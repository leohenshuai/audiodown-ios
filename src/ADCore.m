#import "AD.h"

static NSString *ADPref(NSString *k, NSString *d) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:k];
    return v.length ? v : d;
}

@implementation ADConfig
+ (instancetype)shared {
    static ADConfig *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [ADConfig new]; [c load]; });
    return c;
}
- (void)load {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    _baseURL = ADPref(@"baseURL", @"https://audio.959935291.xyz:899");
    _token = ADPref(@"token", @"");
    _authHeader = ADPref(@"authHeader", @"Authorization");
    _authScheme = ADPref(@"authScheme", @"Bearer");
    _pathMe = ADPref(@"pathMe", @"/api/me");
    _pathList = ADPref(@"pathList", @"/api/books");
    _pathSearch = ADPref(@"pathSearch", @"/api/search?q={q}");
    _pathBook = ADPref(@"pathBook", @"/api/books/{id}");
    _pathStream = ADPref(@"pathStream", @"/api/books/{id}/stream");
    _pathProgress = ADPref(@"pathProgress", @"/api/progress");
    _listPath = ADPref(@"listPath", @"");
}
- (void)save {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    [u setObject:_baseURL forKey:@"baseURL"]; [u setObject:_token forKey:@"token"];
    [u setObject:_authHeader forKey:@"authHeader"]; [u setObject:_authScheme forKey:@"authScheme"];
    [u setObject:_pathMe forKey:@"pathMe"]; [u setObject:_pathList forKey:@"pathList"];
    [u setObject:_pathSearch forKey:@"pathSearch"]; [u setObject:_pathBook forKey:@"pathBook"];
    [u setObject:_pathStream forKey:@"pathStream"]; [u setObject:_pathProgress forKey:@"pathProgress"];
    [u setObject:_listPath forKey:@"listPath"];
    [u synchronize];
}
- (NSDictionary *)headers {
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    h[@"Accept"] = @"application/json";
    if (_token.length) {
        if (_authScheme.length) {
            h[_authHeader] = [NSString stringWithFormat:@"%@ %@", _authScheme, _token];
        } else {
            h[_authHeader] = _token;
        }
        // 兼容网页会话：同时带上 cookie
        h[@"Cookie"] = [NSString stringWithFormat:@"token=%@; session=%@", _token, _token];
    }
    return h;
}
- (NSString *)urlFor:(NSString *)tmpl args:(NSDictionary<NSString *, NSString *> *)args {
    NSString *t = tmpl;
    for (NSString *k in args) {
        t = [t stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"{%@}", k] withString:args[k]];
    }
    if ([t hasPrefix:@"http"]) return t;
    NSString *base = _baseURL;
    while (base.length && [base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    if (![t hasPrefix:@"/"]) t = [@"/" stringByAppendingString:t];
    return [base stringByAppendingString:t];
}
@end

// ─────────────────────────── 模型 ───────────────────────────
@implementation ADChapter
+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:[NSDictionary class]]) return nil;
    ADChapter *c = [ADChapter new];
    c.fid = [ADAPI stringAt:@"fid" in:j] ?: [ADAPI stringAt:@"id" in:j] ?: [ADAPI stringAt:@"cid" in:j] ?: @"";
    c.title = [ADAPI stringAt:@"title" in:j] ?: [ADAPI stringAt:@"name" in:j] ?: c.fid;
    c.streamURL = [ADAPI stringAt:@"url" in:j] ?: [ADAPI stringAt:@"stream_url" in:j] ?: [ADAPI stringAt:@"audio" in:j] ?: @"";
    c.duration = [ADAPI doubleAt:@"duration" in:j];
    return c;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_fid forKey:@"fid"]; [c encodeObject:_title forKey:@"title"];
    [c encodeObject:_streamURL forKey:@"streamURL"]; [c encodeDouble:_duration forKey:@"duration"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _fid = [c decodeObjectForKey:@"fid"]; _title = [c decodeObjectForKey:@"title"];
        _streamURL = [c decodeObjectForKey:@"streamURL"]; _duration = [c decodeDoubleForKey:@"duration"];
    }
    return self;
}
@end

