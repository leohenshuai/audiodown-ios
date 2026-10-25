#import "AD.h"
#import <CommonCrypto/CommonDigest.h>

// ───────────── 磁盘缓存 ─────────────
static NSString *ADCacheDir(void) {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    d = [d stringByAppendingPathComponent:@"cache"];
    if (![NSFileManager.defaultManager fileExistsAtPath:d])
        [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString *ADCachePath(NSString *key) {
    NSData *in = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char out[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(in.bytes, (CC_LONG)in.length, out);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", out[i]];
    return [ADCacheDir() stringByAppendingPathComponent:hex];
}
static id ADCacheGet(NSString *key, NSTimeInterval *age) {
    if (!key.length) return nil;
    NSData *d = [NSData dataWithContentsOfFile:ADCachePath(key)];
    if (!d.length) return nil;
    NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:ADCachePath(key) error:nil];
    if (age) *age = -[attr[NSFileModificationDate] timeIntervalSinceNow];
    return [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingAllowFragments error:nil];
}
static void ADCacheSet(NSString *key, id json) {
    if (!key.length || !json) return;
    NSData *d = [NSJSONSerialization isValidJSONObject:json] ? [NSJSONSerialization dataWithJSONObject:json options:0 error:nil] : nil;
    if (d) [d writeToFile:ADCachePath(key) atomically:YES];
}

@interface ADApi ()
@property (nonatomic, strong) NSURLSession *session;
- (void)JSON:(NSString *)path method:(NSString *)method body:(id)body timeout:(NSTimeInterval)timeout done:(void (^)(id json, NSString *err))cb;
- (void)cachedGET:(NSString *)path key:(NSString *)key timeout:(NSTimeInterval)timeout done:(void (^)(id json, BOOL cached, NSString *err))cb;
@end

@implementation ADApi

+ (instancetype)shared {
    static ADApi *a; static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = [ADApi new];
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 12;
        c.timeoutIntervalForResource = 20;
        c.waitsForConnectivity = NO;
        a.session = [NSURLSession sessionWithConfiguration:c];
    });
    return a;
}

- (NSMutableURLRequest *)request:(NSString *)path method:(NSString *)method body:(id)body {
    NSString *full = [[ADConfig shared] url:path];
    // 已经是合法 URL（含 %XX 转义）就直接用，避免二次编码把中文变成 %25E7…
    NSURL *u = [NSURL URLWithString:full];
    if (!u || !u.host.length) {
        NSString *enc = [full stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        u = [NSURL URLWithString:enc];
    }
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
    r.HTTPMethod = method;
    [[ADConfig shared].headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) {
        [r setValue:v forHTTPHeaderField:k];
    }];
    if (body) {
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    return r;
}

- (void)JSON:(NSString *)path method:(NSString *)method body:(id)body done:(void (^)(id json, NSString *err))cb {
    [self JSON:path method:method body:body timeout:0 done:cb];
}

- (void)JSON:(NSString *)path method:(NSString *)method body:(id)body timeout:(NSTimeInterval)timeout done:(void (^)(id json, NSString *err))cb {
    NSMutableURLRequest *r = [self request:path method:method body:body];
    if (timeout > 0) r.timeoutInterval = timeout;
    NSLog(@"[AD] %@ %@", method, r.URL.absoluteString);
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil] : nil;
        NSString *message = nil;
        if (err) {
            message = (err.code == NSURLErrorTimedOut) ? @"请求超时，检查网络后重试" : err.localizedDescription;
        } else if (code >= 400) {
            if ([json isKindOfClass:NSDictionary.class] && [json[@"error"] isKindOfClass:NSString.class]) message = json[@"error"];
            else message = [NSString stringWithFormat:@"HTTP %ld", (long)code];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ cb(json, message); });
    }] resume];
}

// 带缓存的 GET：先给缓存，再给网络结果
- (void)cachedGET:(NSString *)path key:(NSString *)key done:(void (^)(id json, BOOL cached, NSString *err))cb {
    [self cachedGET:path key:key timeout:0 done:cb];
}

