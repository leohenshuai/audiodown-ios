#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface ADPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id ticker;
@property (nonatomic, assign) BOOL resolving;
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
}

- (void)playAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tracks.count) return;
    _index = index;
    ADTrack *t = _tracks[index];
    self.statusText = @"正在获取音频…";
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    [self resolveAndPlay:t attempt:0];
}

- (void)resolveAndPlay:(ADTrack *)t attempt:(NSInteger)attempt {
    if (_resolving) return;
    _resolving = YES;
    __weak typeof(self) w = self;
    [[ADApi shared] playURLOf:t done:^(NSString *url, NSDictionary *headers, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (!url) {
            self.resolving = NO;
            self.statusText = err ?: @"无法播放";
            [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
            return;
        }
        if ([err isEqualToString:@"WAIT"]) {
            // 番茄源需要先下载，轮询到就绪
            if (attempt > 40) {
                self.resolving = NO;
                self.statusText = @"音频还在准备，稍后会自动开始";
                [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
                return;
            }
            self.statusText = @"音频准备中…";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.resolving = NO;
                [self resolveAndPlay:t attempt:attempt + 1];
            });
            return;
        }
        self.resolving = NO;
        [self startWithURL:url headers:headers track:t];
    }];
}

- (void)startWithURL:(NSString *)url headers:(NSDictionary *)headers track:(ADTrack *)t {
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
    self.statusText = @"加载失败，检查 token 或换一集";
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
}

- (void)itemEnded:(NSNotification *)n {
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