@implementation ADBook
+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:[NSDictionary class]]) return nil;
    ADBook *b = [ADBook new];
    b.bid = [ADAPI stringAt:@"id" in:j] ?: [ADAPI stringAt:@"bid" in:j] ?: [ADAPI stringAt:@"book_id" in:j] ?: @"";
    b.title = [ADAPI stringAt:@"title" in:j] ?: [ADAPI stringAt:@"name" in:j] ?: @"未命名";
    b.author = [ADAPI stringAt:@"author" in:j] ?: [ADAPI stringAt:@"authors" in:j] ?: @"";
    b.narrator = [ADAPI stringAt:@"narrator" in:j] ?: [ADAPI stringAt:@"reader" in:j] ?: @"";
    b.cover = [ADAPI stringAt:@"cover" in:j] ?: [ADAPI stringAt:@"cover_url" in:j] ?: [ADAPI stringAt:@"image" in:j] ?: @"";
    b.summary = [ADAPI stringAt:@"summary" in:j] ?: [ADAPI stringAt:@"intro" in:j] ?: [ADAPI stringAt:@"description" in:j] ?: @"";
    id chs = [ADAPI valueAt:@"chapters" in:j] ?: [ADAPI valueAt:@"tracks" in:j] ?: [ADAPI valueAt:@"items" in:j];
    NSMutableArray *arr = [NSMutableArray array];
    if ([chs isKindOfClass:[NSArray class]]) {
        for (id o in (NSArray *)chs) { ADChapter *c = [ADChapter fromJSON:o]; if (c) [arr addObject:c]; }
    }
    b.chapters = arr;
    return b;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_bid forKey:@"bid"]; [c encodeObject:_title forKey:@"title"];
    [c encodeObject:_author forKey:@"author"]; [c encodeObject:_narrator forKey:@"narrator"];
    [c encodeObject:_cover forKey:@"cover"]; [c encodeObject:_summary forKey:@"summary"];
    [c encodeObject:_chapters forKey:@"chapters"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _bid = [c decodeObjectForKey:@"bid"]; _title = [c decodeObjectForKey:@"title"];
        _author = [c decodeObjectForKey:@"author"]; _narrator = [c decodeObjectForKey:@"narrator"];
        _cover = [c decodeObjectForKey:@"cover"]; _summary = [c decodeObjectForKey:@"summary"];
        _chapters = [c decodeObjectForKey:@"chapters"] ?: @[];
    }
    return self;
}
@end

// ─────────────────────────── 本地存储 ───────────────────────────
@implementation ADStore {
    NSMutableArray<ADBook *> *_shelf;
    NSMutableDictionary<NSString *, NSNumber *> *_progress;
    NSMutableDictionary<NSString *, NSString *> *_last;
}
+ (instancetype)shared {
    static ADStore *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ADStore new]; [s load]; });
    return s;
}
- (NSString *)path:(NSString *)n {
    NSString *d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [d stringByAppendingPathComponent:n];
}
- (void)load {
    _shelf = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class],[ADBook class],[ADChapter class],[NSArray class],[NSString class],nil] fromData:[NSData dataWithContentsOfFile:[self path:@"shelf.dat"]] error:nil] ?: [NSMutableArray array];
    _progress = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSMutableDictionary class],[NSString class],[NSNumber class],nil] fromData:[NSData dataWithContentsOfFile:[self path:@"progress.dat"]] error:nil] ?: [NSMutableDictionary dictionary];
    _last = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSMutableDictionary class],[NSString class],nil] fromData:[NSData dataWithContentsOfFile:[self path:@"last.dat"]] error:nil] ?: [NSMutableDictionary dictionary];
}
- (NSMutableArray<ADBook *> *)shelf { return _shelf; }
- (void)save {
    [[NSKeyedArchiver archivedDataWithRootObject:_shelf requiringSecureCoding:NO error:nil] writeToFile:[self path:@"shelf.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_progress requiringSecureCoding:NO error:nil] writeToFile:[self path:@"progress.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_last requiringSecureCoding:NO error:nil] writeToFile:[self path:@"last.dat"] atomically:YES];
}
- (void)addBook:(ADBook *)b {
    if (!b.bid.length) return;
    for (ADBook *x in _shelf) if ([x.bid isEqualToString:b.bid]) return;
    [_shelf insertObject:b atIndex:0]; [self save];
}
- (void)removeBook:(ADBook *)b { [_shelf removeObject:b]; [self save]; }
- (double)progressForChapter:(NSString *)cid { return [_progress[cid] doubleValue]; }
- (void)setProgress:(double)p forChapter:(NSString *)cid { if (cid.length) _progress[cid] = @(p); [self save]; }
- (NSString *)lastChapterOfBook:(NSString *)bid { return _last[bid]; }
- (void)setLastChapter:(NSString *)cid book:(NSString *)bid { if (bid.length) _last[bid] = cid; [self save]; }
@end

// ─────────────────────────── 网络 ───────────────────────────
@implementation ADAPI
+ (instancetype)shared {
    static ADAPI *a; static dispatch_once_t once;
    dispatch_once(&once, ^{ a = [ADAPI new]; });
    return a;
}

+ (id)valueAt:(NSString *)path in:(id)obj {
    if (!path.length) return obj;
    id cur = obj;
    for (NSString *part in [path componentsSeparatedByString:@"."]) {
        NSString *key = part; NSInteger idx = -1;
        NSRange br = [part rangeOfString:@"["];
        if (br.location != NSNotFound) {
            key = [part substringToIndex:br.location];
            NSString *num = [[part substringFromIndex:br.location] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[]"]];
            idx = num.integerValue;
        }
        if (key.length) {
            if ([cur isKindOfClass:[NSDictionary class]]) cur = cur[key];
            else return nil;
        }
        if (idx >= 0) {
            if ([cur isKindOfClass:[NSArray class]] && idx < (NSInteger)[cur count]) cur = cur[idx];
            else return nil;
        }
        if (!cur) return nil;
    }
    return cur;
}
+ (NSString *)stringAt:(NSString *)path in:(id)obj {
    id v = [self valueAt:path in:obj];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}
+ (double)doubleAt:(NSString *)path in:(id)obj {
    id v = [self valueAt:path in:obj];
    if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    return 0;
}

- (NSURLSession *)session {
    static NSURLSession *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 20;
        s = [NSURLSession sessionWithConfiguration:c delegate:nil delegateQueue:nil];
    });
    return s;
}

