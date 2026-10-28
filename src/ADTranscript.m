#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>

// AI 文稿:把当前集音频切成 5 分钟一段 → 语音识别(OpenAI 兼容 /audio/transcriptions)
// → 可选大模型校对(OpenAI 兼容 /chat/completions)→ 按句拆行、带时间戳 → 跟着播放进度高亮滚动。
// 服务商、模型、Key 全由用户在「AI 文稿设置」里填;Key 存 Keychain,不进备份。
// 每集识别一次就缓存到 Documents/transcripts/<trackId>.json,重听不再花钱;中途断了下次从断点续。

static NSString *const kTRChanged = @"ADTranscriptChanged";
static const double kChunkSec = 300;

// ───────────── Keychain ─────────────
static NSDictionary *ADTRKCBase(NSString *acct) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"ad.transcript",
             (__bridge id)kSecAttrAccount: acct};
}
static NSString *ADTRKeyGet(NSString *acct) {
    NSMutableDictionary *q = [ADTRKCBase(acct) mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess || !out) return @"";
    NSData *d = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}
static void ADTRKeySet(NSString *acct, NSString *v) {
    SecItemDelete((__bridge CFDictionaryRef)ADTRKCBase(acct));
    if (!v.length) return;
    NSMutableDictionary *a = [ADTRKCBase(acct) mutableCopy];
    a[(__bridge id)kSecValueData] = [v dataUsingEncoding:NSUTF8StringEncoding];
    a[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)a, NULL);
}

static NSString *ADTRDef(NSString *k) {
    NSString *s = [NSUserDefaults.standardUserDefaults stringForKey:k];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
static NSURL *ADTREndpoint(NSString *base, NSString *suffix) {
    NSString *b = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    if (![b hasSuffix:suffix]) b = [b stringByAppendingString:suffix];
    return [NSURL URLWithString:b];
}
static NSString *ADTRDir(void) {
    NSString *d = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/transcripts"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString *ADTRPath(NSString *tid) { return [ADTRDir() stringByAppendingPathComponent:[tid stringByAppendingString:@".json"]]; }

// ───────────── 一行文稿 ─────────────
@interface ADTLine : NSObject
@property (nonatomic, assign) double start, end;
@property (nonatomic, copy) NSString *text;
@end
@implementation ADTLine
+ (instancetype)s:(double)s e:(double)e t:(NSString *)t { ADTLine *l = [ADTLine new]; l.start = s; l.end = e; l.text = t; return l; }
@end

// 按标点/长度拆成短句(和喜马拉雅那种一行一短句一样)
static NSArray<NSString *> *ADTRSplit(NSString *s) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    NSCharacterSet *hard = [NSCharacterSet characterSetWithCharactersInString:@"。！？!?；;…\n"];
    NSCharacterSet *soft = [NSCharacterSet characterSetWithCharactersInString:@"，,、：: "];
    NSCharacterSet *trim = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *ch, NSRange r, NSRange er, BOOL *stop) {
        [cur appendString:ch];
        unichar c = [ch characterAtIndex:0];
        BOOL h = [hard characterIsMember:c];
        BOOL so = [soft characterIsMember:c] && cur.length >= 12;
        if (h || so || cur.length >= 30) {
            NSString *t = [cur stringByTrimmingCharactersInSet:trim];
            if (t.length > 1 || (t.length == 1 && out.count == 0)) [out addObject:t];
            else if (t.length == 1 && out.count) out[out.count - 1] = [out.lastObject stringByAppendingString:t];
            [cur setString:@""];
        }
    }];
    NSString *t = [cur stringByTrimmingCharactersInSet:trim];
    if (t.length) [out addObject:t];
    return out;
}
// 一段(带起止时间)拆成多行,时间按字数比例分
static void ADTRDistribute(NSString *text, double s, double e, NSMutableArray<ADTLine *> *into) {
    NSArray *ps = ADTRSplit(text ?: @"");
    if (!ps.count) return;
    NSUInteger total = 0; for (NSString *p in ps) total += p.length;
    double t = s, span = MAX(0.1, e - s);
    for (NSString *p in ps) {
        double d = total ? span * p.length / (double)total : span / ps.count;
        [into addObject:[ADTLine s:t e:t + d t:p]];
        t += d;
    }
}

// ───────────── 识别任务 ─────────────
@interface ADTJob : NSObject
@property (nonatomic, strong) ADTrack *track;
@property (nonatomic, strong) ADAlbum *album;
@property (nonatomic, strong) NSURL *file;
@property (nonatomic, assign) BOOL tempFile;
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) NSInteger chunks, next;
@property (nonatomic, strong) NSMutableArray<ADTLine *> *lines;
@property (nonatomic, assign) double chunkSec;
@property (nonatomic, assign) BOOL qwen;                       // 阿里百炼 qwen3-asr:30 秒一段 wav,走 chat/completions
@property (nonatomic, strong) NSMutableArray *pending;         // 等待批量校对的段(每段一个 {start,end,text})
@property (nonatomic, assign) NSInteger groupStart;            // pending 对应的第一行在 lines 里的位置
@end
@implementation ADTJob @end

@interface ADTranscriber : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *status;   // trackId → 进度 / ✗错误
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<ADTLine *> *> *mem;
@property (nonatomic, strong) NSMutableArray<ADTJob *> *queue;
@property (nonatomic, strong) ADTJob *running;
@property (nonatomic, strong) NSHashTable *views;
- (BOOL)anyLive;
+ (instancetype)shared;
@end

@implementation ADTranscriber
+ (instancetype)shared { static ADTranscriber *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [ADTranscriber new]; s.status = [NSMutableDictionary dictionary]; s.mem = [NSMutableDictionary dictionary]; s.queue = [NSMutableArray array]; s.views = [NSHashTable weakObjectsHashTable]; }); return s; }

+ (BOOL)configured { return ADTRDef(@"ad_asr_base").length > 0 && ADTRDef(@"ad_asr_model").length > 0; }
+ (BOOL)isQwen {
    NSString *b = ADTRDef(@"ad_asr_base").lowercaseString;
    return [b containsString:@"dashscope"] || [b containsString:@"aliyuncs"];
}

- (void)post:(NSString *)tid { dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:kTRChanged object:tid]; }); }
- (void)setState:(NSString *)s for:(NSString *)tid { dispatch_async(dispatch_get_main_queue(), ^{ if (s) self.status[tid] = s; else [self.status removeObjectForKey:tid]; [self post:tid]; }); }

