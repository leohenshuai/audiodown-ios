#import "AD.h"
#include <ifaddrs.h>
#include <net/if.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface ADPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id ticker;
// 用一个自增序号代替原来的 _resolving 互斥标志：
// 旧写法里连续点两集时，前一次请求没回来，后一次会被直接丢弃，
// 界面就一直停在「正在获取音频…」。现在新请求直接接管，旧回调按序号作废。
@property (nonatomic, assign) NSInteger resolveSeq;
@property (nonatomic, assign) BOOL retriedItem;
// 播放队列补全：专辑页只加载了前几十集时，播放器自己把后面的目录补齐，
// 否则队列的「倒序」「快速选集」「缓存整本」都只能看到前 50 集。
@property (nonatomic, assign) BOOL filling;
- (void)ensureFullQueue;
- (void)fillQueuePage:(NSInteger)page tries:(NSInteger)tries forAlbum:(NSString *)albumId;
@end

@implementation ADPlayer

+ (instancetype)shared {
    static ADPlayer *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [ADPlayer new]; [p setup]; });
    return p;
}

- (void)setup {
    _tracks = @[];
    _rate = [NSUserDefaults.standardUserDefaults floatForKey:@"ad.rate"];
    if (_rate <= 0) _rate = 1.0f;
    AVAudioSession *s = AVAudioSession.sharedInstance;
    [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeSpokenAudio options:0 error:nil];
    [s setActive:YES error:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    [self remoteCommands];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tickSleep) userInfo:nil repeats:YES];
}

- (AVPlayer *)player { return _player; }
- (ADTrack *)current {
    if (_index < 0 || _index >= (NSInteger)_tracks.count) return nil;
    return _tracks[_index];
}
- (BOOL)isPlaying { return _player.rate > 0; }

- (void)playAlbum:(ADAlbum *)album tracks:(NSArray<ADTrack *> *)tracks at:(NSInteger)index {
    _album = album;
    _tracks = tracks ?: @[];
    [[ADStore shared] touchHistory:album];
    NSInteger start = index;
    NSString *last = [[ADStore shared] lastTrackOf:album.albumId];
    if (index <= 0 && last.length) {
        for (NSInteger i = 0; i < (NSInteger)_tracks.count; i++) {
            if ([_tracks[i].trackId isEqualToString:last]) { start = i; break; }
        }
    }
    [self playAt:start];
    [self ensureFullQueue];
}

// ── 队列补全 ─────────────────────────────────────────
- (void)fillQueuePage:(NSInteger)page tries:(NSInteger)tries forAlbum:(NSString *)albumId {
    if (!albumId.length) { self.filling = NO; return; }
    __weak typeof(self) w = self;
    [[ADApi shared] tracksOf:albumId page:page done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (!self.album || ![self.album.albumId isEqualToString:albumId]) { self.filling = NO; return; }
        if (cached) return;                       // 缓存那条由专辑页处理，这里只认网络结果
        if (err.length) {
            if (tries < 2) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(w) s = w; if (!s) return;
                    [s fillQueuePage:page tries:tries + 1 forAlbum:albumId];
                });
            } else {
                self.filling = NO;
            }
            return;
        }
        if (!list.count) { self.filling = NO; return; }
        NSMutableArray *merged = [self.tracks mutableCopy] ?: [NSMutableArray array];
        NSMutableSet *have = [NSMutableSet set];
        for (ADTrack *t in merged) if (t.trackId.length) [have addObject:t.trackId];
        NSInteger added = 0;
        for (ADTrack *t in list) {
            if (!t.trackId.length || [have containsObject:t.trackId]) continue;
            [merged addObject:t]; [have addObject:t.trackId]; added++;
        }
        if (added > 0) {
            self.tracks = merged;                 // 只往末尾追加，当前播放的 _index 不受影响
            [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
        }
        if (added == 0 || list.count < 50) { self.filling = NO; return; }
        [self fillQueuePage:page + 1 tries:0 forAlbum:albumId];
    }];
}

- (void)ensureFullQueue {
    if (self.filling) return;
    if (!self.album || !self.tracks.count) return;
    if ((NSInteger)self.tracks.count % 50 != 0) return;   // 不是被截断的样子，不用补
    self.filling = YES;
    [self fillQueuePage:(NSInteger)self.tracks.count / 50 + 1 tries:0 forAlbum:self.album.albumId];
}

- (void)playAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tracks.count) return;
    _index = index;
    self.retriedItem = NO;
    ADTrack *t = _tracks[index];
    NSURL *local = [[ADDownloader shared] localURL:t.trackId];
    if (!local) {
        NSString *pp = [self prefetchPath:t.trackId];
        if ([NSFileManager.defaultManager fileExistsAtPath:pp]) local = [NSURL fileURLWithPath:pp];
    }
    if (local) {
        [self startWithURL:local.absoluteString headers:@{} track:t];
        return;
    }
    self.statusText = @"正在获取音频…";
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    [self resolveAndPlay:t attempt:0];
}