- (NSURL *)urlChecked:(NSString *)url {
    return [NSURL URLWithString:[url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
}

- (void)request:(NSString *)pathOrURL method:(NSString *)method body:(id)body completion:(ADJSONBlock)cb {
    ADConfig *cfg = [ADConfig shared];
    NSString *full = [pathOrURL hasPrefix:@"http"] ? pathOrURL : [cfg urlFor:pathOrURL args:@{}];
    NSURL *u = [self urlChecked:full];
    if (!u) { if (cb) cb(nil, [NSError errorWithDomain:@"ad" code:1 userInfo:@{NSLocalizedDescriptionKey: @"URL 无效"}], 0); return; }
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
    r.HTTPMethod = method ?: @"GET";
    [cfg.headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) { [r setValue:v forHTTPHeaderField:k]; }];
    if (body) {
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        id json = nil;
        if (data.length) json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (cb) cb(json ?: (data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil), err, code);
        });
    }] resume];
}

- (void)me:(ADJSONBlock)cb { [self request:[ADConfig shared].pathMe method:@"GET" body:nil completion:cb]; }

- (void)fetchList:(NSString *)query completion:(ADJSONBlock)cb {
    ADConfig *cfg = [ADConfig shared];
    NSString *p = query.length ? cfg.pathSearch : cfg.pathList;
    p = [p stringByReplacingOccurrencesOfString:@"{q}" withString:[query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @""];
    [self request:p method:@"GET" body:nil completion:cb];
}

- (void)fetchBook:(NSString *)bid completion:(ADJSONBlock)cb {
    NSString *p = [[ADConfig shared].pathBook stringByReplacingOccurrencesOfString:@"{id}" withString:bid];
    [self request:p method:@"GET" body:nil completion:cb];
}

- (void)reportProgress:(NSString *)bid chapter:(NSString *)cid seconds:(double)s chapterProgress:(double)p {
    ADConfig *cfg = [ADConfig shared];
    if (!cfg.pathProgress.length) return;
    NSDictionary *body = @{@"book_id": bid ?: @"", @"chapter_id": cid ?: @"", @"position": @(s), @"progress": @(p)};
    [self request:cfg.pathProgress method:@"POST" body:body completion:^(id j, NSError *e, NSInteger c) {}];
}

- (NSURL *)streamURLFor:(ADChapter *)ch {
    if (ch.streamURL.length) {
        if ([ch.streamURL hasPrefix:@"http"]) return [NSURL URLWithString:ch.streamURL];
        return [NSURL URLWithString:[[ADConfig shared] urlFor:ch.streamURL args:@{}]];
    }
    if (!ch.fid.length) return nil;
    NSString *p = [[ADConfig shared].pathStream stringByReplacingOccurrencesOfString:@"{id}" withString:ch.fid];
    return [NSURL URLWithString:[[ADConfig shared] urlFor:p args:@{}]];
}

- (void)probeAuth:(void (^)(NSString *))cb {
    ADConfig *cfg = [ADConfig shared];
    NSString *savedH = cfg.authHeader, *savedS = cfg.authScheme;
    NSArray *combos = @[@[@"Authorization", @"Bearer"], @[@"Authorization", @"Token"], @[@"Authorization", @""],
                        @[@"X-Api-Key", @""], @[@"X-Token", @""], @[@"X-Access-Token", @""], @[@"token", @"@"],
                        @[@"X-Auth-Token", @""], @[@"api-key", @""]];
    NSMutableArray *tried = [NSMutableArray array];
    __block NSInteger i = 0;
    __block void (^step)(void);
    step = ^{
        if (i >= (NSInteger)combos.count) {
            cfg.authHeader = savedH; cfg.authScheme = savedS; [cfg save];
            cb([tried componentsJoinedByString:@"\n"]);
            return;
        }
        NSArray *c = combos[i];
        cfg.authHeader = c[0]; cfg.authScheme = [c[1] isEqualToString:@"@"] ? nil : c[1];
        [[ADAPI shared] me:^(id json, NSError *err, NSInteger code) {
            [tried addObject:[NSString stringWithFormat:@"%@: %@  →  HTTP %ld", c[0], c[1], (long)code]];
            if (code == 200) {
                cfg.authHeader = c[0]; cfg.authScheme = c[1]; [cfg save];
                [tried addObject:@"\n✅ 命中这一种，已自动保存"];
                cb([tried componentsJoinedByString:@"\n"]);
            } else { i++; step(); }
        }];
    };
    step();
}

@end