- (void)cachedGET:(NSString *)path key:(NSString *)key timeout:(NSTimeInterval)timeout done:(void (^)(id json, BOOL cached, NSString *err))cb {
    NSTimeInterval age = 0;
    id cached = ADCacheGet(key, &age);
    if (cached) cb(cached, YES, nil);
    [self JSON:path method:@"GET" body:nil timeout:timeout done:^(id json, NSString *err) {
        if (!err && json) { ADCacheSet(key, json); cb(json, NO, nil); return; }
        if (!cached) cb(nil, NO, err);
        else cb(cached, YES, err);   // 有缓存时把错误一并带回去，界面可提示离线
    }];
}

- (void)discover:(void (^)(NSArray<NSDictionary *> *, BOOL, NSString *))cb {
    [self cachedGET:@"/open-api/v1/discover" key:@"discover" done:^(id json, BOOL cached, NSString *err) {
        NSArray *secs = [json isKindOfClass:NSDictionary.class] ? json[@"sections"] : nil;
        cb([secs isKindOfClass:NSArray.class] ? secs : @[], cached, err);
    }];
}

- (void)search:(NSString *)q page:(NSInteger)page done:(void (^)(NSArray<ADAlbum *> *, BOOL, BOOL, NSString *))cb {
    NSCharacterSet *strict = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *enc = [q stringByAddingPercentEncodingWithAllowedCharacters:strict] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/search?q=%@&page=%ld&pageSize=30", enc, (long)page];
    NSString *key = [NSString stringWithFormat:@"search:%@:%ld", q, (long)page];
    [self cachedGET:path key:key done:^(id json, BOOL cached, NSString *err) {
        NSArray *items = nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            id d = json[@"data"];
            if ([d isKindOfClass:NSDictionary.class] && [d[@"items"] isKindOfClass:NSArray.class]) items = d[@"items"];
            else if ([json[@"items"] isKindOfClass:NSArray.class]) items = json[@"items"];
            NSMutableArray *out = [NSMutableArray array];
            for (id o in items) { ADAlbum *a = [ADAlbum fromJSON:o]; if (a) [out addObject:a]; }
            cb(out, out.count >= 15, cached, err);
            return;
        }
        cb(@[], NO, cached, err);
    }];
}

- (void)albumDetail:(NSString *)albumId done:(void (^)(ADAlbum *, BOOL, NSString *))cb {
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/albums/%@", albumId];
    [self cachedGET:path key:[@"album:" stringByAppendingString:albumId] done:^(id json, BOOL cached, NSString *err) {
        id d = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        ADAlbum *a = [ADAlbum fromJSON:[d isKindOfClass:NSDictionary.class] ? d : json];
        cb(a, cached, err);
    }];
}

// 把响应里可能是“曲目数组”的地方都试一遍（服务端不同源包装不一样）
static NSArray *ADPickArray(NSDictionary *json) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSArray *keys = @[@"items", @"tracks", @"list", @"songs", @"trackList", @"data"];
    NSMutableArray *dicts = [NSMutableArray array];
    [dicts addObject:json];
    for (NSString *k in @[@"data", @"result", @"payload"]) {
        id v = json[k];
        if ([v isKindOfClass:NSDictionary.class]) [dicts addObject:v];
    }
    for (NSDictionary *d in dicts) {
        for (NSString *k in keys) {
            id v = d[k];
            if ([v isKindOfClass:NSArray.class] && [v count]) return v;
        }
    }
    return nil;
}
static NSString *ADPickStr(NSDictionary *json, NSArray *keys) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSMutableArray *dicts = [NSMutableArray arrayWithObject:json];
    for (NSString *k in @[@"data", @"result", @"payload"]) {
        id v = json[k];
        if ([v isKindOfClass:NSDictionary.class]) [dicts addObject:v];
    }
    for (NSDictionary *d in dicts)
        for (NSString *k in keys) {
            id v = d[k];
            if ([v isKindOfClass:NSString.class] && [v length]) return v;
        }
    return nil;
}
static NSInteger ADPickInt(NSDictionary *json, NSArray *keys) {
    if (![json isKindOfClass:NSDictionary.class]) return 0;
    NSMutableArray *dicts = [NSMutableArray arrayWithObject:json];
    for (NSString *k in @[@"data", @"result", @"payload"]) {
        id v = json[k];
        if ([v isKindOfClass:NSDictionary.class]) [dicts addObject:v];
    }
    for (NSDictionary *d in dicts)
        for (NSString *k in keys) {
            id v = d[k];
            if ([v respondsToSelector:@selector(integerValue)] && [v integerValue] > 0) return [v integerValue];
        }
    return 0;
}