// 文件格式:{"v":1,"lines":[[s,e,"t"],…],"next":k,"chunks":n}
- (NSDictionary *)rawFor:(NSString *)tid {
    NSData *d = [NSData dataWithContentsOfFile:ADTRPath(tid)];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : nil;
}
- (NSArray<ADTLine *> *)linesFor:(NSString *)tid {
    if (!tid.length) return @[];
    NSArray *m = self.mem[tid];
    if (m) return m;
    NSMutableArray *out = [NSMutableArray array];
    for (id row in [self rawFor:tid][@"lines"]) {
        if (![row isKindOfClass:NSArray.class] || [row count] < 3) continue;
        [out addObject:[ADTLine s:[row[0] doubleValue] e:[row[1] doubleValue] t:[row[2] description]]];
    }
    if (out.count) { if (self.mem.count > 6) [self.mem removeAllObjects]; self.mem[tid] = out; }
    return out;
}
- (BOOL)isDone:(NSString *)tid {
    NSDictionary *r = [self rawFor:tid];
    return r && [r[@"next"] integerValue] >= [r[@"chunks"] integerValue] && [r[@"chunks"] integerValue] > 0;
}
- (void)save:(ADTJob *)j {
    NSMutableArray *rows = [NSMutableArray array];
    for (ADTLine *l in j.lines) [rows addObject:@[@(round(l.start * 100) / 100), @(round(l.end * 100) / 100), l.text ?: @""]];
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"v": @1, @"lines": rows, @"next": @(j.next), @"chunks": @(j.chunks), @"title": j.track.title ?: @""} options:0 error:nil];
    [d writeToFile:ADTRPath(j.track.trackId) atomically:YES];
    NSArray *copy = [j.lines copy];
    NSString *tid = j.track.trackId;
    dispatch_async(dispatch_get_main_queue(), ^{ self.mem[tid] = copy; [self post:tid]; });
}

- (NSString *)statusFor:(NSString *)tid { return self.status[tid]; }
- (BOOL)anyLive {
    for (UIView *v in self.views) if (v.window && !v.hidden) return YES;
    return NO;
}

- (void)request:(ADTrack *)t album:(ADAlbum *)a front:(BOOL)front {
    if (!t.trackId.length || ![ADTranscriber configured]) return;
    if ([self isDone:t.trackId]) return;
    if ([self.running.track.trackId isEqualToString:t.trackId]) return;
    for (ADTJob *q in self.queue) if ([q.track.trackId isEqualToString:t.trackId]) return;
    if ([self.status[t.trackId] hasPrefix:@"✗"]) return;       // 失败过:等用户点重试
    ADTJob *j = [ADTJob new]; j.track = t; j.album = a; j.lines = [NSMutableArray array];
    if (front) [self.queue insertObject:j atIndex:0]; else [self.queue addObject:j];
    while (self.queue.count > 3) [self.queue removeLastObject];
    [self setState:@"排队中…" for:t.trackId];
    [self pump];
}
- (void)retry:(ADTrack *)t album:(ADAlbum *)a {
    [self.status removeObjectForKey:t.trackId];
    [self request:t album:a front:YES];
}
- (void)clearAll {
    [NSFileManager.defaultManager removeItemAtPath:ADTRDir() error:nil];
    [self.mem removeAllObjects];
    [self.status removeAllObjects];
}

- (void)pump {
    if (self.running || !self.queue.count) return;
    ADTJob *j = self.queue.firstObject;
    [self.queue removeObjectAtIndex:0];
    self.running = j;
    ADLogTag(@"AI", @"开始识别 %@", j.track.title ?: j.track.trackId);
    [self setState:@"正在获取音频…" for:j.track.trackId];
    __weak typeof(self) w = self;
    [self audioFor:j.track done:^(NSURL *file, BOOL temp, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (!file) { [self fail:j msg:err ?: @"取不到音频"]; return; }
        j.file = file; j.tempFile = temp;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
            double dur = CMTimeGetSeconds(asset.duration);
            if (isnan(dur) || dur <= 0) dur = 0;
            j.duration = dur;
            j.qwen = [ADTranscriber isQwen];
            j.chunkSec = j.qwen ? 30 : kChunkSec;
            j.chunks = dur > 0 ? (NSInteger)ceil(dur / j.chunkSec) : 1;
            j.next = 0;
            // 上次做到一半:从断点续(已识别的行保留)
            NSDictionary *old = [self rawFor:j.track.trackId];
            if (old && [old[@"chunks"] integerValue] == j.chunks && [old[@"next"] integerValue] > 0) {
                j.next = [old[@"next"] integerValue];
                for (id row in old[@"lines"]) if ([row isKindOfClass:NSArray.class] && [row count] >= 3)
                    [j.lines addObject:[ADTLine s:[row[0] doubleValue] e:[row[1] doubleValue] t:[row[2] description]]];
                ADLogTag(@"AI", @"从第 %ld/%ld 段续识别", (long)j.next + 1, (long)j.chunks);
            }
            [self chunk:j];
        });
    }];
}

- (void)finish:(ADTJob *)j {
    if (j.tempFile) [NSFileManager.defaultManager removeItemAtURL:j.file error:nil];
    ADLogTag(@"AI", @"识别完成 %@ · %lu 行", j.track.title ?: @"", (unsigned long)j.lines.count);
    [self setState:nil for:j.track.trackId];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = nil;
        // 文稿开着、而且刚做完的是正在播的这集:顺手把下一集也识别了,切集时就不用等
        ADPlayer *p = ADPlayer.shared;
        BOOL pre = [NSUserDefaults.standardUserDefaults objectForKey:@"ad_tr_prefetch"] ? [NSUserDefaults.standardUserDefaults boolForKey:@"ad_tr_prefetch"] : YES;
        if (pre && [self anyLive] && [p.current.trackId isEqualToString:j.track.trackId] && p.index + 1 < (NSInteger)p.tracks.count)
            [self request:p.tracks[p.index + 1] album:p.album front:NO];
        [self pump];
    });
}
- (void)fail:(ADTJob *)j msg:(NSString *)m {
    if (j.tempFile && j.file) [NSFileManager.defaultManager removeItemAtURL:j.file error:nil];
    ADLogError(@"AI", @"✗ 文稿失败 %@ · %@", j.track.title ?: @"", m);
    if (j.lines.count) [self save:j];
    [self setState:[@"✗ " stringByAppendingString:m] for:j.track.trackId];
    dispatch_async(dispatch_get_main_queue(), ^{ self.running = nil; [self pump]; });
}

