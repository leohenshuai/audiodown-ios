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
    _baseURL = ADPref(@"ad.base", @"https://audio.959935291.xyz:899");
    _token = ADPref(@"ad.token", @"");
    _username = ADPref(@"ad.user", @"");
    _password = ADPref(@"ad.pass", @"");
}
- (void)save {
    NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
    [u setObject:_baseURL forKey:@"ad.base"];
    [u setObject:_token forKey:@"ad.token"];
    [u setObject:_username ?: @"" forKey:@"ad.user"];
    [u setObject:_password ?: @"" forKey:@"ad.pass"];
}
- (NSDictionary *)headers {
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    h[@"Accept"] = @"application/json";
    if (_token.length) h[@"Authorization"] = [@"Bearer " stringByAppendingString:_token];
    return h;
}
- (NSString *)url:(NSString *)path {
    NSString *b = _baseURL;
    while (b.length && [b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [b stringByAppendingString:path];
}
@end

// ───────────────── 模型 ─────────────────
static NSString *ADStr(id o, NSString *k) {
    if (![o isKindOfClass:NSDictionary.class]) return nil;
    id v = o[k];
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [v stringValue];
    return nil;
}
static double ADNum(id o, NSString *k) {
    if (![o isKindOfClass:NSDictionary.class]) return 0;
    id v = o[k];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}

@implementation ADAlbum
+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    ADAlbum *a = [ADAlbum new];
    a.albumId = ADStr(j, @"albumId") ?: ADStr(j, @"id") ?: @"";
    a.title = ADStr(j, @"title") ?: ADStr(j, @"rawTitle") ?: @"未命名";
    a.cover = ADStr(j, @"cover") ?: @"";
    a.anchor = ADStr(j, @"anchorName") ?: @"";
    a.author = ADStr(j, @"author") ?: @"";
    a.reader = ADStr(j, @"reader") ?: @"";
    a.intro = ADStr(j, @"intro") ?: @"";
    a.provider = ADStr(j, @"provider") ?: @"";
    a.trackCount = (NSInteger)ADNum(j, @"trackCount");
    a.playCount = ADNum(j, @"playCount");
    a.isFinished = ADNum(j, @"isFinished") > 0;
    a.isPaid = ADNum(j, @"isPaid") > 0;
    return a.albumId.length ? a : nil;
}
- (void)encodeWithCoder:(NSCoder *)c {
    for (NSString *k in @[@"albumId", @"title", @"cover", @"anchor", @"author", @"reader", @"intro", @"provider"])
        [c encodeObject:[self valueForKey:k] forKey:k];
    [c encodeInteger:_trackCount forKey:@"trackCount"];
    [c encodeDouble:_playCount forKey:@"playCount"];
    [c encodeBool:_isFinished forKey:@"isFinished"];
    [c encodeBool:_isPaid forKey:@"isPaid"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        for (NSString *k in @[@"albumId", @"title", @"cover", @"anchor", @"author", @"reader", @"intro", @"provider"])
            [self setValue:[c decodeObjectForKey:k] forKey:k];
        _trackCount = [c decodeIntegerForKey:@"trackCount"];
        _playCount = [c decodeDoubleForKey:@"playCount"];
        _isFinished = [c decodeBoolForKey:@"isFinished"];
        _isPaid = [c decodeBoolForKey:@"isPaid"];
    }
    return self;
}
@end

@implementation ADTrack
+ (instancetype)fromJSON:(NSDictionary *)j album:(ADAlbum *)a {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    ADTrack *t = [ADTrack new];
    t.trackId = ADStr(j, @"trackId") ?: ADStr(j, @"id") ?: @"";
    t.title = ADStr(j, @"title") ?: ADStr(j, @"trackTitle") ?: t.trackId;
    t.albumId = ADStr(j, @"albumId") ?: a.albumId;
    t.provider = ADStr(j, @"provider") ?: a.provider;
    t.index = (NSInteger)ADNum(j, @"index");
    t.duration = ADNum(j, @"duration");
    return t.trackId.length ? t : nil;
}
@end

// ───────────────── 存储 ─────────────────
@implementation ADStore {
    NSMutableArray<ADAlbum *> *_fav;
    NSMutableArray<ADAlbum *> *_hist;
    NSMutableDictionary<NSString *, NSNumber *> *_pos;
    NSMutableDictionary<NSString *, NSString *> *_last;
    NSMutableDictionary<NSString *, NSDictionary *> *_info;
    NSMutableSet<NSString *> *_done;
    NSMutableSet<NSString *> *_doneAlbums;
    NSMutableArray<ADAlbum *> *_want;
    NSMutableSet<NSString *> *_pin;
    NSMutableArray<NSDictionary *> *_bm;
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
    NSData *d1 = [NSData dataWithContentsOfFile:[self path:@"fav.dat"]];
    NSData *d2 = [NSData dataWithContentsOfFile:[self path:@"hist.dat"]];
    NSData *d3 = [NSData dataWithContentsOfFile:[self path:@"pos.dat"]];
    NSData *d4 = [NSData dataWithContentsOfFile:[self path:@"last.dat"]];
    NSSet *setA = [NSSet setWithObjects:NSMutableArray.class, NSArray.class, ADAlbum.class, NSString.class, nil];
    _fav = (d1 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setA fromData:d1 error:nil] : nil) ?: [NSMutableArray array];
    _hist = (d2 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setA fromData:d2 error:nil] : nil) ?: [NSMutableArray array];
    NSSet *setD = [NSSet setWithObjects:NSMutableDictionary.class, NSDictionary.class, NSString.class, NSNumber.class, nil];
    _pos = (d3 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setD fromData:d3 error:nil] : nil) ?: [NSMutableDictionary dictionary];
    _last = (d4 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setD fromData:d4 error:nil] : nil) ?: [NSMutableDictionary dictionary];
    NSData *d5 = [NSData dataWithContentsOfFile:[self path:@"info.dat"]];
    _info = (d5 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setD fromData:d5 error:nil] : nil) ?: [NSMutableDictionary dictionary];
    NSSet *setS = [NSSet setWithObjects:NSSet.class, NSMutableSet.class, NSString.class, nil];
    NSData *d6 = [NSData dataWithContentsOfFile:[self path:@"done.dat"]];
    NSData *d7 = [NSData dataWithContentsOfFile:[self path:@"donealbums.dat"]];
    _done = (d6 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setS fromData:d6 error:nil] : nil) ?: [NSMutableSet set];
    _doneAlbums = (d7 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setS fromData:d7 error:nil] : nil) ?: [NSMutableSet set];
    NSData *d8 = [NSData dataWithContentsOfFile:[self path:@"want.dat"]];
    NSData *d9 = [NSData dataWithContentsOfFile:[self path:@"pin.dat"]];
    _want = (d8 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setA fromData:d8 error:nil] : nil) ?: [NSMutableArray array];
    _pin = (d9 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setS fromData:d9 error:nil] : nil) ?: [NSMutableSet set];
    NSData *d10 = [NSData dataWithContentsOfFile:[self path:@"bm.dat"]];
    NSSet *setB = [NSSet setWithObjects:NSMutableArray.class, NSArray.class, NSDictionary.class, NSMutableDictionary.class, NSString.class, NSNumber.class, nil];
    _bm = (d10 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:setB fromData:d10 error:nil] : nil) ?: [NSMutableArray array];
    _bm = [_bm mutableCopy];
}
- (void)reload { [self load]; [NSNotificationCenter.defaultCenter postNotificationName:@"ADDoneChanged" object:nil]; }
- (NSString *)docPath:(NSString *)name { return [self path:name]; }
- (NSArray<NSDictionary *> *)bookmarks { return _bm; }
- (void)addBookmark:(NSDictionary *)bm { if (bm) { [_bm insertObject:bm atIndex:0]; [self save]; } }
- (void)removeBookmark:(NSDictionary *)bm { [_bm removeObject:bm]; [self save]; }
- (void)save {
    [[NSKeyedArchiver archivedDataWithRootObject:_fav requiringSecureCoding:NO error:nil] writeToFile:[self path:@"fav.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_hist requiringSecureCoding:NO error:nil] writeToFile:[self path:@"hist.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_pos requiringSecureCoding:NO error:nil] writeToFile:[self path:@"pos.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_last requiringSecureCoding:NO error:nil] writeToFile:[self path:@"last.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_info requiringSecureCoding:NO error:nil] writeToFile:[self path:@"info.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_done requiringSecureCoding:NO error:nil] writeToFile:[self path:@"done.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_doneAlbums requiringSecureCoding:NO error:nil] writeToFile:[self path:@"donealbums.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_want requiringSecureCoding:NO error:nil] writeToFile:[self path:@"want.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_pin requiringSecureCoding:NO error:nil] writeToFile:[self path:@"pin.dat"] atomically:YES];
    [[NSKeyedArchiver archivedDataWithRootObject:_bm requiringSecureCoding:NO error:nil] writeToFile:[self path:@"bm.dat"] atomically:YES];
}
- (NSArray<ADAlbum *> *)favorites { return _fav; }
- (NSArray<ADAlbum *> *)history { return _hist; }
- (BOOL)isFavorite:(NSString *)albumId {
    for (ADAlbum *a in _fav) if ([a.albumId isEqualToString:albumId]) return YES;
    return NO;
}
- (void)toggleFavorite:(ADAlbum *)a {
    ADAlbum *hit = nil;
    for (ADAlbum *x in _fav) if ([x.albumId isEqualToString:a.albumId]) { hit = x; break; }
    if (hit) [_fav removeObject:hit]; else [_fav insertObject:a atIndex:0];
    [self save];
}
- (void)touchHistory:(ADAlbum *)a {
    ADAlbum *hit = nil;
    for (ADAlbum *x in _hist) if ([x.albumId isEqualToString:a.albumId]) { hit = x; break; }
    BOOL wasFirst = (hit && _hist.firstObject == hit);
    if (hit) [_hist removeObject:hit];
    [_hist insertObject:a atIndex:0];
    while (_hist.count > 30) [_hist removeLastObject];
    [self save];
    // 新出现或顺序变化时通知首页重建“继续收听”（以前从不通知，移除后再听回不来）
    if (!wasFirst) [NSNotificationCenter.defaultCenter postNotificationName:@"ADContinueChanged" object:nil];
}
- (void)removeContinue:(NSString *)albumId {
    if (!albumId.length) return;
    for (ADAlbum *x in [_hist copy]) if ([x.albumId isEqualToString:albumId]) [_hist removeObject:x];
    [self save];
}
- (double)positionFor:(NSString *)trackId { return trackId ? [_pos[trackId] doubleValue] : 0; }
- (BOOL)isDone:(NSString *)trackId {
    return trackId.length && [_done containsObject:trackId];
}

