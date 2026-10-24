#import "AD.h"

@interface ADApi ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation ADApi

+ (instancetype)shared {
    static ADApi *a; static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = [ADApi new];
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 20;
        c.timeoutIntervalForResource = 40;
        a.session = [NSURLSession sessionWithConfiguration:c];
    });
    return a;
}

- (NSMutableURLRequest *)request:(NSString *)path method:(NSString *)method body:(id)body {
    NSString *full = [[ADConfig shared] url:path];
    NSURL *u = [NSURL URLWithString:[full stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
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
    NSMutableURLRequest *r = [self request:path method:method body:body];
    NSLog(@"[AD] %@ %@", method, r.URL.absoluteString);
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil] : nil;
        NSString *message = nil;
        if (err) message = err.localizedDescription;
        else if (code >= 400) {
            if ([json isKindOfClass:NSDictionary.class] && [json[@"error"] isKindOfClass:NSString.class]) message = json[@"error"];
            else message = [NSString stringWithFormat:@"HTTP %ld", (long)code];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ cb(json, message); });
    }] resume];
}

// 发现页：sections[{title, items:[album…]}]
- (void)discover:(void (^)(NSArray<NSDictionary *> *, NSString *))cb {
    [self JSON:@"/open-api/v1/discover" method:@"GET" body:nil done:^(id json, NSString *err) {
        if (err) { cb(@[], err); return; }
        NSArray *secs = [json isKindOfClass:NSDictionary.class] ? json[@"sections"] : nil;
        cb([secs isKindOfClass:NSArray.class] ? secs : @[], nil);
    }];
}

- (void)search:(NSString *)q page:(NSInteger)page done:(void (^)(NSArray<ADAlbum *> *, BOOL, NSString *))cb {
    NSString *enc = [q stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/search?q=%@&page=%ld&pageSize=30", enc, (long)page];
    [self JSON:path method:@"GET" body:nil done:^(id json, NSString *err) {
        if (err) { cb(@[], NO, err); return; }
        NSArray *items = nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            id d = json[@"data"];
            if ([d isKindOfClass:NSDictionary.class] && [d[@"items"] isKindOfClass:NSArray.class]) items = d[@"items"];
            else if ([json[@"items"] isKindOfClass:NSArray.class]) items = json[@"items"];
        }
        NSMutableArray *out = [NSMutableArray array];
        for (id o in items) { ADAlbum *a = [ADAlbum fromJSON:o]; if (a) [out addObject:a]; }
        BOOL more = out.count >= 15;
        cb(out, more, nil);
    }];
}

- (void)albumDetail:(NSString *)albumId done:(void (^)(ADAlbum *, NSString *))cb {
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/albums/%@", albumId];
    [self JSON:path method:@"GET" body:nil done:^(id json, NSString *err) {
        if (err) { cb(nil, err); return; }
        id d = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        ADAlbum *a = [ADAlbum fromJSON:[d isKindOfClass:NSDictionary.class] ? d : json];
        cb(a, a ? nil : @"返回里没有专辑信息");
    }];
}

- (void)tracksOf:(NSString *)albumId page:(NSInteger)page done:(void (^)(NSArray<ADTrack *> *, NSInteger, NSString *))cb {
    NSString *path = [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=%ld&pageSize=50", albumId, (long)page];
    [self JSON:path method:@"GET" body:nil done:^(id json, NSString *err) {
        if (err) { cb(@[], 0, err); return; }
        NSArray *items = [json isKindOfClass:NSDictionary.class] ? json[@"items"] : nil;
        NSInteger total = [json[@"total"] respondsToSelector:@selector(integerValue)] ? [json[@"total"] integerValue] : 0;
        ADAlbum *stub = [ADAlbum new];
        stub.albumId = albumId; stub.provider = [json[@"provider"] isKindOfClass:NSString.class] ? json[@"provider"] : @"";
        NSMutableArray *out = [NSMutableArray array];
        for (id o in items) { ADTrack *t = [ADTrack fromJSON:o album:stub]; if (t) [out addObject:t]; }
        cb(out, total, nil);
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
