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
@end

@implementation ADDownloader

+ (instancetype)shared {
    static ADDownloader *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [ADDownloader new];
        d.retryMap = [NSMutableDictionary dictionary];
        NSArray *fa = [NSUserDefaults.standardUserDefaults arrayForKey:@"ad_dl_failed"];
        d.failedIds = fa ? [NSMutableSet setWithArray:fa] : [NSMutableSet set];
        [d load];
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        d.session = [NSURLSession sessionWithConfiguration:c delegate:d delegateQueue:nil];
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
    for (ADTask *t in _tasks) if (t.state == ADTaskStateRunning) t.state = ADTaskStatePaused;
}
- (void)save {
    [[NSKeyedArchiver archivedDataWithRootObject:_tasks requiringSecureCoding:NO error:nil] writeToFile:[self listPath] atomically:YES];
}
- (void)notify { [NSNotificationCenter.defaultCenter postNotificationName:@"ADDownloadChanged" object:nil]; }

- (NSArray<ADTask *> *)tasks { return _tasks; }

- (NSString *)fileFor:(NSString *)trackId {
    return [[self audioDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", trackId]];
}
- (BOOL)hasLocal:(NSString *)trackId {
    return trackId && [NSFileManager.defaultManager fileExistsAtPath:[self fileFor:trackId]];
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
    if (t.state != ADTaskStateRunning) { self.runningTask = nil; [self pump]; return; }
    if (t.cursor >= (NSInteger)t.tracks.count) {
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
        [self notify];
    }];
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    NSString *tid = task.taskDescription;
    NSString *dst = [self fileFor:tid];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dst error:nil];
    [fm copyItemAtPath:location.path toPath:dst error:nil];
    NSDictionary *attr = [fm attributesOfItemAtPath:dst error:nil];
    // 文件没写成 / 太小（多半是服务端返回的错误页）就别当成功，交回重试
    if (!attr || [attr fileSize] < 8000) {
        [fm removeItemAtPath:dst error:nil];
        __weak typeof(self) w0 = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(w0) self = w0; if (!self) return;
            ADTask *t0 = self.runningTask;
            if (!t0 || t0.state != ADTaskStateRunning) return;
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
    ADTask *t = self.runningTask;
    if (!t) { for (ADTask *x in _tasks) if (x.state == ADTaskStateRunning) { t = x; break; } }
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        if (t) { t.done += 1; t.cursor += 1; }
        if (tid.length && [self.failedIds containsObject:tid]) { [self.failedIds removeObject:tid]; [self saveFailed]; }
        self.currentTrackId = nil; self.currentWritten = 0; self.currentExpected = 0;
        self.current = nil;
        [self save]; [self notify];
        if (t) [self stepTask:t];
    });
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error || error.code == NSURLErrorCancelled) return;   // 暂停/删除时主动取消，不算失败
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        ADTask *t = self.runningTask;
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