- (void)markDone:(NSString *)trackId album:(NSString *)albumId wholeBook:(BOOL)whole {
    BOOL changed = NO;
    if (trackId.length && ![_done containsObject:trackId]) { [_done addObject:trackId]; changed = YES; }
    if (whole && albumId.length && ![_doneAlbums containsObject:albumId]) { [_doneAlbums addObject:albumId]; changed = YES; }
    if (changed) {
        [self save];
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADDoneChanged" object:nil];
    }
}

- (BOOL)isAlbumDone:(NSString *)albumId {
    return albumId.length && [_doneAlbums containsObject:albumId];
}

- (void)setPosition:(double)sec for:(NSString *)trackId { if (trackId) _pos[trackId] = @(sec); [self save]; }
- (NSArray<ADAlbum *> *)wants { return _want; }
- (BOOL)isWanted:(NSString *)albumId {
    for (ADAlbum *a in _want) if ([a.albumId isEqualToString:albumId]) return YES;
    return NO;
}
- (void)toggleWant:(ADAlbum *)a {
    ADAlbum *hit = nil;
    for (ADAlbum *x in _want) if ([x.albumId isEqualToString:a.albumId]) { hit = x; break; }
    if (hit) [_want removeObject:hit]; else [_want insertObject:a atIndex:0];
    [self save];
}
- (BOOL)isPinned:(NSString *)albumId { return albumId.length && [_pin containsObject:albumId]; }
- (void)togglePin:(NSString *)albumId {
    if (!albumId.length) return;
    if ([_pin containsObject:albumId]) [_pin removeObject:albumId]; else [_pin addObject:albumId];
    [self save];
}
- (void)removeHistory:(NSString *)albumId {
    if (!albumId.length) return;
    for (ADAlbum *x in [_hist copy]) if ([x.albumId isEqualToString:albumId]) [_hist removeObject:x];
    for (ADAlbum *x in [_fav copy]) if ([x.albumId isEqualToString:albumId]) [_fav removeObject:x];
    for (ADAlbum *x in [_want copy]) if ([x.albumId isEqualToString:albumId]) [_want removeObject:x];
    [self save];
}
- (NSString *)lastTrackOf:(NSString *)albumId { return albumId ? _last[albumId] : nil; }
- (NSDictionary *)lastInfoOf:(NSString *)albumId {
    id v = albumId ? _info[albumId] : nil;
    return [v isKindOfClass:NSDictionary.class] ? v : nil;
}
- (void)setLastInfo:(NSDictionary *)info album:(NSString *)albumId {
    BOOL fresh = (albumId && !_info[albumId]);
    if (albumId && info) _info[albumId] = info;
    [self save];
    if (fresh) [NSNotificationCenter.defaultCenter postNotificationName:@"ADContinueChanged" object:nil];
}
- (void)setLastTrack:(NSString *)trackId album:(NSString *)albumId {
    if (albumId && trackId) _last[albumId] = trackId;
    [self save];
}
@end

