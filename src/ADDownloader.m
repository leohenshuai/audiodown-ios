#import "AD.h"
#import <AVFoundation/AVFoundation.h>

@interface ADDownloader () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSMutableArray<ADTask *> *tasks;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *current;
@property (nonatomic, strong) ADTask *runningTask;
@property (nonatomic, assign) BOOL resolving;
@end

@implementation ADDownloader

+ (instancetype)shared {
    static ADDownloader *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [ADDownloader new];
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
    _tasks = (d ? [NSKeyedUnarchiver unarchivedObjectOfClasses:set fromData:d error:nil] : nil) ?: [NSMutableArray array];
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
- (NSURL *)localURL:(NSString *)trackId {
    return [self hasLocal:trackId] ? [NSURL fileURLWithPath:[self fileFor:trackId]] : nil;
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

- (void)pauseTask:(ADTask *)t {
    if (!t) return;
    if (t == self.runningTask) {
        [self.current cancel];
        self.current = nil;
        self.runningTask = nil;
        self.resolving = NO;
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
    [self.current cancel]; self.current = nil; self.runningTask = nil;
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
    __weak typeof(self) w = self;
    [[ADApi shared] playURLOf:tr done:^(NSString *url, NSDictionary *headers, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.resolving = NO;
        if (!url) {
            t.failed += 1; t.cursor += 1;
            [self save]; [self notify];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self stepTask:t]; });
            return;
        }
        if ([err isEqualToString:@"WAIT"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self stepTask:t]; });
            return;
        }
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
    [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
    [[NSFileManager defaultManager] copyItemAtPath:location.path toPath:dst error:nil];
    ADTask *t = self.runningTask;
    if (!t) { for (ADTask *x in _tasks) if (x.state == ADTaskStateRunning) { t = x; break; } }
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        if (t) { t.done += 1; t.cursor += 1; }
        self.current = nil;
        [self save]; [self notify];
        if (t) [self stepTask:t];
    });
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) return;
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        ADTask *t = self.runningTask;
        if (t && t.state == ADTaskStateRunning) {
            t.failed += 1; t.cursor += 1;
            self.current = nil;
            [self save]; [self notify];
            [self stepTask:t];
        }
    });
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    self.runningTask.bytes = (double)total;
    static NSDate *last; static dispatch_once_t once;
    dispatch_once(&once, ^{ last = [NSDate date]; });
    if ([[NSDate date] timeIntervalSinceDate:last] > 0.4) {
        last = [NSDate date];
        dispatch_async(dispatch_get_main_queue(), ^{ [self notify]; });
    }
}
@end