- (NSString *)prefetchDir {
    static NSString *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/cache/prefetch"];
        [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return d;
}

- (NSString *)prefetchPath:(NSString *)trackId {
    return [[self prefetchDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", trackId]];
}

- (void)cleanPrefetch {
    NSInteger days = [[NSUserDefaults standardUserDefaults] integerForKey:@"ad_prefetch_days"];
    if (days <= 0) days = 3;
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:-days * 86400];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *f in [fm contentsOfDirectoryAtPath:[self prefetchDir] error:nil]) {
        NSString *p = [[self prefetchDir] stringByAppendingPathComponent:f];
        NSDictionary *attr = [fm attributesOfItemAtPath:p error:nil];
        if ([attr.fileModificationDate compare:limit] == NSOrderedAscending) [fm removeItemAtPath:p error:nil];
    }
}

+ (BOOL)isWiFi {
    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0) return NO;
    BOOL on = NO;
    for (struct ifaddrs *a = addrs; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
        if (strcmp(a->ifa_name, "en0") == 0) { on = YES; break; }
    }
    freeifaddrs(addrs);
    return on;
}

- (void)prefetchAhead {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if (![ud boolForKey:@"ad_prefetch"]) return;
    if ([ud boolForKey:@"ad_prefetch_wifi"] && ![ADPlayer isWiFi]) return;
    NSInteger n = [ud integerForKey:@"ad_prefetch_count"];
    if (n <= 0) n = 2;
    if (!self.prefetching) self.prefetching = [NSMutableSet set];
    for (NSInteger k = 1; k <= n; k++) {
        NSInteger i = _index + k;
        if (i >= (NSInteger)_tracks.count) break;
        ADTrack *t = _tracks[i];
        if ([[ADDownloader shared] hasLocal:t.trackId]) continue;
        if ([NSFileManager.defaultManager fileExistsAtPath:[self prefetchPath:t.trackId]]) continue;
        if ([self.prefetching containsObject:t.trackId]) continue;
        [self.prefetching addObject:t.trackId];
        __weak typeof(self) w = self;
        [[ADApi shared] playURLOf:t done:^(NSString *url, NSDictionary *headers, NSString *err) {
            __strong typeof(w) self = w; if (!self) return;
            if (!url.length || [err isEqualToString:@"WAIT"]) { [self.prefetching removeObject:t.trackId]; return; }
            NSMutableDictionary *h = [NSMutableDictionary dictionary];
            [headers enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
                if ([val isKindOfClass:NSString.class] && [val length]) h[key] = val;
            }];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
            req.timeoutInterval = 60;
            for (NSString *key in h) [req setValue:h[key] forHTTPHeaderField:key];
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                [self.prefetching removeObject:t.trackId];
                if (data.length > 40000) [data writeToFile:[self prefetchPath:t.trackId] atomically:YES];
            }];
            [task resume];
        }];
    }
}

- (void)resolveAndPlay:(ADTrack *)t attempt:(NSInteger)attempt {
    if (attempt == 0) self.resolveSeq += 1;          // 新的播放请求，作废之前所有在飞的请求
    NSInteger seq = self.resolveSeq;
    __weak typeof(self) w = self;
    [[ADApi shared] playURLOf:t done:^(NSString *url, NSDictionary *headers, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (seq != self.resolveSeq) return;          // 已被后来的请求取代
        if (!url) {
            // 取地址失败（超时 / 服务端 5xx）先自己重试一次，别直接甩错误
            if (attempt < 1) {
                self.statusText = @"获取音频失败，正在重试…";
                [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(w) s = w; if (!s) return;
                    [s resolveAndPlay:t attempt:attempt + 1];
                });
                return;
            }
            self.statusText = err ?: @"无法播放";
            [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
            return;
        }
        if ([err isEqualToString:@"WAIT"]) {
            // 番茄源需要先下载，轮询到就绪
            if (attempt > 40) {
                self.statusText = @"音频还在准备，稍后会自动开始";
                [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
                return;
            }
            self.statusText = @"音频准备中…";
            [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(w) s = w; if (!s) return;
                if (seq != s.resolveSeq) return;
                [s resolveAndPlay:t attempt:attempt + 1];
            });
            return;
        }
        [self startWithURL:url headers:headers track:t];
    }];
}