// ───────────────── 工具 ─────────────────
@implementation ADUtil
+ (UIColor *)brand { return [UIColor colorWithRed:0.973 green:0.392 blue:0.26 alpha:1]; }
+ (UIColor *)bg { return [UIColor colorWithRed:0.067 green:0.047 blue:0.035 alpha:1]; }
+ (UIColor *)card { return [UIColor colorWithWhite:1 alpha:0.07]; }
+ (UIColor *)dim { return [UIColor colorWithWhite:1 alpha:0.55]; }
+ (UILabel *)label:(NSString *)font size:(CGFloat)size color:(UIColor *)c {
    UILabel *l = [UILabel new];
    UIFont *f = font.length ? [UIFont fontWithName:font size:size] : nil;
    l.font = f ?: [UIFont systemFontOfSize:size];
    l.textColor = c;
    l.numberOfLines = 0;
    return l;
}
+ (NSString *)time:(double)sec {
    if (isnan(sec) || sec < 0) sec = 0;
    int s = (int)sec, h = s / 3600, m = (s % 3600) / 60, q = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%d:%02d:%02d", h, m, q];
    return [NSString stringWithFormat:@"%02d:%02d", m, q];
}
+ (NSString *)count:(double)n {
    if (n >= 100000000) return [NSString stringWithFormat:@"%.1f亿", n / 100000000];
    if (n >= 10000) return [NSString stringWithFormat:@"%.1f万", n / 10000];
    return [NSString stringWithFormat:@"%.0f", n];
}
+ (double)parseDuration:(NSString *)text {
    if (!text.length) return 0;
    NSString *t = [[text lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    double total = 0;
    NSScanner *sc = [NSScanner scannerWithString:t];
    while (!sc.isAtEnd) {
        double v = 0;
        if (![sc scanDouble:&v]) { sc.scanLocation = sc.scanLocation + 1; continue; }
        NSString *unit = nil;
        [sc scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&unit];
        if (!unit.length) total += v * 60;              // 纯数字按分钟
        else if ([unit hasPrefix:@"h"]) total += v * 3600;
        else if ([unit hasPrefix:@"s"]) total += v;
        else total += v * 60;
    }
    return total;
}

+ (void)togglePlaceholder:(UIImageView *)iv hidden:(BOOL)h {
    for (UIView *v in iv.subviews) if (v.tag == 8801) v.hidden = h;
}

+ (NSString *)coverDir {
    static NSString *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/cache/covers"];
        [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return d;
}

+ (void)cover:(UIImageView *)iv url:(NSString *)url {
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    iv.image = nil;
    if (!url.length) return;
    NSURL *u = [url hasPrefix:@"http"] ? [NSURL URLWithString:url] : [NSURL URLWithString:[[ADConfig shared] url:url]];
    if (!u) return;
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 400; });
    UIImage *hit = [cache objectForKey:url];
    if (hit) { iv.image = hit; [self togglePlaceholder:iv hidden:YES]; return; }
    NSString *path = [[self coverDir] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%lu.jpg", (unsigned long)url.hash]];
    UIImage *disk = [UIImage imageWithContentsOfFile:path];
    if (disk) { [self togglePlaceholder:iv hidden:YES];
        [cache setObject:disk forKey:url];
        iv.image = disk;
        return;
    }
    [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        UIImage *img = data.length ? [UIImage imageWithData:data] : nil;
        if (!img) return;
        [cache setObject:img forKey:url];
        [data writeToFile:path atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            iv.image = img;
            [self togglePlaceholder:iv hidden:YES];
        });
    }] resume];
}
@end
