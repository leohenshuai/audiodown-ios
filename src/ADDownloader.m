#import "AD.h"
#import <AVFoundation/AVFoundation.h>


@implementation ADTask
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_albumId forKey:@"albumId"]; [c encodeObject:_title forKey:@"title"];
    [c encodeObject:_cover forKey:@"cover"]; [c encodeObject:_anchor forKey:@"anchor"];
    [c encodeObject:_provider forKey:@"provider"]; [c encodeObject:_tracks forKey:@"tracks"];
    [c encodeInteger:_done forKey:@"done"]; [c encodeInteger:_failed forKey:@"failed"];
    [c encodeInteger:_state forKey:@"state"]; [c encodeInteger:_cursor forKey:@"cursor"];
    [c encodeDouble:_bytes forKey:@"bytes"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _albumId = [c decodeObjectOfClass:NSString.class forKey:@"albumId"]; _title = [c decodeObjectOfClass:NSString.class forKey:@"title"];
        _cover = [c decodeObjectOfClass:NSString.class forKey:@"cover"]; _anchor = [c decodeObjectOfClass:NSString.class forKey:@"anchor"];
        _provider = [c decodeObjectOfClass:NSString.class forKey:@"provider"]; _tracks = [c decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, ADTrack.class, nil] forKey:@"tracks"] ?: @[];
        _done = [c decodeIntegerForKey:@"done"]; _failed = [c decodeIntegerForKey:@"failed"];
        _state = [c decodeIntegerForKey:@"state"]; _cursor = [c decodeIntegerForKey:@"cursor"];
        _bytes = [c decodeDoubleForKey:@"bytes"];
    }
    return self;
}
@end

@interface ADDownloader () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSMutableArray<ADTask *> *tasks;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *current;
@property (nonatomic, strong) ADTask *runningTask;
@property (nonatomic, assign) BOOL resolving;
// 每集最多重试 2 次，避免一次网络抖动就永久跳过这一集
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *retryMap;
@property (nonatomic, assign) NSInteger waitCount;
// 单集进度：正在下的那一集 + 已写入/总字节；失败过的集；gen 用来作废被取消的旧请求
@property (nonatomic, copy, readwrite, nullable) NSString *currentTrackId;
@property (nonatomic, assign, readwrite) double currentWritten, currentExpected;
@property (nonatomic, strong) NSMutableSet<NSString *> *failedIds;
@property (nonatomic, assign) NSInteger gen;
// 切后台时,一集下完到下一集开始之间要联网取地址;用后台任务把这几秒撑住
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@end

@implementation ADDownloader

+ (instancetype)shared {
    static ADDownloader *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [ADDownloader new];
        d.retryMap = [NSMutableDictionary dictionary];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [d fixExtensions]; });
        NSArray *fa = [NSUserDefaults.standardUserDefaults arrayForKey:@"ad_dl_failed"];
        d.failedIds = fa ? [NSMutableSet setWithArray:fa] : [NSMutableSet set];
        d.bgTask = UIBackgroundTaskInvalid;
        [d load];
        // 普通会话。试过后台会话:这个下载地址要带 Cookie/Referer,后台会话下请求头没送达,
        // 服务端回空内容(实测 22 次全是 0 字节)。切后台时靠 beginBackgroundTask 撑住。
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForResource = 24 * 3600;
        d.session = [NSURLSession sessionWithConfiguration:c delegate:d delegateQueue:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [d reconcile];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [d reconcile]; }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [d holdForBackground]; }];
        });
    });
    return d;
}