// 逐段:导出 5 分钟 → 识别 → 校对 → 落盘 → 下一段
- (void)chunk:(ADTJob *)j {
    if (j.qwen) { [self chunkQ:j]; return; }
    if (j.next >= j.chunks) { [self save:j]; [self finish:j]; return; }
    NSInteger k = j.next;
    [self setState:(j.chunks > 1 ? [NSString stringWithFormat:@"AI 识别中 %ld/%ld…", (long)k + 1, (long)j.chunks] : @"AI 识别中…") for:j.track.trackId];
    __weak typeof(self) w = self;
    [self exportChunk:j index:k done:^(NSURL *part, BOOL temp, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (!part) { [self fail:j msg:err ?: @"音频切段失败"]; return; }
        double off = (j.chunks > 1) ? k * j.chunkSec : 0;
        double len = j.duration > 0 ? MIN(j.chunkSec, j.duration - off) : 0;
        [self asr:part album:j.album verbose:YES done:^(NSArray *segs, NSString *aerr) {
            if (temp) [NSFileManager.defaultManager removeItemAtURL:part error:nil];
            if (!segs) { [self fail:j msg:aerr ?: @"识别失败"]; return; }
            void (^commit)(NSArray *) = ^(NSArray *fixed) {
                NSMutableArray *rows = [NSMutableArray array];
                for (NSDictionary *s in fixed) {
                    double ss = [s[@"start"] doubleValue], ee = [s[@"end"] doubleValue];
                    if (ee <= ss) ee = ss + 1;
                    ADTRDistribute(s[@"text"], off + ss, off + ee, rows);
                }
                [j.lines addObjectsFromArray:rows];
                j.next = k + 1;
                [self save:j];
                [self chunk:j];
            };
            // 只有纯文本没有分段时间:整段时长按字数平均分
            if (segs.count == 1 && [segs[0][@"end"] doubleValue] <= 0) {
                NSMutableDictionary *m = [segs[0] mutableCopy]; m[@"end"] = @(len > 0 ? len : 60); segs = @[m];
            }
            if ([NSUserDefaults.standardUserDefaults boolForKey:@"ad_llm_on"] && ADTRDef(@"ad_llm_model").length) {
                [self setState:(j.chunks > 1 ? [NSString stringWithFormat:@"AI 校对中 %ld/%ld…", (long)k + 1, (long)j.chunks] : @"AI 校对中…") for:j.track.trackId];
                [self correct:segs album:j.album done:commit];
            } else commit(segs);
        }];
    }];
}

// ── 取音频:已下载 / 已预取的直接用,否则临时下载一份 ──
- (void)audioFor:(ADTrack *)t done:(void (^)(NSURL *, BOOL, NSString *))cb {
    NSURL *local = [[ADDownloader shared] localURL:t.trackId];
    if (!local) {
        NSString *pp = [ADPlayer.shared prefetchPath:t.trackId];
        if ([NSFileManager.defaultManager fileExistsAtPath:pp]) local = [NSURL fileURLWithPath:pp];
    }
    if (local) { cb(local, NO, nil); return; }
    [[ADApi shared] playURLOf:t done:^(NSString *url, NSDictionary *headers, NSString *err) {
        if (!url.length) { cb(nil, NO, err ?: @"取不到音频地址"); return; }
        NSURL *u = [url hasPrefix:@"/"] ? [NSURL fileURLWithPath:url] : [NSURL URLWithString:url];
        if (u.isFileURL) { cb(u, NO, nil); return; }
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
        r.timeoutInterval = 120;
        [headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) {
            if ([k isKindOfClass:NSString.class] && [v isKindOfClass:NSString.class]) [r setValue:v forHTTPHeaderField:k];
        }];
        [[NSURLSession.sharedSession downloadTaskWithRequest:r completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *e) {
            if (!loc || e) { dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, NO, e.localizedDescription ?: @"音频下载失败"); }); return; }
            NSData *head = [[NSFileHandle fileHandleForReadingFromURL:loc error:nil] readDataOfLength:12];
            const uint8_t *b = head.bytes;
            NSString *ext = (head.length >= 8 && b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') ? @"m4a" : @"mp3";
            NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tr-%@.%@", t.trackId, ext]]];
            [NSFileManager.defaultManager removeItemAtURL:dst error:nil];
            [NSFileManager.defaultManager moveItemAtURL:loc toURL:dst error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ cb(dst, YES, nil); });
        }] resume];
    }];
}

// ── 切段:单段且文件不大时原样上传;否则导出成 m4a ──
- (void)exportChunk:(ADTJob *)j index:(NSInteger)k done:(void (^)(NSURL *, BOOL, NSString *))cb {
    unsigned long long size = [[NSFileManager.defaultManager attributesOfItemAtPath:j.file.path error:nil] fileSize];
    if (j.chunks <= 1 && size < 24 * 1024 * 1024) { cb(j.file, NO, nil); return; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:j.file options:nil];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!ex) { cb(nil, NO, @"系统不支持导出这个音频"); return; }
    NSURL *out = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"trc-%@-%ld.m4a", j.track.trackId, (long)k]]];
    [NSFileManager.defaultManager removeItemAtURL:out error:nil];
    ex.outputURL = out;
    ex.outputFileType = AVFileTypeAppleM4A;
    double off = k * j.chunkSec;
    ex.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(off, 600), CMTimeMakeWithSeconds(MIN(j.chunkSec, MAX(1, j.duration - off)), 600));
    [ex exportAsynchronouslyWithCompletionHandler:^{
        if (ex.status == AVAssetExportSessionStatusCompleted) cb(out, YES, nil);
        else cb(nil, NO, [NSString stringWithFormat:@"音频切段失败 %@", ex.error.localizedDescription ?: @""]);
    }];
}