- (void)startWithURL:(NSString *)url headers:(NSDictionary *)headers track:(ADTrack *)t {
    [self prefetchAhead];
    [self cleanPrefetch];
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    // 过滤空值
    [headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) {
        if ([v isKindOfClass:NSString.class] && [v length]) h[k] = v;
    }];
    if (h.count) opts[@"AVURLAssetHTTPHeaderFieldsKey"] = h;
    NSURL *u = [NSURL URLWithString:url];
    if (!u) { self.statusText = @"音频地址无效"; return; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:u options:opts];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    if (!_player) _player = [AVPlayer playerWithPlayerItem:item];
    else [_player replaceCurrentItemWithPlayerItem:item];
    _player.automaticallyWaitsToMinimizeStalling = YES;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(failed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];

    if (_ticker) [_player removeTimeObserver:_ticker];
    __weak typeof(self) w = self;
    _ticker = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.7, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        __strong typeof(w) self = w; if (!self) return;
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerTick" object:nil];
        double sec = CMTimeGetSeconds(time);
        if (self.current.trackId && sec > 0) {
            [[ADStore shared] setPosition:sec for:self.current.trackId];
            [[ADStore shared] setLastTrack:self.current.trackId album:self.album.albumId];
            double d = self.player.currentItem ? CMTimeGetSeconds(self.player.currentItem.duration) : 0;
            [[ADStore shared] setLastInfo:@{@"trackId": self.current.trackId ?: @"",
                                            @"index": @(self.index),
                                            @"title": self.current.title ?: @"",
                                            @"seconds": @(sec),
                                            @"duration": @(isnan(d) ? 0 : d)} album:self.album.albumId];
        }
    }];

    double saved = [[ADStore shared] positionFor:t.trackId];
    if (saved > 5) [_player seekToTime:CMTimeMakeWithSeconds(saved, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    _player.rate = _rate;
    self.statusText = nil;
    [[ADStore shared] setLastTrack:t.trackId album:self.album.albumId];
    [[ADStore shared] touchHistory:self.album];
    [self nowPlaying];
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
}

- (void)failed:(NSNotification *)n {
    // 音频地址有时效，过期后会 403。先按原集重新取一次地址再报错
    if (!self.retriedItem && self.index >= 0 && self.index < (NSInteger)_tracks.count) {
        self.retriedItem = YES;
        ADTrack *t = _tracks[self.index];
        self.statusText = @"音频地址失效，正在重新获取…";
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
        [self resolveAndPlay:t attempt:0];
        return;
    }
    self.statusText = @"加载失败，检查 token 或换一集";
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
}

- (void)itemEnded:(NSNotification *)n {
    ADTrack *cur = self.current;
    if (cur.trackId) {
        BOOL last = (_index + 1 >= (NSInteger)_tracks.count);
        [[ADStore shared] markDone:cur.trackId album:_album.albumId wholeBook:last];
    }
    if (self.stopAfterChapter) {
        self.stopAfterChapter = NO;
        [_player pause];
        [self nowPlaying];
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
        return;
    }
    if (_index + 1 < (NSInteger)_tracks.count) [self next];
    else { [_player pause]; [self nowPlaying]; }
}

- (void)toggle {
    if (!_player) { if (_tracks.count) [self playAt:_index]; return; }
    if (_player.rate > 0) [self pause];
    else { [_player play]; _player.rate = _rate; [self nowPlaying]; }
}
- (void)pause { [_player pause]; [self nowPlaying]; }
- (void)next { if (_index + 1 < (NSInteger)_tracks.count) [self playAt:_index + 1]; }
- (void)prev {
    double sec = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    if (sec > 5) { [self seekTo:0]; return; }
    if (_index > 0) [self playAt:_index - 1];
}
- (void)seekTo:(double)sec {
    if (!_player) return;
    [_player seekToTime:CMTimeMakeWithSeconds(MAX(0, sec), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}
- (void)seekBy:(double)delta { [self seekTo:CMTimeGetSeconds(_player.currentTime) + delta]; }

- (void)setRate:(float)rate {
    _rate = rate;
    if (_player.rate > 0) _player.rate = rate;
    [NSUserDefaults.standardUserDefaults setFloat:rate forKey:@"ad.rate"];
    [self nowPlaying];
}

- (void)tickSleep {
    if (_sleepDeadline > 0 && [NSDate date].timeIntervalSince1970 >= _sleepDeadline) {
        _sleepDeadline = 0;
        [self pause];
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    }
}

- (void)nowPlaying {
    ADTrack *t = self.current;
    if (!t) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = t.title ?: @"";
    info[MPMediaItemPropertyArtist] = _album.title ?: @"";
    info[MPMediaItemPropertyAlbumTitle] = _album.anchor ?: @"";
    if (_player.currentItem) {
        double dur = CMTimeGetSeconds(_player.currentItem.duration);
        if (dur > 0 && !isnan(dur)) {
            info[MPMediaItemPropertyPlaybackDuration] = @(dur);
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime));
        }
    }
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player ? _player.rate : 0);
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    MPNowPlayingInfoCenter.defaultCenter.playbackState = (_player.rate > 0) ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
}

- (void)remoteCommands {
    MPRemoteCommandCenter *c = MPRemoteCommandCenter.sharedCommandCenter;
    __weak typeof(self) w = self;
    [c.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; if (s.isPlaying) return MPRemoteCommandHandlerStatusSuccess;
        [s toggle]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s pause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s toggle]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s next]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s prev]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.skipForwardCommand setPreferredIntervals:@[@30]];
    [c.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s seekBy:30]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.skipBackwardCommand setPreferredIntervals:@[@15]];
    [c.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        __strong typeof(w) s = w; [s seekBy:-15]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        MPChangePlaybackPositionCommandEvent *ev = (id)e;
        __strong typeof(w) s = w; [s seekTo:ev.positionTime]; return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)interrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeEnded) [[AVAudioSession sharedInstance] setActive:YES error:nil];
    else [self pause];
}

- (void)routeChanged:(NSNotification *)n {
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) [self pause];
}
@end
