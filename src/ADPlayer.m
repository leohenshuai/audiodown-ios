#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

@interface ADPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) double lastReport;
@property (nonatomic, strong) NSTimer *sleepTimer;
@end

@implementation ADPlayer

+ (instancetype)shared {
    static ADPlayer *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [ADPlayer new]; [p setup]; });
    return p;
}

- (void)setup {
    _rate = 1.0f;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeSpokenAudio options:0 error:nil];
    [s setActive:YES error:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    [self setupRemoteCommands];
}

- (AVPlayer *)player { return _player; }

- (ADChapter *)currentChapter {
    if (!_book || _index < 0 || _index >= (NSInteger)_book.chapters.count) return nil;
    return _book.chapters[_index];
}

- (void)attachObservers {
    __weak typeof(self) weakSelf = self;
    if (_timeObserver) [_player removeTimeObserver:_timeObserver];
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime t) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ADPlayerTick" object:nil];
        double sec = CMTimeGetSeconds(t);
        double dur = CMTimeGetSeconds(self.player.currentItem.duration);
        // 每 15 秒上报一次进度
        if (sec - self.lastReport > 15 && self.book.bid.length) {
            self.lastReport = sec;
            double p = dur > 0 ? sec / dur : 0;
            [[ADStore shared] setProgress:sec forChapter:self.currentChapter.fid];
            [[ADAPI shared] reportProgress:self.book.bid chapter:self.currentChapter.fid seconds:sec chapterProgress:p];
        }
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
}

- (void)playBook:(ADBook *)book at:(NSInteger)index {
    _book = book; _index = index;
    NSString *last = [[ADStore shared] lastChapterOfBook:book.bid];
    if (last.length) {
        for (NSInteger i = 0; i < (NSInteger)book.chapters.count; i++) {
            if ([book.chapters[i].fid isEqualToString:last]) {
                if (index == 0 && [NSUserDefaults.standardUserDefaults boolForKey:@"resumeLast"] != NO) index = i;
                break;
            }
        }
        _index = index;
    }
    [self playIndex:_index];
}

- (void)playIndex:(NSInteger)index {
    if (!_book || index < 0 || index >= (NSInteger)_book.chapters.count) return;
    _index = index;
    ADChapter *ch = _book.chapters[index];
    NSURL *u = [[ADAPI shared] streamURLFor:ch];
    if (!u) { [self postError:@"这一章没有可用的音频地址"]; return; }
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    ADConfig *cfg = [ADConfig shared];
    // 若服务端要求 token 才能取音频，也带上
    NSString *authValue = nil;
    if (cfg.token.length) authValue = cfg.authScheme.length ? [NSString stringWithFormat:@"%@ %@", cfg.authScheme, cfg.token] : cfg.token;
    if (authValue && ![cfg.authHeader.lowercaseString isEqualToString:@"authorization"]) {
        // AVPlayer 不能加自定义头，改用 query 传递不可行时只能靠 URL 自身
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:u options:opts];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    if (!_player) _player = [AVPlayer playerWithPlayerItem:item];
    else [_player replaceCurrentItemWithPlayerItem:item];
    _player.automaticallyWaitsToMinimizeStalling = YES;
    [self attachObservers];

    double saved = [[ADStore shared] progressForChapter:ch.fid];
    if (saved > 3) {
        [_player seekToTime:CMTimeMakeWithSeconds(saved, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    [_player play];
    _player.rate = _rate > 0 ? _rate : 1.0f;
    [[ADStore shared] setLastChapter:ch.fid book:_book.bid];
    [self updateNowPlaying];
}

- (void)itemEnded:(NSNotification *)n {
    if (_index + 1 < (NSInteger)_book.chapters.count) [self next];
    else { [_player pause]; [self updateNowPlaying]; }
}

- (void)toggle {
    if (_player.rate > 0) [self pause]; else [self playIndex:_index];
}

- (void)pause {
    [_player pause];
    double sec = CMTimeGetSeconds(_player.currentTime);
    if (self.currentChapter.fid) [[ADStore shared] setProgress:sec forChapter:self.currentChapter.fid];
    if (_book.bid.length) [[ADAPI shared] reportProgress:_book.bid chapter:self.currentChapter.fid seconds:sec chapterProgress:0];
    [self updateNowPlaying];
}

- (void)next { if (_index + 1 < (NSInteger)_book.chapters.count) [self playIndex:_index + 1]; }
- (void)prev {
    double sec = CMTimeGetSeconds(_player.currentTime);
    if (sec > 5) { [self seekTo:0]; return; }
    if (_index > 0) [self playIndex:_index - 1];
}

- (void)seekTo:(double)sec {
    [_player seekToTime:CMTimeMakeWithSeconds(sec, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ADPlayerTick" object:nil];
}

- (void)seekBy:(double)delta {
    double sec = CMTimeGetSeconds(_player.currentTime) + delta;
    if (sec < 0) sec = 0;
    [self seekTo:sec];
}

- (void)setRate:(float)rate {
    _rate = rate;
    if (_player.rate > 0) _player.rate = rate;
    [[NSUserDefaults standardUserDefaults] setFloat:rate forKey:@"playRate"];
    [self updateNowPlaying];
}

- (void)setSleepTimerDeadline:(double)sleepTimerDeadline {
    _sleepTimerDeadline = sleepTimerDeadline;
    [_sleepTimer invalidate]; _sleepTimer = nil;
    if (sleepTimerDeadline <= 0) return;
    _sleepTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tickSleep) userInfo:nil repeats:YES];
}

- (void)tickSleep {
    if (_sleepTimerDeadline > 0 && [NSDate date].timeIntervalSince1970 >= _sleepTimerDeadline) {
        _sleepTimerDeadline = 0;
        [_sleepTimer invalidate]; _sleepTimer = nil;
        [_player pause];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ADSleepFired" object:nil];
    }
}

- (void)postError:(NSString *)msg {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ADPlayerError" object:nil userInfo:@{@"msg": msg}];
}

- (void)updateNowPlaying {
    ADChapter *ch = self.currentChapter;
    if (!ch) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = ch.title ?: @"";
    info[MPMediaItemPropertyArtist] = _book.title ?: @"";
    info[MPMediaItemPropertyAlbumTitle] = _book.author ?: @"";
    double dur = CMTimeGetSeconds(_player.currentItem.duration);
    if (dur > 0 && !isnan(dur)) { info[MPMediaItemPropertyPlaybackDuration] = @(dur); info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime)); }
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    [MPNowPlayingInfoCenter defaultCenter].playbackState = _player.rate > 0 ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
}

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *c = [MPRemoteCommandCenter sharedCommandCenter];
    [c.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] toggle]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] pause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] toggle]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] next]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] prev]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.skipForwardCommand setPreferredIntervals:@[@30]];
    [c.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] seekBy:30]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.skipBackwardCommand setPreferredIntervals:@[@15]];
    [c.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [[ADPlayer shared] seekBy:-15]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        MPChangePlaybackPositionCommandEvent *ev = (id)e;
        [[ADPlayer shared] seekTo:ev.positionTime]; return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)interrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeEnded) {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        [self updateNowPlaying];
    } else {
        [self pause];
    }
}

- (void)routeChanged:(NSNotification *)n {
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) [self pause];
}

@end
