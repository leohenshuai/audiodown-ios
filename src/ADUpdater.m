#import "AD.h"
#import <Security/Security.h>

// GitHub Release 检查更新。仓库私有 → 需要令牌；令牌存 Keychain，不进备份
static NSString *const kRepo = @"leohenshuai/audiodown-ios";
static NSString *const kSvc = @"com.leo.audiodown.github";

@implementation ADUpdater

+ (NSString *)repo { return kRepo; }

+ (NSString *)token {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kSvc, (__bridge id)kSecAttrAccount: @"token",
                        (__bridge id)kSecReturnData: @YES, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess || !out) return @"";
    NSData *d = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

+ (void)setToken:(NSString *)t {
    NSDictionary *base = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService: kSvc, (__bridge id)kSecAttrAccount: @"token"};
    SecItemDelete((__bridge CFDictionaryRef)base);
    if (!t.length) return;
    NSMutableDictionary *add = [base mutableCopy];
    add[(__bridge id)kSecValueData] = [t dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

+ (NSMutableURLRequest *)req:(NSString *)url accept:(NSString *)accept {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [r setValue:accept forHTTPHeaderField:@"Accept"];
    [r setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [r setValue:@"YueTing-iOS" forHTTPHeaderField:@"User-Agent"];
    NSString *t = [self token];
    if (t.length) [r setValue:[@"Bearer " stringByAppendingString:t] forHTTPHeaderField:@"Authorization"];
    return r;
}

// 版本号按数字逐段比较："v5.13" > "5.9"
+ (BOOL)isNewer:(NSString *)remote than:(NSString *)local {
    NSString *(^clean)(NSString *) = ^NSString *(NSString *s) {
        s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([s.lowercaseString hasPrefix:@"v"]) s = [s substringFromIndex:1];
        NSRange dash = [s rangeOfString:@"-"]; if (dash.location != NSNotFound) s = [s substringToIndex:dash.location];
        return s;
    };
    NSArray *a = [clean(remote) componentsSeparatedByString:@"."], *b = [clean(local) componentsSeparatedByString:@"."];
    NSUInteger n = MAX(a.count, b.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger x = i < a.count ? [a[i] integerValue] : 0, y = i < b.count ? [b[i] integerValue] : 0;
        if (x != y) return x > y;
    }
    return NO;
}

+ (void)fetchLatest:(void (^)(NSDictionary *rel, NSString *err))cb {
    NSString *url = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", kRepo];
    [[[NSURLSession sharedSession] dataTaskWithRequest:[self req:url accept:@"application/vnd.github+json"] completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        NSString *err = nil; NSDictionary *out = nil;
        if (e) err = e.localizedDescription;
        else if (code == 401) err = @"令牌无效或已过期";
        else if (code == 403) err = @"令牌没有读取这个仓库的权限，或请求太频繁";
        else if (code == 404) err = @"没找到 Release（仓库还没发布过版本，或令牌看不到这个私有仓库）";
        else if (code != 200 || ![j isKindOfClass:NSDictionary.class]) err = [NSString stringWithFormat:@"GitHub 返回 %ld", (long)code];
        else {
            NSString *ipa = nil, *assetApi = nil; double size = 0;
            for (NSDictionary *a in j[@"assets"]) {
                if (![a isKindOfClass:NSDictionary.class]) continue;
                if ([[a[@"name"] lowercaseString] hasSuffix:@".ipa"]) { ipa = a[@"name"]; assetApi = a[@"url"]; size = [a[@"size"] doubleValue]; break; }
            }
            out = @{@"tag": j[@"tag_name"] ?: @"", @"name": j[@"name"] ?: @"", @"notes": j[@"body"] ?: @"",
                    @"page": j[@"html_url"] ?: [NSString stringWithFormat:@"https://github.com/%@/releases", kRepo],
                    @"ipa": ipa ?: @"", @"asset": assetApi ?: @"", @"size": @(size)};
        }
        dispatch_async(dispatch_get_main_queue(), ^{ cb(out, err); });
    }] resume];
}

// 私有仓库的附件要用 API 地址 + Accept: application/octet-stream 下载
+ (void)downloadAsset:(NSDictionary *)rel progress:(void (^)(double))prog done:(void (^)(NSURL *, NSString *))done {
    NSString *api = rel[@"asset"];
    if (!api.length) { done(nil, @"这个版本没有附带安装包"); return; }
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithRequest:[self req:api accept:@"application/octet-stream"] completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *e) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSURL *dst = nil; NSString *err = nil;
        if (e || code != 200 || !loc) err = e.localizedDescription ?: [NSString stringWithFormat:@"下载失败（%ld）", (long)code];
        else {
            NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/updates"];
            [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *name = [rel[@"ipa"] length] ? rel[@"ipa"] : [NSString stringWithFormat:@"YueTing-%@.ipa", rel[@"tag"]];
            dst = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
            [NSFileManager.defaultManager removeItemAtURL:dst error:nil];
            NSError *mv = nil;
            if (![NSFileManager.defaultManager moveItemAtURL:loc toURL:dst error:&mv]) { err = mv.localizedDescription; dst = nil; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(dst, err); });
    }];
    if (@available(iOS 11.0, *)) {
        __block NSKeyValueObservation *obs = nil;
        (void)obs;
    }
    [task resume];
    // 轮询进度（NSProgress KVO 在纯 ObjC 写法里较啰嗦，这里 0.4s 刷一次）
    __block NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) {
        if (task.state != NSURLSessionTaskStateRunning) { [t invalidate]; return; }
        double total = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : [rel[@"size"] doubleValue];
        if (total > 0) prog(MIN(1.0, task.countOfBytesReceived / total));
    }];
    (void)timer;
}

// 启动后静默检查（每天最多一次），有新版本时在设置的底栏图标上不打扰，只写入状态
+ (void)backgroundCheck {
    if (![self token].length) return;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    double last = [ud doubleForKey:@"ad_update_last"];
    if ([NSDate date].timeIntervalSince1970 - last < 86400) return;
    [self fetchLatest:^(NSDictionary *rel, NSString *err) {
        if (!rel) return;
        [ud setDouble:[NSDate date].timeIntervalSince1970 forKey:@"ad_update_last"];
        [ud setObject:rel[@"tag"] forKey:@"ad_update_tag"];
    }];
}
@end