// ── 语音识别:OpenAI 兼容 multipart ──
- (void)asr:(NSURL *)file album:(ADAlbum *)a verbose:(BOOL)verbose done:(void (^)(NSArray *, NSString *))cb {
    NSURL *url = ADTREndpoint(ADTRDef(@"ad_asr_base"), @"/audio/transcriptions");
    if (!url) { cb(nil, @"识别接口地址不对"); return; }
    NSString *key = ADTRKeyGet(@"asr");
    NSString *bd = [NSString stringWithFormat:@"----ADTR%08X%08X", arc4random(), arc4random()];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 300;
    [r setValue:[@"multipart/form-data; boundary=" stringByAppendingString:bd] forHTTPHeaderField:@"Content-Type"];
    if (key.length) [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    NSMutableData *body = [NSMutableData data];
    void (^field)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", bd, n, v] dataUsingEncoding:NSUTF8StringEncoding]];
    };
    field(@"model", ADTRDef(@"ad_asr_model"));
    NSString *lang = ADTRDef(@"ad_asr_lang");
    if (lang.length) field(@"language", lang);
    if (verbose) { field(@"response_format", @"verbose_json"); field(@"timestamp_granularities[]", @"segment"); }
    else field(@"response_format", @"json");
    // 提示词:书名 + 已知人名,能明显提高人名/专有名词的识别率
    NSArray *names = [self namesOf:a.albumId];
    NSString *prompt = [NSString stringWithFormat:@"以下是有声书《%@》的朗读,使用简体中文和标点。%@", a.title ?: @"",
                        names.count ? [NSString stringWithFormat:@"人物:%@。", [names componentsJoinedByString:@"、"]] : @""];
    if (prompt.length > 200) prompt = [prompt substringToIndex:200];
    field(@"prompt", prompt);
    NSData *audio = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
    if (!audio.length) { cb(nil, @"读不到音频文件"); return; }
    NSString *ext = file.pathExtension.lowercaseString.length ? file.pathExtension.lowercaseString : @"mp3";
    NSString *mime = [ext isEqualToString:@"mp3"] ? @"audio/mpeg" : @"audio/mp4";
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.%@\"\r\nContent-Type: %@\r\n\r\n", bd, ext, mime] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:audio];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", bd] dataUsingEncoding:NSUTF8StringEncoding]];
    CFTimeInterval t0 = CACurrentMediaTime();
    ADLogTag(@"AI", @"→ 识别 %@ %.1fMB", url.host ?: @"", audio.length / 1048576.0);
    __weak typeof(self) w = self;
    [[NSURLSession.sharedSession uploadTaskWithRequest:r fromData:body completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
        __strong typeof(w) self = w; if (!self) return;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (e) { cb(nil, e.localizedDescription); return; }
        id j = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (code < 200 || code >= 300) {
            // 有的模型(如 gpt-4o-transcribe)不支持 verbose_json:降级成纯文本再试一次
            if (verbose && code == 400) { ADLogWarn(@"AI", @"接口不支持分段时间,改用纯文本"); [self asr:file album:a verbose:NO done:cb]; return; }
            NSString *msg = [j isKindOfClass:NSDictionary.class] ? ([j[@"error"] isKindOfClass:NSDictionary.class] ? j[@"error"][@"message"] : [j[@"error"] description]) : nil;
            if (!msg.length) msg = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(160, data.length))] encoding:NSUTF8StringEncoding];
            if (code == 404 && !msg.length) msg = @"这个地址下没有语音识别接口,请确认服务商支持 /audio/transcriptions";
            cb(nil, [NSString stringWithFormat:@"识别接口 %ld:%@", (long)code, msg ?: @""]);
            return;
        }
        ADLogTag(@"AI", @"← 识别 %ld %.0fs", (long)code, CACurrentMediaTime() - t0);
        NSMutableArray *segs = [NSMutableArray array];
        if ([j isKindOfClass:NSDictionary.class] && [j[@"segments"] isKindOfClass:NSArray.class]) {
            for (NSDictionary *s in j[@"segments"]) {
                if (![s isKindOfClass:NSDictionary.class]) continue;
                NSString *tx = [s[@"text"] description];
                if (!tx.length) continue;
                [segs addObject:@{@"start": s[@"start"] ?: @0, @"end": s[@"end"] ?: @0, @"text": tx}];
            }
        }
        if (!segs.count) {
            NSString *tx = [j isKindOfClass:NSDictionary.class] ? [j[@"text"] description] : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!tx.length) { cb(nil, @"识别结果为空"); return; }
            [segs addObject:@{@"start": @0, @"end": @0, @"text": tx}];
        }
        cb(segs, nil);
    }] resume];
}

// ── 阿里百炼 qwen3-asr-flash ──
// 兼容接口只返回整段文字,没有时间戳:所以每 30 秒一段,段起止时间已知,段内按字数分行。
static NSData *ADTRWav(NSURL *file, double off, double len) {
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:file options:nil];
    AVAssetTrack *trk = [[as tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!trk) return nil;
    AVAssetReader *rd = [[AVAssetReader alloc] initWithAsset:as error:nil];
    if (!rd) return nil;
    rd.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(off, 600), CMTimeMakeWithSeconds(len, 600));
    NSDictionary *st = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @16000, AVNumberOfChannelsKey: @1,
                         AVLinearPCMBitDepthKey: @16, AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO};
    AVAssetReaderTrackOutput *out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trk outputSettings:st];
    [rd addOutput:out];
    if (![rd startReading]) return nil;
    NSMutableData *pcm = [NSMutableData data];
    CMSampleBufferRef sb;
    while ((sb = [out copyNextSampleBuffer])) {
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
        size_t n = bb ? CMBlockBufferGetDataLength(bb) : 0;
        if (n) { NSMutableData *tmp = [NSMutableData dataWithLength:n]; CMBlockBufferCopyDataBytes(bb, 0, n, tmp.mutableBytes); [pcm appendData:tmp]; }
        CFRelease(sb);
    }
    if (pcm.length < 3200) return nil;
    uint32_t dl = (uint32_t)pcm.length, rl = dl + 36, sr = 16000, br = 32000, fl = 16;
    uint16_t fmt = 1, ch = 1, ba = 2, bits = 16;
    NSMutableData *w = [NSMutableData dataWithCapacity:44 + pcm.length];
    [w appendBytes:"RIFF" length:4]; [w appendBytes:&rl length:4]; [w appendBytes:"WAVEfmt " length:8];
    [w appendBytes:&fl length:4]; [w appendBytes:&fmt length:2]; [w appendBytes:&ch length:2];
    [w appendBytes:&sr length:4]; [w appendBytes:&br length:4]; [w appendBytes:&ba length:2]; [w appendBytes:&bits length:2];
    [w appendBytes:"data" length:4]; [w appendBytes:&dl length:4]; [w appendData:pcm];
    return w;
}

