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
// 正在异步取音频地址：此时 _album 已经切到新书，但 _player 里可能还是旧书的声音。
// 这段空窗里 toggle 不能去暂停/恢复旧音频，pause 要顺手作废在飞的请求。
@property (nonatomic, assign) BOOL resolving;
// 切换书目的序号：连点 A 又点 C 时，A 的目录载入结果按此作废，免得把队列覆盖回去。
@property (nonatomic, assign) NSInteger openSeq;
@property (nonatomic, assign) CFTimeInterval resolveT;   // 进入 resolving 的时刻,兜底用
@property (nonatomic, assign) BOOL retriedItem;
// 播放队列补全：专辑页只加载了前几十集时，播放器自己把后面的目录补齐，
// 否则队列的「倒序」「快速选集」「缓存整本」都只能看到前 50 集。
@property (nonatomic, assign) BOOL filling;
// 锁屏/控制中心封面:按封面地址缓存一份 MPMediaItemArtwork,换书时才重新取
@property (nonatomic, strong) MPMediaItemArtwork *artwork;
@property (nonatomic, copy) NSString *artworkURL, *artworkLoading;
- (void)ensureFullQueue;
- (void)loadPagesOf:(NSString *)albumId upTo:(NSInteger)lastPage page:(NSInteger)page acc:(NSMutableArray *)acc tries:(NSInteger)tries done:(void (^)(NSArray *list))done;
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
    self.openSeq += 1;                         // 作废还在载入目录的 openAlbum
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


// ── 打开某本书并定位到某集（书签 / 启动恢复用）────────────
- (void)loadPagesOf:(NSString *)albumId upTo:(NSInteger)lastPage page:(NSInteger)page acc:(NSMutableArray *)acc tries:(NSInteger)tries done:(void (^)(NSArray *list))done {
    __block BOOL fired = NO;
    __weak typeof(self) w = self;
    [[ADApi shared] tracksOf:albumId page:page done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self || fired) return;
        if (err.length && !list.count) {
            if (cached) return;
            fired = YES;
            if (tries < 2) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [w loadPagesOf:albumId upTo:lastPage page:page acc:acc tries:tries + 1 done:done];
                });
            } else done(acc.count ? acc : nil);
            return;
        }
        if (!list.count) { if (cached) return; fired = YES; done(acc.count ? acc : nil); return; }
        fired = YES;
        [acc addObjectsFromArray:list];
        if (page >= lastPage || list.count < 50) done(acc);
        else [self loadPagesOf:albumId upTo:lastPage page:page + 1 acc:acc tries:0 done:done];
    }];
}

- (void)openAlbum:(ADAlbum *)album trackId:(NSString *)trackId index:(NSInteger)index seconds:(double)sec autoPlay:(BOOL)play {
    if (!album.albumId.length) return;
    // 已经在这本书的队列里：直接跳
    if (_album && [_album.albumId isEqualToString:album.albumId] && _tracks.count) {
        for (NSInteger i = 0; i < (NSInteger)_tracks.count; i++) {
            if ([_tracks[i].trackId isEqualToString:trackId]) {
                if (play) { if (trackId) [[ADStore shared] setPosition:sec for:trackId]; [self playAt:i]; }
                return;
            }
        }
    }
    // 要载入目录才能定位：切到别的书时先把旧书静音，别让它在加载期间继续出声
    if (play && (!_album || ![_album.albumId isEqualToString:album.albumId])) {
        [_player pause];
        self.resolveSeq += 1;                  // 作废在飞的取地址请求
        self.resolving = YES; self.resolveT = CACurrentMediaTime();
    }
    // 用户连点 A 又点 C：给这次载入发个号，回来时不是最新的就丢掉
    self.openSeq += 1;
    NSInteger myOpen = self.openSeq;
    NSInteger lastPage = MAX(0, index) / 50 + 1;
    self.statusText = play ? @"正在载入书签位置…" : nil;
    if (play) [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    __weak typeof(self) w = self;
    [self loadPagesOf:album.albumId upTo:lastPage page:1 acc:[NSMutableArray array] tries:0 done:^(NSArray *list) {
        __strong typeof(w) self = w; if (!self) return;
        if (myOpen != self.openSeq) return;    // 过期的载入结果，丢弃
        if (!list.count) { self.statusText = @"目录载入失败"; self.resolving = NO; [ADHaptic warning]; [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil]; return; }
        NSMutableArray *uniq = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set];
        for (ADTrack *t in list) { if (t.trackId.length && ![seen containsObject:t.trackId]) { [seen addObject:t.trackId]; [uniq addObject:t]; } }
        NSInteger pos = -1;
        for (NSInteger i = 0; i < (NSInteger)uniq.count; i++) if ([[uniq[i] trackId] isEqualToString:trackId]) { pos = i; break; }
        if (pos < 0) pos = MIN(MAX(0, index), (NSInteger)uniq.count - 1);
        self.album = album;
        self.tracks = uniq;
        self.index = pos;
        self.statusText = nil;
        if (trackId.length && sec > 0) [[ADStore shared] setPosition:sec for:trackId];
        [[ADStore shared] setLastTrack:[uniq[pos] trackId] album:album.albumId];
        if (play) { [[ADStore shared] touchHistory:album]; [self playAt:pos]; }
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
        [self ensureFullQueue];
    }];
}