- (void)tracksOf:(NSString *)albumId page:(NSInteger)page done:(void (^)(NSArray<ADTrack *> *, NSInteger, BOOL, NSString *))cb {
    [self tracksOf:albumId page:page pageSize:50 done:cb];
}

- (void)tracksOf:(NSString *)albumId page:(NSInteger)page pageSize:(NSInteger)size done:(void (^)(NSArray<ADTrack *> *, NSInteger, BOOL, NSString *))cb {
    if (size < 1) size = 50;
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=%ld&pageSize=%ld", albumId, (long)page, (long)size];
    NSString *key = [NSString stringWithFormat:@"tracks:%@:%ld:%ld", albumId, (long)size, (long)page];
    // 目录接口服务端要现场找源，比别的接口慢，给它 30 秒（其它接口仍是 12 秒）
    [self cachedGET:path key:key timeout:30 done:^(id json, BOOL cached, NSString *err) {
        NSArray *items = ADPickArray(json);
        NSInteger total = ADPickInt(json, @[@"total", @"totalCount", @"count", @"trackCount"]);
        ADAlbum *stub = [ADAlbum new];
        stub.albumId = albumId;
        stub.provider = [json isKindOfClass:NSDictionary.class] && [json[@"provider"] isKindOfClass:NSString.class] ? json[@"provider"] : @"";
        NSMutableArray *out = [NSMutableArray array];
        for (id o in items) { ADTrack *t = [ADTrack fromJSON:o album:stub]; if (t) [out addObject:t]; }
        if (!err.length && !out.count && !cached && page == 1) {
            // 目录为空：把服务端的原样返回写进 Documents/debug_tracks_<专辑>.txt，并在错误文案里带上一小段
            NSData *raw = [NSJSONSerialization dataWithJSONObject:(json ?: @{}) options:0 error:nil];
            NSString *text = raw ? [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] : @"(不是 JSON)";
            NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *f = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"debug_tracks_%@.txt", albumId]];
            [[NSString stringWithFormat:@"GET %@\n\n%@", path, text] writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSLog(@"[AD] 目录为空 %@ -> %@", path, text);
            NSString *snip = text.length > 110 ? [[text substringToIndex:110] stringByAppendingString:@"…"] : text;
            NSString *lastError = ADPickStr(json, @[@"lastError", @"error", @"msg", @"message"]);
            err = lastError.length ? [NSString stringWithFormat:@"服务端没抓到目录：%@", lastError]
                                   : [NSString stringWithFormat:@"服务端返回空目录：%@", snip];
        }
        cb(out, total, cached, err);
    }];
}

- (void)playURLOf:(ADTrack *)t done:(void (^)(NSString *, NSDictionary *, NSString *))cb {
    NSDictionary *body = @{@"trackId": t.trackId ?: @"",
                           @"provider": t.provider ?: @"",
                           @"albumId": t.albumId ?: @""};
    [self JSON:@"/open-api/v1/cdn/play" method:@"POST" body:body done:^(id json, NSString *err) {
        if (err) { cb(nil, nil, err); return; }
        if (![json isKindOfClass:NSDictionary.class]) { cb(nil, nil, @"播放接口返回异常"); return; }
        NSString *url = json[@"url"] ?: json[@"directUrl"];
        if (![url isKindOfClass:NSString.class] || !url.length) { cb(nil, nil, json[@"msg"] ?: @"没有拿到音频地址"); return; }
        NSDictionary *headers = [json[@"headers"] isKindOfClass:NSDictionary.class] ? json[@"headers"] : @{};
        BOOL pending = [json[@"downloadPending"] boolValue];
        cb(url, headers, pending ? @"WAIT" : nil);
    }];
}

- (void)downloads:(void (^)(NSArray<NSDictionary *> *, NSString *))cb {
    [self JSON:@"/open-api/v1/downloads?page=1&pageSize=20" method:@"GET" body:nil done:^(id json, NSString *err) {
        if (err) { cb(@[], err); return; }
        NSArray *items = [json isKindOfClass:NSDictionary.class] ? json[@"items"] : nil;
        cb([items isKindOfClass:NSArray.class] ? items : @[], nil);
    }];
}
@end