- (void)asrQwen:(NSData *)wav album:(ADAlbum *)a context:(BOOL)ctx done:(void (^)(NSString *, NSString *))cb {
    NSURL *url = ADTREndpoint(ADTRDef(@"ad_asr_base"), @"/chat/completions");
    if (!url) { cb(nil, @"识别接口地址不对"); return; }
    NSString *key = ADTRKeyGet(@"asr");
    NSMutableArray *msgs = [NSMutableArray array];
    if (ctx) {
        NSArray *names = [self namesOf:a.albumId];
        NSString *c = [NSString stringWithFormat:@"有声书《%@》的朗读。%@", a.title ?: @"", names.count ? [NSString stringWithFormat:@"人物:%@。", [names componentsJoinedByString:@"、"]] : @""];
        if (c.length > 300) c = [c substringToIndex:300];
        [msgs addObject:@{@"role": @"system", @"content": c}];
    }
    NSString *dataURL = [@"data:audio/wav;base64," stringByAppendingString:[wav base64EncodedStringWithOptions:0]];
    [msgs addObject:@{@"role": @"user", @"content": @[@{@"type": @"input_audio", @"input_audio": @{@"data": dataURL}}]}];
    NSMutableDictionary *opts = [@{@"enable_itn": @NO} mutableCopy];
    NSString *lang = ADTRDef(@"ad_asr_lang");
    if (lang.length) opts[@"language"] = lang;
    NSDictionary *payload = @{@"model": ADTRDef(@"ad_asr_model"), @"messages": msgs, @"stream": @NO, @"asr_options": opts};
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 90;
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (key.length) [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    __weak typeof(self) w = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
        __strong typeof(w) self = w; if (!self) return;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (e) { cb(nil, e.localizedDescription); return; }
        id j = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (code < 200 || code >= 300) {
            // 带 system 上下文被拒:去掉上下文再试一次(不确定这个模型是否接受 system 消息)
            if (ctx && code == 400) { ADLogWarn(@"AI", @"接口不接受上下文提示,去掉后重试"); [self asrQwen:wav album:a context:NO done:cb]; return; }
            NSString *msg = nil;
            if ([j isKindOfClass:NSDictionary.class]) {
                id er = j[@"error"];
                msg = [er isKindOfClass:NSDictionary.class] ? [er[@"message"] description] : ([j[@"message"] description] ?: ([er description]));
            }
            if (!msg.length && data.length) msg = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(160, data.length))] encoding:NSUTF8StringEncoding];
            if (code == 401) msg = [@"Key 不对或没开通 " stringByAppendingString:msg ?: @""];
            if (code == 404 && !msg.length) msg = @"接口地址或模型名不对";
            cb(nil, [NSString stringWithFormat:@"识别接口 %ld:%@", (long)code, msg ?: @""]);
            return;
        }
        NSString *content = nil;
        id ch = [j isKindOfClass:NSDictionary.class] && [j[@"choices"] isKindOfClass:NSArray.class] ? [j[@"choices"] firstObject] : nil;
        id msg = [ch isKindOfClass:NSDictionary.class] ? ch[@"message"] : nil;
        id ct = [msg isKindOfClass:NSDictionary.class] ? msg[@"content"] : nil;
        if ([ct isKindOfClass:NSString.class]) content = ct;
        else if ([ct isKindOfClass:NSArray.class]) { NSMutableString *m = [NSMutableString string]; for (id p in ct) if ([p isKindOfClass:NSDictionary.class] && p[@"text"]) [m appendString:[p[@"text"] description]]; content = m; }
        cb(content ?: @"", nil);   // 静音段返回空串是正常的
    }] resume];
}

// 阿里模式的主循环:30 秒一段 → 识别 → 立即显示;每满 6 段(约 3 分钟)批量校对一次,校对好了替换这几行
- (void)chunkQ:(ADTJob *)j {
    if (j.next >= j.chunks) { [self correctGroup:j done:^{ [self save:j]; [self finish:j]; }]; return; }
    NSInteger k = j.next;
    [self setState:[NSString stringWithFormat:@"AI 识别中 %ld/%ld…", (long)k + 1, (long)j.chunks] for:j.track.trackId];
    double off = k * j.chunkSec;
    double len = j.duration > 0 ? MIN(j.chunkSec, j.duration - off) : j.chunkSec;
    if (len < 0.4) { j.next = k + 1; [self chunkQ:j]; return; }
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(w) self = w; if (!self) return;
        NSData *wav = ADTRWav(j.file, off, len);
        if (!wav.length) {
            // 这一段读不出来(多半是尾部太短或静音):跳过,不让整集失败
            ADLogWarn(@"AI", @"第 %ld 段音频转码为空,跳过", (long)k + 1);
            j.next = k + 1; [self chunkQ:j]; return;
        }
        [self asrQwen:wav album:j.album context:YES done:^(NSString *text, NSString *err) {
            if (!text) { [self fail:j msg:err ?: @"识别失败"]; return; }
            NSString *tx = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            BOOL llm = [NSUserDefaults.standardUserDefaults boolForKey:@"ad_llm_on"] && ADTRDef(@"ad_llm_model").length;
            if (tx.length) {
                if (llm) {
                    if (!j.pending) j.pending = [NSMutableArray array];
                    if (!j.pending.count) j.groupStart = j.lines.count;
                    [j.pending addObject:@{@"start": @(off), @"end": @(off + len), @"text": tx}];
                }
                ADTRDistribute(tx, off, off + len, j.lines);
            }
            j.next = k + 1;
            [self save:j];
            if (j.pending.count >= 6) [self correctGroup:j done:^{ [self chunkQ:j]; }];
            else [self chunkQ:j];
        }];
    });
}
- (void)correctGroup:(ADTJob *)j done:(void (^)(void))done {
    NSArray *segs = [j.pending copy];
    if (!segs.count) { done(); return; }
    [j.pending removeAllObjects];
    [self setState:@"AI 校对中…" for:j.track.trackId];
    [self correct:segs album:j.album done:^(NSArray *fixed) {
        // correct: 失败时回传的就是原数组对象;成功才替换这几段已显示的行
        if (fixed != segs && j.groupStart <= (NSInteger)j.lines.count) {
            [j.lines removeObjectsInRange:NSMakeRange(j.groupStart, j.lines.count - j.groupStart)];
            for (NSDictionary *sg in fixed) ADTRDistribute(sg[@"text"], [sg[@"start"] doubleValue], [sg[@"end"] doubleValue], j.lines);
            [self save:j];
        }
        done();
    }];
}