- (NSString *)audioDir {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    d = [d stringByAppendingPathComponent:@"audio"];
    if (![NSFileManager.defaultManager fileExistsAtPath:d])
        [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
- (NSString *)listPath {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [d stringByAppendingPathComponent:@"downloads.dat"];
}
- (void)load {
    NSSet *set = [NSSet setWithObjects:NSMutableArray.class, NSArray.class, ADTask.class, ADTrack.class, NSString.class, nil];
    NSData *d = [NSData dataWithContentsOfFile:[self listPath]];
    _tasks = [(d ? ADUnarchive(d, set) : nil) mutableCopy] ?: [NSMutableArray array];
    // 以前这里把"下载中"一律改成"暂停"。有了后台会话,应用被回收后下载可能还在继续,
    // 是否真的还在下要查过会话里的任务才知道:见 reconcile。
}

// 当前"下载中"的任务;进程被后台事件拉起时 runningTask 还是空的,在这里接上
- (ADTask *)activeTask {
    if (self.runningTask) return self.runningTask;
    for (ADTask *t in _tasks) if (t.state == ADTaskStateRunning) { self.runningTask = t; return t; }
    return nil;
}

// 启动/回前台时对一遍账:列表里"下载中"的任务,后台会话里是不是真有一个在下
- (void)reconcile {
    if (self.runningTask && self.current) return;            // 本进程里正常在下,不用动
    __weak typeof(self) w = self;
    [self.session getTasksWithCompletionHandler:^(NSArray *d, NSArray *u, NSArray<NSURLSessionDownloadTask *> *downloads) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(w) self = w; if (!self) return;
            if (self.runningTask && self.current) return;
            ADTask *run = nil;
            for (ADTask *t in self->_tasks) if (t.state == ADTaskStateRunning) { run = t; break; }
            NSURLSessionDownloadTask *live = nil;
            for (NSURLSessionDownloadTask *k in downloads) {
                if (k.state != NSURLSessionTaskStateRunning && k.state != NSURLSessionTaskStateSuspended) continue;
                if (!live && run) live = k; else [k cancel];      // 多出来的/没有主人的:取消
            }
            if (live && run) {
                // 接管:应用被回收之后,这一集还在后台下着
                self.runningTask = run; self.current = live; self.currentTrackId = live.taskDescription; self.resolving = NO;
                self.currentWritten = (double)live.countOfBytesReceived; self.currentExpected = (double)live.countOfBytesExpectedToReceive;
                ADLogTag(@"DL", @"接管后台下载 %@ 第%ld/%lu集", run.title ?: @"", (long)run.cursor + 1, (unsigned long)run.tracks.count);
                [self notify];
                return;
            }
            if (!run) return;
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return;   // 后台被拉起:完成事件可能还在路上,先别判死
            // 前台打开,会话里没有任务:多半是被强退过(强退会取消后台下载)。等 3 秒看有没有迟到的完成事件。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(w) self = w; if (!self || self.runningTask || self.current) return;
                for (ADTask *t in self->_tasks) if (t.state == ADTaskStateRunning) {
                    t.state = ADTaskStatePaused;
                    ADLogWarn(@"DL", @"上次下载没能在后台继续(可能被强退),已暂停:%@", t.title ?: @"");
                }
                [self save]; [self notify];
            });
        });
    }];
}

// 应用进入后台时,正在下的任务靠后台任务多活一会儿(通常几分钟到约 30 秒,系统说了算)
- (void)holdForBackground {
    if (self.runningTask) [self beginBG];
}