- (void)restoreLast {
    if (self.album || self.tracks.count) return;
    ADAlbum *a = [ADStore shared].history.firstObject;
    if (!a) return;
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    NSString *tid = info[@"trackId"] ?: [[ADStore shared] lastTrackOf:a.albumId];
    if (!tid.length) return;
    NSInteger idx = [info[@"index"] integerValue];
    [self openAlbum:a trackId:tid index:idx seconds:[info[@"seconds"] doubleValue] autoPlay:NO];
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
    self.openSeq += 1;                         // 新的播放请求:作废还在载入目录的 openAlbum
    // 先掐掉旧音频：取地址要几秒，这段时间里不能让上一本的声音继续放。
    // 清掉 currentItem 之后 toggle 会走 playAt 重来，而不是去暂停一段已经过期的音频。
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    self.resolving = YES; self.resolveT = CACurrentMediaTime();
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

// 预缓存文件：读时兼容各种扩展名，写时按文件头决定
- (NSString *)prefetchPath:(NSString *)trackId {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *e in @[@"mp3", @"m4a", @"aac", @"flac", @"ogg", @"wav"]) {
        NSString *p = [[self prefetchDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", trackId, e]];
        if ([fm fileExistsAtPath:p]) {
            // 旧版本误存成 .m4a 的 MP3：顺手改名
            if ([e isEqualToString:@"m4a"]) {
                NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:p]; NSData *d = [h readDataOfLength:16]; [h closeFile];
                NSString *real = [ADDownloader extForData:d];
                if (real.length && ![real isEqualToString:@"m4a"]) {
                    NSString *np = [[p stringByDeletingPathExtension] stringByAppendingPathExtension:real];
                    [fm removeItemAtPath:np error:nil];
                    if ([fm moveItemAtPath:p toPath:np error:nil]) return np;
                }
            }
            return p;
        }
    }
    return [[self prefetchDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp3", trackId]];
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
                if (data.length > 40000) {
                    NSString *ext = [ADDownloader extForData:[data subdataWithRange:NSMakeRange(0, 16)]] ?: @"mp3";
                    [data writeToFile:[[self prefetchDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", t.trackId, ext]] atomically:YES];
                }
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
            self.resolving = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
            return;
        }
        if ([err isEqualToString:@"WAIT"]) {
            // 番茄源需要先下载，轮询到就绪
            if (attempt > 40) {
                self.statusText = @"音频还在准备，稍后会自动开始";
                self.resolving = NO;
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
    self.resolving = NO;                       // 地址已经拿到，空窗结束
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
    if (!u) { self.statusText = @"音频地址无效"; self.resolving = NO; return; }
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
        [self refreshNowPlayingIfNeeded];
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
    if (n.object && n.object != _player.currentItem) return;   // 旧集迟到的失败通知,忽略
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
    if (n.object && n.object != _player.currentItem) return;   // 旧集迟到的结束通知,忽略
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
    NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:@"ad_playmode"];   // 0 顺序 1 单集循环 2 整本循环
    if (mode == 1) { [self seekTo:0]; [_player play]; _player.rate = _rate; return; }
    if (_index + 1 < (NSInteger)_tracks.count) [self next];
    else if (mode == 2 && _tracks.count) [self playAt:0];
    else { [_player pause]; [self nowPlaying]; }
}

- (void)toggle {
    // 播放器还没有音频项（刚切书 / 上一个 item 已被清掉）：直接重新开这一集
    if (!_player || _player.currentItem == nil) { if (_tracks.count) [self playAt:_index]; return; }
    // 地址还在取：此时 currentItem 还是旧书的音频，不能拿它来暂停/恢复
    if (self.resolving) {
        // 兜底:取地址空窗超过 20 秒仍没复位,说明链路断了,直接重开这一集
        if (CACurrentMediaTime() - self.resolveT > 20 && _tracks.count) [self playAt:_index];
        return;
    }
    if (_player.rate > 0) [self pause];
    else { [_player play]; _player.rate = _rate; [self nowPlaying]; if (_album) [[ADStore shared] touchHistory:_album]; }
}
- (void)pause {
    if (self.resolving) {
        // 取消在飞的取地址，别等它回来又把声音放出来
        self.resolveSeq += 1;
        self.openSeq += 1;                     // 目录还在载入时按暂停:载入完成后也不要自动开播
        self.resolving = NO;
        self.statusText = nil;
        [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
    }
    [_player pause];
    [self nowPlaying];
}
- (void)next { if (_index + 1 < (NSInteger)_tracks.count) [self playAt:_index + 1]; }
- (void)prev {
    double sec = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    if (sec > 5) { [self seekTo:0]; return; }
    if (_index > 0) [self playAt:_index - 1];
}
- (void)seekTo:(double)sec {
    if (!_player) return;
    __weak typeof(self) w2 = self;
    [_player seekToTime:CMTimeMakeWithSeconds(MAX(0, sec), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL f) {
        dispatch_async(dispatch_get_main_queue(), ^{ [w2 nowPlaying]; });
    }];
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
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @1.0;
    NSString *cv = [self coverURL];
    BOOL haveArt = (self.artwork && [self.artworkURL isEqualToString:cv]);
    if (haveArt) info[MPMediaItemPropertyArtwork] = self.artwork;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    MPNowPlayingInfoCenter.defaultCenter.playbackState = (_player.rate > 0) ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
    if (!haveArt) [self loadArtwork:cv];     // 必须放在写入之后:缓存命中会同步回调并合并封面
}

// 当前书的封面地址;书对象里没有时,从收藏/历史/想听/下载任务里找同一本书
- (NSString *)coverURL {
    if (_album.cover.length) return _album.cover;
    NSString *aid = _album.albumId;
    if (!aid.length) return @"";
    ADStore *st = [ADStore shared];
    for (NSArray *list in @[st.history, st.favorites, st.wants])
        for (ADAlbum *a in list) if ([a.albumId isEqualToString:aid] && a.cover.length) { _album.cover = a.cover; return a.cover; }
    ADTask *t = [[ADDownloader shared] taskForAlbum:aid];
    if (t.cover.length) { _album.cover = t.cover; return t.cover; }
    return @"";
}

// 锁屏信息缺时长或缺封面时补写;平时每 10 秒校准一次已播时间
- (void)refreshNowPlayingIfNeeded {
    NSDictionary *cur = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    double dur = _player.currentItem ? CMTimeGetSeconds(_player.currentItem.duration) : 0;
    BOOL durReady = (dur > 0 && !isnan(dur));
    BOOL missDur = durReady && !cur[MPMediaItemPropertyPlaybackDuration];
    BOOL missArt = self.artwork && [self.artworkURL isEqualToString:[self coverURL]] && !cur[MPMediaItemPropertyArtwork];
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (missDur || missArt || !cur.count || now - last > 10) { last = now; [self nowPlaying]; }
}

- (void)loadArtwork:(NSString *)url {
    if (!url.length || [self.artworkLoading isEqualToString:url]) return;
    self.artworkLoading = url;
    __weak typeof(self) w = self;
    [ADUtil coverImage:url done:^(UIImage *img) {
        __strong typeof(w) self = w; if (!self) return;
        self.artworkLoading = nil;
        if (!img || ![url isEqualToString:[self coverURL]]) return;
        // 统一成正方形,锁屏里显示更饱满
        CGFloat side = MIN(img.size.width, img.size.height);
        CGFloat out = MIN(side, 600);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(out, out)];
        UIImage *sq = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGFloat s = out / side;
            [img drawInRect:CGRectMake(-(img.size.width - side) / 2 * s, -(img.size.height - side) / 2 * s, img.size.width * s, img.size.height * s)];
        }];
        self.artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:sq.size requestHandler:^UIImage *(CGSize size) { return sq; }];
        self.artworkURL = url;
        NSMutableDictionary *info = [MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo mutableCopy];
        if (!info.count) { [self nowPlaying]; return; }
        info[MPMediaItemPropertyArtwork] = self.artwork;
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    }];
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