// ── 大模型校对:只改错字/人名/标点,行数必须一致,对不上就用原文 ──
- (NSArray *)namesOf:(NSString *)albumId {
    NSDictionary *all = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"ad_tr_names"];
    NSArray *n = albumId.length ? all[albumId] : nil;
    return [n isKindOfClass:NSArray.class] ? n : @[];
}
- (void)addNames:(NSArray *)names album:(NSString *)albumId {
    if (!albumId.length || ![names isKindOfClass:NSArray.class] || !names.count) return;
    NSMutableOrderedSet *s = [NSMutableOrderedSet orderedSetWithArray:[self namesOf:albumId]];
    for (id n in names) if ([n isKindOfClass:NSString.class] && [n length] >= 2 && [n length] <= 8) [s addObject:n];
    while (s.count > 60) [s removeObjectAtIndex:0];
    NSMutableDictionary *all = [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ad_tr_names"] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[albumId] = s.array;
    [NSUserDefaults.standardUserDefaults setObject:all forKey:@"ad_tr_names"];
}

- (void)correct:(NSArray *)segs album:(ADAlbum *)a done:(void (^)(NSArray *))done {
    NSString *base = ADTRDef(@"ad_llm_base");
    NSString *key = ADTRKeyGet(@"llm");
    if (!base.length) { base = ADTRDef(@"ad_asr_base"); if (!key.length) key = ADTRKeyGet(@"asr"); }
    NSURL *url = ADTREndpoint(base, @"/chat/completions");
    if (!url) { done(segs); return; }
    NSMutableString *numbered = [NSMutableString string];
    for (NSUInteger i = 0; i < segs.count; i++) [numbered appendFormat:@"%lu\t%@\n", (unsigned long)i + 1, [segs[i][@"text"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    NSString *intro = a.intro.length > 200 ? [a.intro substringToIndex:200] : (a.intro ?: @"");
    NSArray *names = [self namesOf:a.albumId];
    NSString *sys = @"你是有声书文稿校对员。输入是语音识别得到的逐行文本,每行以编号和制表符开头。"
                    @"只做这些修改:改正同音错字和错别字;让人名、地名、专有名词前后一致;补上中文标点;繁体改简体。"
                    @"不要增删内容,不要改写措辞,不要合并或拆分行。"
                    @"只输出 JSON:{\"lines\":[与输入行数相同、顺序相同的字符串,不带编号],\"names\":[文中出现的人名和专有名词]}";
    NSString *user = [NSString stringWithFormat:@"书名:%@\n简介:%@\n已知人名:%@\n共 %lu 行:\n%@", a.title ?: @"", intro,
                      names.count ? [names componentsJoinedByString:@"、"] : @"无", (unsigned long)segs.count, numbered];
    NSDictionary *payload = @{@"model": ADTRDef(@"ad_llm_model"), @"temperature": @0.1,
                              @"messages": @[@{@"role": @"system", @"content": sys}, @{@"role": @"user", @"content": user}]};
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 180;
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (key.length) [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    CFTimeInterval t0 = CACurrentMediaTime();
    __weak typeof(self) w = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
        __strong typeof(w) self = w; if (!self) return;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        id j = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *content = nil;
        if ([j isKindOfClass:NSDictionary.class]) {
            id ch = [j[@"choices"] isKindOfClass:NSArray.class] ? [j[@"choices"] firstObject] : nil;
            id msg = [ch isKindOfClass:NSDictionary.class] ? ch[@"message"] : nil;
            content = [msg isKindOfClass:NSDictionary.class] ? [msg[@"content"] description] : nil;
        }
        if (e || code < 200 || code >= 300 || !content.length) {
            ADLogWarn(@"AI", @"校对没成功(%ld %@),用识别原文", (long)code, e.localizedDescription ?: @"");
            done(segs); return;
        }
        NSRange l = [content rangeOfString:@"{"], rr = [content rangeOfString:@"}" options:NSBackwardsSearch];
        NSDictionary *o = nil;
        if (l.location != NSNotFound && rr.location != NSNotFound && rr.location > l.location) {
            NSData *jd = [[content substringWithRange:NSMakeRange(l.location, rr.location - l.location + 1)] dataUsingEncoding:NSUTF8StringEncoding];
            o = [NSJSONSerialization JSONObjectWithData:jd options:0 error:nil];
        }
        NSArray *lines = [o isKindOfClass:NSDictionary.class] ? o[@"lines"] : nil;
        if (![lines isKindOfClass:NSArray.class] || lines.count != segs.count) {
            ADLogWarn(@"AI", @"校对返回行数不一致(%lu/%lu),用识别原文", (unsigned long)([lines isKindOfClass:NSArray.class] ? lines.count : 0), (unsigned long)segs.count);
            done(segs); return;
        }
        [self addNames:o[@"names"] album:a.albumId];
        NSMutableArray *fixed = [NSMutableArray array];
        for (NSUInteger i = 0; i < segs.count; i++) {
            NSMutableDictionary *m = [segs[i] mutableCopy];
            NSString *tx = [lines[i] description];
            if (tx.length) m[@"text"] = tx;
            [fixed addObject:m];
        }
        ADLogTag(@"AI", @"← 校对 %ld %.0fs · %lu 行", (long)code, CACurrentMediaTime() - t0, (unsigned long)segs.count);
        done(fixed);
    }] resume];
}
@end

// ───────────── 文稿视图(播放页内嵌 + 全屏共用)─────────────
@interface ADTranscriptView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIButton *action, *expand;
@property (nonatomic, strong) NSArray<ADTLine *> *lines;
@property (nonatomic, copy) NSString *tid;
@property (nonatomic, assign) NSInteger cur;
@property (nonatomic, assign) BOOL full;
@property (nonatomic, assign) double userScrollAt;
@property (nonatomic, strong) CAGradientLayer *fade;
@end

@implementation ADTranscriptView

- (instancetype)initFull:(BOOL)full {
    if ((self = [super initWithFrame:CGRectZero])) {
        _full = full; _cur = -1;
        self.backgroundColor = UIColor.clearColor;
        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.backgroundColor = UIColor.clearColor;
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.showsVerticalScrollIndicator = NO;
        _table.dataSource = self; _table.delegate = self;
        _table.estimatedRowHeight = 0;
        [self addSubview:_table];
        if (!full) {
            _fade = [CAGradientLayer layer];
            _fade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
            _fade.locations = @[@0, @0.18, @0.78, @1];
            self.layer.mask = _fade;
        }
        _hint = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.55]];
        _hint.textAlignment = NSTextAlignmentCenter;
        _hint.numberOfLines = 0;
        [self addSubview:_hint];
        _action = [UIButton buttonWithType:UIButtonTypeSystem];
        _action.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _action.tintColor = UIColor.whiteColor;
        _action.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        _action.layer.cornerRadius = 16;
        [_action addTarget:self action:@selector(tapAction) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_action];
        if (!full) {
            _expand = [UIButton buttonWithType:UIButtonTypeSystem];
            [_expand setTitle:@"展开" forState:UIControlStateNormal];
            _expand.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            _expand.tintColor = [UIColor colorWithWhite:1 alpha:0.75];
            _expand.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
            _expand.layer.cornerRadius = 11;
            [_expand addTarget:self action:@selector(tapExpand) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:_expand];
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:kTRChanged object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadForTrack) name:@"ADPlayerChanged" object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [[ADTranscriber shared].views addObject:self];
    if (self.window && !self.hidden) [self reloadForTrack];
}
- (void)setHidden:(BOOL)h {
    BOOL was = self.hidden;
    [super setHidden:h];
    if (was && !h && self.window) [self reloadForTrack];   // 切到文稿时才开始识别
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.table.frame = b;
    CGFloat pad = self.full ? b.size.height * 0.4 : b.size.height * 0.36;
    self.table.contentInset = UIEdgeInsetsMake(pad, 0, pad, 0);
    self.fade.frame = b;
    self.hint.frame = CGRectMake(24, b.size.height / 2 - 46, b.size.width - 48, 50);
    CGFloat aw = 132;
    self.action.frame = CGRectMake((b.size.width - aw) / 2, b.size.height / 2 + 12, aw, 32);
    self.expand.frame = CGRectMake(b.size.width - 24 - 48, b.size.height - 26, 48, 22);
}

- (void)reloadForTrack {
    ADPlayer *p = ADPlayer.shared;
    NSString *tid = p.current.trackId;
    if (!tid.length) return;
    BOOL changed = ![tid isEqualToString:self.tid];
    self.tid = tid;
    if (changed) { self.cur = -1; self.userScrollAt = 0; }
    self.lines = [[ADTranscriber shared] linesFor:tid];
    [self.table reloadData];
    if (self.window && !self.hidden && [ADTranscriber configured] && ![[ADTranscriber shared] isDone:tid])
        [[ADTranscriber shared] request:p.current album:p.album front:YES];
    [self refreshHint];
    if (changed) [self tick:YES];
}
- (void)changed:(NSNotification *)n {
    if (n.object && ![n.object isEqual:self.tid]) return;
    NSUInteger before = self.lines.count;
    self.lines = [[ADTranscriber shared] linesFor:self.tid];
    if (self.lines.count != before) { [self.table reloadData]; self.cur = -1; [self tick:YES]; }
    [self refreshHint];
}

- (void)refreshHint {
    ADTranscriber *tr = [ADTranscriber shared];
    NSString *st = [tr statusFor:self.tid];
    BOOL has = self.lines.count > 0;
    NSString *msg = nil, *btn = nil;
    if (![ADTranscriber configured]) { msg = @"AI 文稿还没设置识别模型"; btn = @"去设置"; }
    else if ([st hasPrefix:@"✗"]) { msg = [st substringFromIndex:2]; btn = @"重试"; }
    else if (!has) msg = st ?: @"准备识别…";
    self.hint.hidden = has || !msg;
    self.hint.text = msg;
    self.action.hidden = !btn || (has && ![st hasPrefix:@"✗"]);
    if (has && [st hasPrefix:@"✗"]) self.action.hidden = YES;
    [self.action setTitle:btn forState:UIControlStateNormal];
    self.table.hidden = !has;
    self.expand.hidden = !has;
}

- (void)tapAction {
    [ADHaptic tap];
    if (![ADTranscriber configured]) { [self openSettings]; return; }
    ADPlayer *p = ADPlayer.shared;
    if (p.current) [[ADTranscriber shared] retry:p.current album:p.album];
}
- (void)openSettings {
    UIViewController *vc = [self nearestVC];
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:[ADTranscriptSettingsController new]];
    n.modalPresentationStyle = UIModalPresentationPageSheet;
    [vc presentViewController:n animated:YES completion:nil];
}
- (void)tapExpand {
    [ADHaptic tap];
    ADTranscriptFullController *f = [ADTranscriptFullController new];
    f.modalPresentationStyle = UIModalPresentationPageSheet;
    [[self nearestVC] presentViewController:f animated:YES completion:nil];
}
- (UIViewController *)nearestVC {
    UIResponder *r = self;
    while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
    return (UIViewController *)r;
}