- (void)beginBG {
    @synchronized (self) {
        if (self.bgTask != UIBackgroundTaskInvalid) return;
        __weak typeof(self) w = self;
        self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"ad.dl.chain" expirationHandler:^{ [w endBG]; }];
    }
    // 不再设固定 28 秒保险:下载期间要一直撑着,系统到期会走 expirationHandler 自己收回
}
- (void)endBG {
    @synchronized (self) {
        if (self.bgTask == UIBackgroundTaskInvalid) return;
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}
- (void)save {
    [[NSKeyedArchiver archivedDataWithRootObject:_tasks requiringSecureCoding:NO error:nil] writeToFile:[self listPath] atomically:YES];
}
- (void)notify { [NSNotificationCenter.defaultCenter postNotificationName:@"ADDownloadChanged" object:nil]; }

- (NSArray<ADTask *> *)tasks { return _tasks; }

// 按文件头判断真实格式。服务端给的多是 MP3(ID3 开头)，以前一律存成 .m4a，
// AVPlayer 按扩展名当 MP4 解析 → 本地文件打不开。
+ (NSString *)extForData:(NSData *)head {
    const unsigned char *b = head.bytes; NSUInteger n = head.length;
    if (n >= 3 && b[0] == 'I' && b[1] == 'D' && b[2] == '3') return @"mp3";
    if (n >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return ((b[1] & 0x06) == 0) ? @"aac" : @"mp3";   // ADTS AAC 的 layer 位为 0
    if (n >= 8 && b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') return @"m4a";
    if (n >= 4 && b[0] == 'f' && b[1] == 'L' && b[2] == 'a' && b[3] == 'C') return @"flac";
    if (n >= 4 && b[0] == 'O' && b[1] == 'g' && b[2] == 'g' && b[3] == 'S') return @"ogg";
    if (n >= 4 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F') return @"wav";
    return nil;
}
+ (NSString *)extForFile:(NSString *)path {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *d = [h readDataOfLength:16]; [h closeFile];
    return [self extForData:d];
}
- (NSArray<NSString *> *)exts { return @[@"mp3", @"m4a", @"aac", @"flac", @"ogg", @"wav"]; }
- (NSString *)pathFor:(NSString *)trackId ext:(NSString *)ext {
    return [[self audioDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", trackId, ext]];
}
// 已存在的文件(任意扩展名)；没有时返回 .mp3 路径
- (NSString *)fileFor:(NSString *)trackId {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *e in [self exts]) { NSString *p = [self pathFor:trackId ext:e]; if ([fm fileExistsAtPath:p]) return p; }
    return [self pathFor:trackId ext:@"mp3"];
}
- (BOOL)hasLocal:(NSString *)trackId {
    return trackId.length && [NSFileManager.defaultManager fileExistsAtPath:[self fileFor:trackId]];
}
// 启动时把旧版本按 .m4a 存下的 MP3 改回正确扩展名
- (void)fixExtensions {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [self audioDir];
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        NSString *src = [dir stringByAppendingPathComponent:f];
        NSString *real = [ADDownloader extForFile:src];
        if (!real.length || [f.pathExtension.lowercaseString isEqualToString:real]) continue;
        NSString *dst = [[src stringByDeletingPathExtension] stringByAppendingPathExtension:real];
        [fm removeItemAtPath:dst error:nil];
        [fm moveItemAtPath:src toPath:dst error:nil];
    }
}
- (void)removeLocal:(NSString *)trackId {
    if (!trackId.length) return;
    NSString *p = [self fileFor:trackId];
    if ([NSFileManager.defaultManager fileExistsAtPath:p]) [NSFileManager.defaultManager removeItemAtPath:p error:nil];
    [self notify];
}

- (NSURL *)localURL:(NSString *)trackId {
    return [self hasLocal:trackId] ? [NSURL fileURLWithPath:[self fileFor:trackId]] : nil;
}

- (void)markFailed:(NSString *)tid { if (tid.length) { [self.failedIds addObject:tid]; [self saveFailed]; } }
- (void)saveFailed { [NSUserDefaults.standardUserDefaults setObject:self.failedIds.allObjects forKey:@"ad_dl_failed"]; }
- (BOOL)isFailed:(NSString *)tid { return tid.length && [self.failedIds containsObject:tid]; }
- (double)fileSize:(NSString *)tid {
    if (!tid.length) return 0;
    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:[self fileFor:tid] error:nil];
    return a ? (double)a.fileSize : 0;
}
- (double)bytesForTask:(ADTask *)t { double sum = 0; for (ADTrack *x in t.tracks) sum += [self fileSize:x.trackId]; return sum; }
- (NSInteger)localCountOf:(ADTask *)t { NSInteger n = 0; for (ADTrack *x in t.tracks) if ([self hasLocal:x.trackId]) n++; return n; }
- (NSInteger)failedCountOf:(ADTask *)t { NSInteger n = 0; for (ADTrack *x in t.tracks) if (![self hasLocal:x.trackId] && [self isFailed:x.trackId]) n++; return n; }

// 停掉这个任务正在进行的请求（不改状态）
- (BOOL)haltIfRunning:(ADTask *)t {
    if (t != self.runningTask) return NO;
    self.gen += 1;
    [self.current cancel]; self.current = nil;
    self.runningTask = nil; self.resolving = NO; self.currentTrackId = nil;
    return YES;
}
- (void)recount:(ADTask *)t {
    t.done = [self localCountOf:t];
    t.failed = [self failedCountOf:t];
    t.cursor = 0;                    // 从头扫，已存在的会被跳过
}

- (void)removeTracks:(NSArray<NSString *> *)ids fromTask:(ADTask *)t {
    if (!t || !ids.count) return;
    BOOL active = (t.state == ADTaskStateRunning || t.state == ADTaskStateQueued);
    [self haltIfRunning:t];
    NSSet *kill = [NSSet setWithArray:ids];
    NSMutableArray *keep = [NSMutableArray array];
    for (ADTrack *x in t.tracks) {
        if ([kill containsObject:x.trackId]) {
            [NSFileManager.defaultManager removeItemAtPath:[self fileFor:x.trackId] error:nil];
            [self.failedIds removeObject:x.trackId];
            [self.retryMap removeObjectForKey:x.trackId];
        } else [keep addObject:x];
    }
    [self saveFailed];
    if (!keep.count) { [_tasks removeObject:t]; [self save]; [self notify]; [self pump]; return; }
    t.tracks = keep;
    [self recount:t];
    if (t.done >= (NSInteger)keep.count) t.state = ADTaskStateDone;
    else if (active) t.state = ADTaskStateQueued;
    else if (t.state == ADTaskStateDone) t.state = t.failed ? ADTaskStateFailed : ADTaskStatePaused;
    [self save]; [self notify]; [self pump];
}

- (void)redownload:(NSArray<NSString *> *)ids inTask:(ADTask *)t {
    if (!t || !ids.count) return;
    [self haltIfRunning:t];
    for (NSString *tid in ids) {
        [NSFileManager.defaultManager removeItemAtPath:[self fileFor:tid] error:nil];
        [self.failedIds removeObject:tid];
        [self.retryMap removeObjectForKey:tid];
    }
    [self saveFailed];
    [self recount:t];
    t.state = ADTaskStateQueued;
    [self save]; [self notify]; [self pump];
}

- (void)retryFailed:(ADTask *)t {
    if (!t) return;
    for (ADTrack *x in t.tracks) if (![self hasLocal:x.trackId]) { [self.failedIds removeObject:x.trackId]; [self.retryMap removeObjectForKey:x.trackId]; }
    [self saveFailed];
    BOOL running = (t == self.runningTask);
    if (!running) [self recount:t]; else t.failed = 0;
    if (t.done < (NSInteger)t.tracks.count && !running) t.state = ADTaskStateQueued;
    [self save]; [self notify]; [self pump];
}

- (ADTask *)taskForAlbum:(NSString *)albumId {
    for (ADTask *t in _tasks) if ([t.albumId isEqualToString:albumId]) return t;
    return nil;
}

- (void)addAlbum:(ADAlbum *)a tracks:(NSArray<ADTrack *> *)tracks {
    if (!tracks.count) return;
    ADTask *t = [self taskForAlbum:a.albumId];
    if (!t) {
        t = [ADTask new];
        t.albumId = a.albumId; t.title = a.title; t.cover = a.cover;
        t.anchor = a.anchor; t.provider = a.provider;
        [_tasks insertObject:t atIndex:0];
    }
    t.tracks = tracks;
    t.done = 0; t.failed = 0; t.cursor = 0;
    t.state = ADTaskStateQueued;
    [self save];
    [self notify];
    [self pump];
}

- (void)addTracks:(ADAlbum *)a tracks:(NSArray<ADTrack *> *)list {
    if (!list.count) return;
    ADTask *t = [self taskForAlbum:a.albumId];
    if (!t) {
        [self addAlbum:a tracks:list];
        return;
    }
    NSMutableArray *merged = [t.tracks mutableCopy] ?: [NSMutableArray array];
    NSMutableSet *have = [NSMutableSet set];
    for (ADTrack *x in merged) [have addObject:x.trackId];
    BOOL added = NO;
    for (ADTrack *x in list) if (![have containsObject:x.trackId]) { [merged addObject:x]; [have addObject:x.trackId]; added = YES; }
    if (!added) { [self notify]; return; }
    t.tracks = merged;
    if (t.state == ADTaskStateDone || t.state == ADTaskStateFailed) t.state = ADTaskStateQueued;
    [self save];
    [self notify];
    [self pump];
}

- (void)pauseTask:(ADTask *)t {
    if (!t) return;
    if (t == self.runningTask) {
        self.gen += 1;
        [self.current cancel];
        self.current = nil;
        self.runningTask = nil;
        self.resolving = NO;
        self.currentTrackId = nil;
    }
    if (t.state != ADTaskStateDone) t.state = ADTaskStatePaused;
    [self save]; [self notify];
}
- (void)resumeTask:(ADTask *)t {
    if (!t || t.state == ADTaskStateDone) return;
    t.state = ADTaskStateQueued;
    [self save]; [self notify];
    [self pump];
}
- (void)deleteTask:(ADTask *)t {
    [self pauseTask:t];
    for (ADTrack *x in t.tracks) [self.failedIds removeObject:x.trackId];
    [self saveFailed];
    for (ADTrack *tr in t.tracks) {
        NSString *p = [self fileFor:tr.trackId];
        if ([NSFileManager.defaultManager fileExistsAtPath:p]) [NSFileManager.defaultManager removeItemAtPath:p error:nil];
    }
    [_tasks removeObject:t];
    [self save]; [self notify];
    [self pump];
}
- (void)pauseAll {
    for (ADTask *t in _tasks) if (t.state == ADTaskStateRunning || t.state == ADTaskStateQueued) t.state = ADTaskStatePaused;
    self.gen += 1;
    [self.current cancel]; self.current = nil; self.runningTask = nil; self.resolving = NO; self.currentTrackId = nil;
    [self save]; [self notify];
}
- (void)resumeAll {
    for (ADTask *t in _tasks) if (t.state == ADTaskStatePaused || t.state == ADTaskStateFailed) t.state = ADTaskStateQueued;
    [self save]; [self notify]; [self pump];
}

- (void)pump {
    if (self.runningTask) return;
    ADTask *next = nil;
    for (ADTask *t in _tasks) if (t.state == ADTaskStateQueued) { next = t; break; }
    if (!next) return;
    self.runningTask = next;
    next.state = ADTaskStateRunning;
    [self stepTask:next];
}

- (void)stepTask:(ADTask *)t {
    if (t.state == ADTaskStateRunning && !self.runningTask) self.runningTask = t;   // 被后台事件拉起时接上
    if (t.state != ADTaskStateRunning) { self.runningTask = nil; [self endBG]; [self pump]; return; }
    if (t.cursor >= (NSInteger)t.tracks.count) {
        [self endBG];
        self.currentTrackId = nil;
        t.state = t.failed ? ADTaskStateFailed : ADTaskStateDone;
        self.runningTask = nil;
        [self save]; [self notify];
        [self pump];
        return;
    }
    ADTrack *tr = t.tracks[t.cursor];
    if ([self hasLocal:tr.trackId]) {
        t.done += 1; t.cursor += 1;
        [self save]; [self notify];
        dispatch_async(dispatch_get_main_queue(), ^{ [self stepTask:t]; });
        return;
    }
    if (self.resolving) return;
    self.resolving = YES;
    self.currentTrackId = tr.trackId;
    self.currentWritten = 0; self.currentExpected = 0;
    NSInteger myGen = self.gen;
    __weak typeof(self) w = self;
    [[ADApi shared] playURLOf:tr done:^(NSString *url, NSDictionary *headers, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (myGen != self.gen) return;                         // 期间被暂停/删除/重下过：作废
        self.resolving = NO;
        if (t.state != ADTaskStateRunning || self.runningTask != t) return;
        if (!url) {
            // 同一集最多重试 2 次，仍然失败才跳过
            NSInteger tries = tr.trackId.length ? [self.retryMap[tr.trackId] integerValue] : 99;
            if (tries < 2) {
                if (tr.trackId.length) self.retryMap[tr.trackId] = @(tries + 1);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * (tries + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self stepTask:t]; });
                return;
            }
            [self.retryMap removeObjectForKey:tr.trackId];
            [self markFailed:tr.trackId];
            t.failed += 1; t.cursor += 1;
            self.waitCount = 0;
            [self save]; [self notify];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self stepTask:t]; });
            return;
        }
        if ([err isEqualToString:@"WAIT"]) {
            self.waitCount += 1;
            if (self.waitCount > 60) {   // 大约 2 分钟还没转码好，先跳过，别把整本书卡死
                self.waitCount = 0;
                [self markFailed:tr.trackId];
                t.failed += 1; t.cursor += 1;
                [self save]; [self notify];
                [self stepTask:t];
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self stepTask:t]; });
            return;
        }
        self.waitCount = 0;
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        [headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) {
            if ([v isKindOfClass:NSString.class] && [v length]) [r setValue:v forHTTPHeaderField:k];
        }];
        self.current = [self.session downloadTaskWithRequest:r];
        self.current.taskDescription = tr.trackId;
        [self.current resume];
        ADLogTag(@"DL", @"开始下载 第%ld/%lu集 %@ · 请求头 %lu 个", (long)t.cursor + 1, (unsigned long)t.tracks.count, tr.title ?: tr.trackId, (unsigned long)r.allHTTPHeaderFields.count);
        [self notify];
    }];
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    [self beginBG];                                          // 马上要联网取下一集的地址,别在这之前被挂起
    NSString *tid = task.taskDescription;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *e in [self exts]) [fm removeItemAtPath:[self pathFor:tid ext:e] error:nil];
    NSString *ext = [ADDownloader extForFile:location.path];
    if (!ext.length) {
        NSString *ue = task.originalRequest.URL.pathExtension.lowercaseString;
        ext = [[self exts] containsObject:ue] ? ue : @"mp3";
    }
    NSString *dst = [self pathFor:tid ext:ext];
    [fm copyItemAtPath:location.path toPath:dst error:nil];
    NSDictionary *attr = [fm attributesOfItemAtPath:dst error:nil];
    NSHTTPURLResponse *hr = [task.response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)task.response : nil;
    if ([attr fileSize] < 8000) ADLogError(@"DL", @"✗ 下载落盘过小 trackId=%@ %lluB · HTTP %ld · 类型 %@ · 声明长度 %lld(多半是服务端返回了错误页)", tid, [attr fileSize], (long)hr.statusCode, hr.MIMEType ?: @"?", task.countOfBytesExpectedToReceive);
    else ADLogTag(@"DL", @"下载完成 trackId=%@ %.1fMB .%@", tid, [attr fileSize] / 1048576.0, ext);
    // 文件没写成 / 太小（多半是服务端返回的错误页）就别当成功，交回重试
    if (!attr || [attr fileSize] < 8000) {
        [fm removeItemAtPath:dst error:nil];
        __weak typeof(self) w0 = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(w0) self = w0; if (!self) return;
            ADTask *t0 = [self activeTask];
            if (!t0 || t0.state != ADTaskStateRunning) { [self endBG]; return; }
            NSInteger tries = tid.length ? [self.retryMap[tid] integerValue] : 99;
            if (tries < 2) {
                if (tid.length) self.retryMap[tid] = @(tries + 1);
                self.current = nil;
                [self save]; [self notify];
                [self stepTask:t0];
            } else {
                if (tid.length) [self.retryMap removeObjectForKey:tid];
                [self markFailed:tid];
                t0.failed += 1; t0.cursor += 1;
                self.current = nil;
                [self save]; [self notify];
                [self stepTask:t0];
            }
        });
        return;
    }
    if (tid.length) [self.retryMap removeObjectForKey:tid];
    self.waitCount = 0;
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        ADTask *t = [self activeTask];                       // 被后台事件拉起时 runningTask 还是空的
        if (t) {
            ADTrack *cur = (t.cursor < (NSInteger)t.tracks.count) ? t.tracks[t.cursor] : nil;
            if (cur && [cur.trackId isEqualToString:tid]) { t.done += 1; t.cursor += 1; }
            else ADLogWarn(@"DL", @"完成的这集(%@)不是当前游标那集,只落盘不计数", tid);
        } else [self endBG];
        if (tid.length && [self.failedIds containsObject:tid]) { [self.failedIds removeObject:tid]; [self saveFailed]; }
        self.currentTrackId = nil; self.currentWritten = 0; self.currentExpected = 0;
        self.current = nil;
        [self save]; [self notify];
        if (t) [self stepTask:t];
    });
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error || error.code == NSURLErrorCancelled) return;   // 暂停/删除时主动取消，不算失败
    ADLogError(@"DL", @"✗ 下载出错 trackId=%@ %@ (code %ld)", task.taskDescription, error.localizedDescription, (long)error.code);
    [self beginBG];
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        ADTask *t = [self activeTask];
        if (!t || t.state != ADTaskStateRunning) [self endBG];
        if (t && t.state == ADTaskStateRunning) {
            NSString *tid = task.taskDescription;
            NSInteger tries = tid.length ? [self.retryMap[tid] integerValue] : 99;
            self.current = nil;
            if (tries < 2) {
                // 同一集重下（cursor 不动）
                if (tid.length) self.retryMap[tid] = @(tries + 1);
                [self notify];
                [self stepTask:t];
                return;
            }
            if (tid.length) [self.retryMap removeObjectForKey:tid];
            [self markFailed:tid];
            t.failed += 1; t.cursor += 1;
            [self save]; [self notify];
            [self stepTask:t];
        }
    });
}

// 系统因后台下载事件唤醒我们、且这批事件都已交付完:通知系统可以重新挂起(下一集的联网由 bgTask 撑着)
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^h)(void) = self.bgCompletion;
        self.bgCompletion = nil;
        ADLogTag(@"DL", @"后台下载事件处理完毕");
        if (h) h();
    });
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    self.runningTask.bytes = (double)total;
    if ([task.taskDescription isEqualToString:self.currentTrackId]) { self.currentWritten = (double)total; self.currentExpected = (double)expected; }
    static NSDate *last; static dispatch_once_t once;
    dispatch_once(&once, ^{ last = [NSDate date]; });
    if ([[NSDate date] timeIntervalSinceDate:last] > 0.4) {
        last = [NSDate date];
        dispatch_async(dispatch_get_main_queue(), ^{ [self notify]; });
    }
}
@end