// 播放页每次刷新进度时调用
- (void)tick:(BOOL)force {
    if (!self.lines.count || !self.window) return;
    AVPlayer *pl = ADPlayer.shared.player;
    double t = pl ? CMTimeGetSeconds(pl.currentTime) : 0;
    if (isnan(t)) return;
    NSInteger lo = 0, hi = (NSInteger)self.lines.count - 1, k = 0;
    while (lo <= hi) { NSInteger m = (lo + hi) / 2; if (self.lines[m].start <= t + 0.15) { k = m; lo = m + 1; } else hi = m - 1; }
    if (k == self.cur && !force) return;
    NSInteger old = self.cur;
    self.cur = k;
    NSMutableArray *ips = [NSMutableArray array];
    for (NSNumber *n in @[@(old), @(k)]) if (n.integerValue >= 0 && n.integerValue < (NSInteger)self.lines.count) [ips addObject:[NSIndexPath indexPathForRow:n.integerValue inSection:0]];
    [UIView performWithoutAnimation:^{ [self.table reloadRowsAtIndexPaths:ips withRowAnimation:UITableViewRowAnimationNone]; }];
    // 用户刚手动翻过:4 秒内不抢滚动
    if (CACurrentMediaTime() - self.userScrollAt < 4) return;
    [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:k inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:!force];
}

- (UIFont *)fontFor:(BOOL)on { return on ? [UIFont systemFontOfSize:(self.full ? 22 : 20) weight:UIFontWeightBold] : [UIFont systemFontOfSize:(self.full ? 17 : 15) weight:UIFontWeightRegular]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.lines.count; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    BOOL on = ip.row == self.cur;
    CGFloat w = t.bounds.size.width - 48;
    CGFloat h = [self.lines[ip.row].text boundingRectWithSize:CGSizeMake(w, 400) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [self fontFor:on]} context:nil].size.height;
    return ceil(h) + (self.full ? 22 : 16);
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"tl"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tl"];
        c.backgroundColor = UIColor.clearColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.textLabel.numberOfLines = 0;
        c.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    BOOL on = ip.row == self.cur;
    c.textLabel.text = self.lines[ip.row].text;
    c.textLabel.font = [self fontFor:on];
    c.textLabel.textColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:(self.full ? 0.5 : 0.42)];
    c.separatorInset = UIEdgeInsetsZero;
    c.layoutMargins = UIEdgeInsetsMake(0, 24, 0, 24);
    c.contentView.layoutMargins = UIEdgeInsetsMake(0, 24, 0, 24);
    return c;
}
// 点哪句就从哪句开始播
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic select];
    self.userScrollAt = 0;
    [ADPlayer.shared seekTo:MAX(0, self.lines[ip.row].start)];
    if (!ADPlayer.shared.isPlaying) [ADPlayer.shared toggle];
    self.cur = -1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self tick:YES]; });
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)s { self.userScrollAt = CACurrentMediaTime(); }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)s { self.userScrollAt = CACurrentMediaTime(); }
@end

// ───────────── 全屏文稿 ─────────────
@interface ADTranscriptFullController ()
@property (nonatomic, strong) ADTranscriptView *tv;
@property (nonatomic, strong) UILabel *head;
@property (nonatomic, strong) CADisplayLink *link;
@end
@implementation ADTranscriptFullController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.11 alpha:1];
    if (@available(iOS 15.0, *)) { self.sheetPresentationController.prefersGrabberVisible = YES; self.sheetPresentationController.preferredCornerRadius = 28; }
    self.head = [ADUtil label:@"PingFangSC-Semibold" size:17 color:UIColor.whiteColor];
    self.head.textAlignment = NSTextAlignmentCenter;
    self.head.text = ADPlayer.shared.current.title ?: @"AI 文稿";
    [self.view addSubview:self.head];
    self.tv = [[ADTranscriptView alloc] initFull:YES];
    [self.view addSubview:self.tv];
    UILabel *note = [ADUtil label:nil size:11 color:[UIColor colorWithWhite:1 alpha:0.35]];
    note.text = @"文稿由 AI 识别生成,可能有错漏 · 点任意一句从该处播放";
    note.textAlignment = NSTextAlignmentCenter;
    note.tag = 77;
    [self.view addSubview:note];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step)];
    self.link.preferredFramesPerSecond = 4;
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)viewDidDisappear:(BOOL)a { [super viewDidDisappear:a]; [self.link invalidate]; self.link = nil; }
- (void)step { [self.tv tick:NO]; self.head.text = ADPlayer.shared.current.title ?: @"AI 文稿"; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, bot = self.view.safeAreaInsets.bottom;
    self.head.frame = CGRectMake(24, 26, W - 48, 24);
    self.tv.frame = CGRectMake(0, 60, W, H - 60 - bot - 30);
    [self.view viewWithTag:77].frame = CGRectMake(16, H - bot - 24, W - 32, 16);
}
@end

// ───────────── AI 文稿设置 ─────────────
@interface ADTranscriptSettingsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@end
@implementation ADTranscriptSettingsController

static NSArray *ADTRFields(void) {
    // key, 标题, 占位, 是否密钥
    return @[@[@[@"ad_asr_base", @"接口地址", @"https://api.openai.com/v1", @NO],
               @[@"asr", @"API Key", @"sk-…", @YES],
               @[@"ad_asr_model", @"模型", @"whisper-1 / 你选用的识别模型", @NO],
               @[@"ad_asr_lang", @"语言(可空)", @"zh", @NO]],
             @[@[@"ad_llm_base", @"接口地址(空=同上)", @"https://…/v1", @NO],
               @[@"llm", @"API Key(空=同上)", @"sk-…", @YES],
               @[@"ad_llm_model", @"模型", @"你选用的对话模型", @NO]]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI 文稿";
    self.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.11 alpha:1];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];
}
- (void)done { [self.view endEditing:YES]; [self dismissViewControllerAnimated:YES completion:nil]; [NSNotificationCenter.defaultCenter postNotificationName:kTRChanged object:nil]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == 1) return 1 + ([NSUserDefaults.standardUserDefaults boolForKey:@"ad_llm_on"] ? 3 : 0);
    if (s == 2) return 1;
    return 2;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return @[@"语音识别(OpenAI 兼容 /audio/transcriptions)", @"大模型校对(OpenAI 兼容 /chat/completions)", @"", @"缓存"][s];
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"· OpenAI 兼容(Groq、OpenAI 等):地址填到 /v1,模型如 whisper-large-v3。\n· 阿里百炼:地址 https://dashscope.aliyuncs.com/compatible-mode/v1,模型 qwen3-asr-flash(自动按 30 秒分段)。\nDeepSeek 没有语音识别接口,不能填在这里。Key 存在本机钥匙串,不进备份,也不写进日志。";
    if (s == 1) return @"校对只改错字、统一人名、补标点,不改写内容。会把书名、简介和识别出的人名一起发给模型,人名会越用越准。";
    if (s == 2) return @"打开文稿并听完当前集识别后,自动识别下一集,切集时不用等。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    c.textLabel.textColor = UIColor.whiteColor;
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ((ip.section == 1 && ip.row == 0) || ip.section == 2) {
        NSString *k = ip.section == 1 ? @"ad_llm_on" : @"ad_tr_prefetch";
        c.textLabel.text = ip.section == 1 ? @"启用大模型校对" : @"自动识别下一集";
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = [ADUtil brand];
        sw.on = [d objectForKey:k] ? [d boolForKey:k] : (ip.section == 2);
        sw.tag = ip.section;
        [sw addTarget:self action:@selector(flip:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        return c;
    }
    if (ip.section == 3) {
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (ip.row == 0) {
            NSArray *fs = [NSFileManager.defaultManager contentsOfDirectoryAtPath:ADTRDir() error:nil];
            c.textLabel.text = @"已缓存文稿";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%lu 集", (unsigned long)fs.count];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            c.textLabel.text = @"清空文稿缓存";
            c.textLabel.textColor = [UIColor colorWithRed:1 green:0.42 blue:0.4 alpha:1];
        }
        return c;
    }
    NSArray *f = ADTRFields()[ip.section][ip.section == 1 ? ip.row - 1 : ip.row];
    BOOL secret = [f[3] boolValue];
    c.textLabel.text = f[1];
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, MIN(230, t.bounds.size.width * 0.58), 30)];
    tf.textAlignment = NSTextAlignmentRight;
    tf.textColor = UIColor.whiteColor;
    tf.font = [UIFont systemFontOfSize:14];
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:f[2] attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.3]}];
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.secureTextEntry = secret;
    tf.text = secret ? ADTRKeyGet(f[0]) : [d stringForKey:f[0]];
    tf.accessibilityIdentifier = f[0];
    tf.tag = secret ? 1 : 0;
    tf.delegate = self;
    [tf addTarget:self action:@selector(edited:) forControlEvents:UIControlEventEditingChanged];
    c.accessoryView = tf;
    return c;
}
- (void)edited:(UITextField *)tf {
    NSString *v = [tf.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (tf.tag == 1) ADTRKeySet(tf.accessibilityIdentifier, v);
    else [NSUserDefaults.standardUserDefaults setObject:v forKey:tf.accessibilityIdentifier];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)flip:(UISwitch *)sw {
    [ADHaptic select];
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:(sw.tag == 1 ? @"ad_llm_on" : @"ad_tr_prefetch")];
    if (sw.tag == 1) [self.table reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 3 || ip.row != 1) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空文稿缓存?" message:@"已识别的文稿会全部删除,再看需要重新识别(会再次计费)。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[ADTranscriber shared] clearAll]; [ADHaptic success];
        [self.table reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
