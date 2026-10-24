#import "AD.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

// ───────────── 专辑详情 ─────────────
@interface ADAlbumController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel, *meta, *intro, *tip;
@property (nonatomic, strong) UIButton *fav;
@property (nonatomic, strong) NSMutableArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger page, total;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) UIButton *dlBtn;
@end

@implementation ADAlbumController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.title = @"专辑";
    self.tracks = [NSMutableArray array];
    self.page = 1;
    self.total = self.album.trackCount;

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
    self.table.refreshControl = [[UIRefreshControl alloc] init];
    self.table.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.table.refreshControl addTarget:self action:@selector(refreshAll) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.table];

    CGFloat w = self.view.bounds.size.width;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0)];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 110, 110)];
    self.cover.layer.cornerRadius = 10;
    self.cover.clipsToBounds = YES;
    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:17 color:UIColor.whiteColor];
    self.titleLabel.frame = CGRectMake(140, 16, w - 156, 46);
    self.meta = [ADUtil label:nil size:12 color:[ADUtil dim]];
    self.meta.frame = CGRectMake(140, 64, w - 156, 20);
    self.intro = [ADUtil label:nil size:12 color:[ADUtil dim]];
    self.intro.frame = CGRectMake(16, 170, w - 32, 0);
    self.dlBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dlBtn.frame = CGRectMake(140, 92, 130, 30);
    self.dlBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.dlBtn.layer.cornerRadius = 15;
    [self.dlBtn setTitle:@"缓存到本机" forState:UIControlStateNormal];
    [self.dlBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
    self.dlBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.dlBtn addTarget:self action:@selector(downloadAll) forControlEvents:UIControlEventTouchUpInside];
    [head addSubview:self.dlBtn];
    [head addSubview:self.cover];
    [head addSubview:self.titleLabel];
    [head addSubview:self.meta];
    [head addSubview:self.intro];
    self.table.tableHeaderView = head;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleFav)];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fillHeader) name:@"ADDownloadChanged" object:nil];
    [self fillHeader];
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] albumDetail:self.album.albumId done:^(ADAlbum *a, BOOL cached, NSString *err) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (a) {
            self.album.title = a.title.length ? a.title : self.album.title;
            self.album.cover = a.cover.length ? a.cover : self.album.cover;
            self.album.intro = a.intro.length ? a.intro : self.album.intro;
            self.album.anchor = a.anchor.length ? a.anchor : self.album.anchor;
            self.album.author = a.author.length ? a.author : self.album.author;
            self.album.provider = a.provider.length ? a.provider : self.album.provider;
            self.total = a.trackCount ?: self.total;
            [self fillHeader];
        }
        [self loadTracks];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = NO;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
}

- (void)fillHeader {
    [ADUtil cover:self.cover url:self.album.cover];
    self.titleLabel.text = self.album.title;
    NSMutableArray *bits = [NSMutableArray array];
    if (self.album.anchor.length) [bits addObject:self.album.anchor];
    if (self.total) [bits addObject:[NSString stringWithFormat:@"%ld 集", (long)self.total]];
    if (self.album.playCount > 0) [bits addObject:[NSString stringWithFormat:@"%@播放", [ADUtil count:self.album.playCount]]];
    [bits addObject:self.album.provider.length ? self.album.provider : @"xm"];
    self.meta.text = [bits componentsJoinedByString:@" · "];

    CGFloat w = self.view.bounds.size.width;
    self.intro.text = self.album.intro.length > 200 ? [[self.album.intro substringToIndex:200] stringByAppendingString:@"…"] : self.album.intro;
    CGSize sz = [self.intro sizeThatFits:CGSizeMake(w - 32, 400)];
    self.intro.frame = CGRectMake(16, 170, w - 32, sz.height);
    UIView *head = self.table.tableHeaderView;
    CGFloat h = 170 + sz.height + 12;
    head.frame = CGRectMake(0, 0, w, h);
    self.table.tableHeaderView = head;

    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (task) {
        NSString *t2 = task.state == ADTaskStateDone ? @"已缓存"
                    : (task.state == ADTaskStatePaused ? [NSString stringWithFormat:@"已暂停 %ld/%ld", (long)task.done, (long)task.tracks.count]
                    : [NSString stringWithFormat:@"缓存中 %ld/%ld", (long)task.done, (long)task.tracks.count]);
        [self.dlBtn setTitle:t2 forState:UIControlStateNormal];
    } else {
        [self.dlBtn setTitle:@"缓存到本机" forState:UIControlStateNormal];
    }
    BOOL fav = [[ADStore shared] isFavorite:self.album.albumId];
    [self.navigationItem.rightBarButtonItem setImage:[UIImage systemImageNamed:fav ? @"heart.fill" : @"heart"]];
    self.navigationItem.rightBarButtonItem.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
}

- (void)refreshAll {
    self.page = 1;
    [self.tracks removeAllObjects];
    [self.table reloadData];
    [self loadTracks];
    [self.table.refreshControl endRefreshing];
}

- (void)downloadAll {
    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (task && task.state == ADTaskStateRunning) { [[ADDownloader shared] pauseTask:task]; [self fillHeader]; return; }
    if (task && task.state == ADTaskStatePaused) { [[ADDownloader shared] resumeTask:task]; [self fillHeader]; return; }
    if (!self.tracks.count) return;
    [[ADDownloader shared] addAlbum:self.album tracks:self.tracks];
    [self fillHeader];
}

- (void)toggleFav {
    [[ADStore shared] toggleFavorite:self.album];
    [self fillHeader];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

- (void)loadTracks {
    if (self.loading) return;
    self.loading = YES;
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] tracksOf:self.album.albumId page:self.page done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.loading = NO;
        if (err) { self.title = err; return; }
        if (total > 0) self.total = total;
        if (list.count) [self.tracks addObjectsFromArray:list];
        if (list.count) self.page += 1;
        [self.table reloadData];
        [self fillHeader];
        // 自动恢复上次进度
        if (self.tracks.count && !ADPlayer.shared.album) {
            ADPlayer.shared.album = self.album;
            ADPlayer.shared.tracks = self.tracks;
        }
    }];
}

- (void)playFrom:(NSInteger)index {
    ADPlayer *p = ADPlayer.shared;
    [p playAlbum:self.album tracks:self.tracks at:index];
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return self.tracks.count ? [NSString stringWithFormat:@"共 %ld 集", (long)MAX(self.total, (NSInteger)self.tracks.count)] : @"";
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)v;
    h.textLabel.textColor = [ADUtil dim];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"tr";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    ADTrack *tr = self.tracks[ip.row];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [ADUtil dim];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.textLabel.text = tr.title;
    double pos = [[ADStore shared] positionFor:tr.trackId];
    if ([[ADDownloader shared] hasLocal:tr.trackId]) {
        c.detailTextLabel.text = @"已缓存 · 离线可听";
        c.detailTextLabel.textColor = [ADUtil brand];
    } else
    c.detailTextLabel.text = pos > 0
        ? [NSString stringWithFormat:@"听到 %@ / %@", [ADUtil time:pos], [ADUtil time:tr.duration]]
        : (tr.duration > 0 ? [ADUtil time:tr.duration] : @"");
    ADTrack *cur = ADPlayer.shared.current;
    BOOL playing = cur && [cur.trackId isEqualToString:tr.trackId];
    c.textLabel.textColor = playing ? [ADUtil brand] : UIColor.whiteColor;
    // 触底加载
    if (ip.row == (NSInteger)self.tracks.count - 3 && self.tracks.count < self.total) [self loadTracks];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    [self playFrom:ip.row];
}
@end

// ───────────── 播放器 ─────────────
@interface ADPlayerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *mid, *duration, *status;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *playBtn, *starBtn, *moreBtn;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) UITableView *queue;
@property (nonatomic, assign) BOOL showQueue;
@end

@implementation ADPlayerController

- (instancetype)init {
    if ((self = [super init])) {
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
        } else {
            self.modalPresentationStyle = UIModalPresentationFullScreen;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.16 green:0.15 blue:0.15 alpha:1];

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 28;
        }
    }

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    bg.frame = self.view.bounds;
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bg];

    self.cover = [UIImageView new];
    self.cover.layer.cornerRadius = 20;
    self.cover.clipsToBounds = YES;
    self.cover.contentMode = UIViewContentModeScaleAspectFill;
    self.cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:26 color:UIColor.whiteColor];
    self.titleLabel.numberOfLines = 2;
    self.subLabel = [ADUtil label:nil size:17 color:[UIColor colorWithWhite:1 alpha:0.62]];

    self.starBtn = [self circleButton:@"star" action:@selector(toggleFav)];
    self.moreBtn = [self circleButton:@"ellipsis" action:@selector(showMore)];
    UIButton *more = self.moreBtn;

    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.95];
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    [self.slider setThumbImage:[self dot:16] forState:UIControlStateNormal];
    [self.slider addTarget:self action:@selector(sliderBegin) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(sliderMoving) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    self.elapsed = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.75]];
    self.mid = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.55]];
    self.duration = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.55]];
    self.status = [ADUtil label:nil size:12 color:[ADUtil brand]];
    self.status.textAlignment = NSTextAlignmentCenter;

    self.playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playBtn.tintColor = UIColor.whiteColor;
    [self.playBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[self.cover, self.titleLabel, self.subLabel, self.starBtn, more, self.slider,
                        self.elapsed, self.mid, self.duration, self.status, self.playBtn]) {
        [self.view addSubview:v];
    }

    // 控制行
    UIButton *prev = [self iconButton:@"backward.end.fill" size:26 action:@selector(prev)];
    UIButton *back = [self iconButton:@"gobackward.15" size:30 action:@selector(back15)];
    UIButton *fwd = [self iconButton:@"goforward.15" size:30 action:@selector(fwd15)];
    UIButton *next = [self iconButton:@"forward.end.fill" size:26 action:@selector(next)];
    prev.tag = 201; back.tag = 202; fwd.tag = 203; next.tag = 204;
    for (UIButton *b in @[prev, back, fwd, next]) [self.view addSubview:b];

    // 底部工具行
    UIButton *rate = [self textButton:@"1.0x" action:@selector(cycleRate)];
    UIButton *sleep = [self iconButton:@"moon.zzz.fill" size:22 action:@selector(cycleSleep)];
    UIButton *air = [self iconButton:@"airplayaudio" size:24 action:@selector(airplay)];
    UIButton *list = [self iconButton:@"list.bullet" size:22 action:@selector(openQueue)];
    rate.tag = 301; sleep.tag = 302; air.tag = 303; list.tag = 304;
    for (UIButton *b in @[rate, sleep, air, list]) [self.view addSubview:b];

    self.queue = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.queue.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    self.queue.dataSource = self;
    self.queue.delegate = self;
    self.queue.hidden = YES;
    self.queue.layer.cornerRadius = 18;
    self.queue.clipsToBounds = YES;
    [self.view addSubview:self.queue];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerChanged" object:nil];
    [self sync];
}

- (UIImage *)dot:(CGFloat)d {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.whiteColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
    }];
}

- (UIButton *)circleButton:(NSString *)icon action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    b.layer.cornerRadius = 22;
    b.tintColor = UIColor.whiteColor;
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)iconButton:(NSString *)icon size:(CGFloat)size action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)textButton:(NSString *)text action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    // 各块固定高度：标题 70 / 进度 28 / 时间 30 / 控制 80 / 底部 40
    CGFloat top = safeTop + 8;
    CGFloat bottomPad = safeBottom + 14;
    CGFloat blockH = 70 + 28 + 30 + 80 + 40;
    CGFloat coverMax = MIN(W - 48, H * 0.46);
    CGFloat leftover = H - top - bottomPad - blockH - coverMax;
    CGFloat coverH = coverMax;
    if (leftover < 0) { coverH = MAX(140, coverMax + leftover); leftover = 0; }
    CGFloat gap = MAX(10, leftover / 5.0);

    CGFloat y = top;
    self.cover.frame = CGRectMake((W - coverH) / 2, y, coverH, coverH);
    y = CGRectGetMaxY(self.cover.frame) + gap;

    self.titleLabel.frame = CGRectMake(24, y, W - 24 - 130, 34);
    self.subLabel.frame = CGRectMake(24, y + 38, W - 24 - 130, 24);
    self.starBtn.frame = CGRectMake(W - 24 - 96, y - 4, 44, 44);
    self.moreBtn.frame = CGRectMake(W - 24 - 44, y - 4, 44, 44);
    self.status.frame = CGRectMake(24, y + 64, W - 48, 14);
    y += 70 + gap;

    self.slider.frame = CGRectMake(24, y + 4, W - 48, 28);
    y += 28 + gap;

    self.elapsed.frame = CGRectMake(24, y, 90, 18);
    self.mid.frame = CGRectMake(W / 2 - 60, y, 120, 18);
    self.mid.textAlignment = NSTextAlignmentCenter;
    self.duration.frame = CGRectMake(W - 114, y, 90, 18);
    self.duration.textAlignment = NSTextAlignmentRight;
    y += 30 + gap;

    self.playBtn.frame = CGRectMake(W / 2 - 40, y, 80, 80);
    [self.view viewWithTag:201].frame = CGRectMake(24, y + 16, 40, 44);
    [self.view viewWithTag:202].frame = CGRectMake(W / 2 - 118, y + 12, 44, 48);
    [self.view viewWithTag:203].frame = CGRectMake(W / 2 + 74, y + 12, 44, 48);
    [self.view viewWithTag:204].frame = CGRectMake(W - 64, y + 16, 40, 44);
    y += 80 + gap;

    UIButton *rate = (UIButton *)[self.view viewWithTag:301];
    rate.frame = CGRectMake(W / 2 - 150, y + 2, 58, 36);
    [self.view viewWithTag:302].frame = CGRectMake(W / 2 - 62, y + 2, 44, 36);
    [self.view viewWithTag:303].frame = CGRectMake(W / 2 + 18, y + 2, 44, 36);
    [self.view viewWithTag:304].frame = CGRectMake(W / 2 + 106, y + 2, 44, 36);

    if (self.showQueue) {
        self.queue.frame = CGRectMake(16, H - 320, W - 32, 300);
    } else {
        self.queue.frame = CGRectMake(16, H, W - 32, 300);
    }
}

- (void)sync {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t) return;
    self.titleLabel.text = t.title;
    self.subLabel.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    self.status.text = p.statusText ?: @"";
    [ADUtil cover:self.cover url:p.album.cover];

    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    if (!self.dragging && dur > 0 && !isnan(dur)) {
        self.slider.maximumValue = dur;
        self.slider.value = cur;
    }
    self.elapsed.text = [ADUtil time:cur];
    self.duration.text = (dur > 0 && !isnan(dur)) ? [NSString stringWithFormat:@"-%@", [ADUtil time:dur - cur]] : @"--:--";

    // 中间：码率 / 状态
    NSString *mid = nil;
    if ([[ADDownloader shared] hasLocal:t.trackId]) mid = @"本地缓存";
    if (!mid && p.player.currentItem) {
        AVPlayerItemAccessLog *log = p.player.currentItem.accessLog;
        AVPlayerItemAccessLogEvent *ev = log.events.lastObject;
        if (ev.observedBitrate > 0) mid = [NSString stringWithFormat:@"%.0f kbps", ev.observedBitrate / 1000.0];
    }
    self.mid.text = mid ?: @"在线播放";

    [self.playBtn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill")
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium]]
                   forState:UIControlStateNormal];
    UIButton *rateBtn = (UIButton *)[self.view viewWithTag:301];
    [rateBtn setTitle:[NSString stringWithFormat:@"%.2gx", p.rate] forState:UIControlStateNormal];
    UIButton *sleepBtn = (UIButton *)[self.view viewWithTag:302];
    if (p.sleepDeadline > 0) {
        double left = p.sleepDeadline - [NSDate date].timeIntervalSince1970;
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = [NSString stringWithFormat:@"%@ · %@后停", self.mid.text ?: @"", [ADUtil time:left]];
    } else {
        sleepBtn.tintColor = UIColor.whiteColor;
    }
    BOOL fav = [[ADStore shared] isFavorite:p.album.albumId];
    [self.starBtn setImage:[UIImage systemImageNamed:(fav ? @"star.fill" : @"star") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    self.starBtn.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    if (self.showQueue) [self.queue reloadData];
}

- (void)toggleFav {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    [[ADStore shared] toggleFavorite:p.album];
    [self sync];
}

- (void)showMore {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:p.album.title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"从头播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [p playAt:0];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"缓存整本到本机" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADDownloader shared] addAlbum:p.album tracks:p.tracks];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)airplay {
    MPVolumeView *vv = [MPVolumeView new];
    vv.showsVolumeSlider = NO;
    vv.frame = CGRectMake(-1000, -1000, 1, 1);
    [self.view addSubview:vv];
    for (UIView *v in vv.subviews) {
        if ([v isKindOfClass:UIButton.class]) { [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside]; break; }
    }
}

- (void)sliderBegin { self.dragging = YES; }
- (void)sliderMoving { self.elapsed.text = [ADUtil time:self.slider.value]; }
- (void)sliderEnd { self.dragging = NO; [ADPlayer.shared seekTo:self.slider.value]; }
- (void)toggle { [ADPlayer.shared toggle]; [self sync]; }
- (void)prev { [ADPlayer.shared prev]; [self sync]; }
- (void)next { [ADPlayer.shared next]; [self sync]; }
- (void)back15 { [ADPlayer.shared seekBy:-15]; }
- (void)fwd15 { [ADPlayer.shared seekBy:15]; }

- (void)cycleRate {
    NSArray *rates = @[@0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    float cur = ADPlayer.shared.rate;
    NSUInteger idx = 0;
    for (NSUInteger i = 0; i < rates.count; i++) if (fabs([rates[i] floatValue] - cur) < 0.001) { idx = i; break; }
    idx = (idx + 1) % rates.count;
    ADPlayer.shared.rate = [rates[idx] floatValue];
    [self sync];
}

- (void)cycleSleep {
    NSArray *mins = @[@0, @15, @30, @45, @60, @90];
    double now = [NSDate date].timeIntervalSince1970;
    double left = ADPlayer.shared.sleepDeadline > 0 ? (ADPlayer.shared.sleepDeadline - now) / 60.0 : 0;
    NSInteger idx = 0;
    for (NSUInteger i = 0; i < mins.count; i++) if (fabs([mins[i] doubleValue] - left) < 1.5) { idx = i; break; }
    idx = (idx + 1) % mins.count;
    double m = [mins[idx] doubleValue];
    ADPlayer.shared.sleepDeadline = m > 0 ? now + m * 60 : 0;
    [self sync];
}

- (void)openQueue {
    self.showQueue = !self.showQueue;
    self.queue.hidden = !self.showQueue;
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        self.queue.frame = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
    }];
    [self.queue reloadData];
    if (self.showQueue) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:ADPlayer.shared.index inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
            [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return ADPlayer.shared.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"q";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    ADTrack *tr = ADPlayer.shared.tracks[ip.row];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    c.textLabel.text = tr.title;
    c.textLabel.textColor = (ip.row == ADPlayer.shared.index) ? [ADUtil brand] : UIColor.whiteColor;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [ADPlayer.shared playAt:ip.row];
    [self openQueue];
    [self sync];
}
@end

// ───────────── 设置 ─────────────
@interface ADSettingsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL tokenShown;
@end

@implementation ADSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.075 green:0.075 blue:0.082 alpha:1];
    self.title = @"设置";
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.token = [ADConfig shared].token ?: @"";

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    self.baseField = [self field:[ADConfig shared].baseURL placeholder:@"https://服务器地址:端口" keyboard:UIKeyboardTypeURL];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    self.status = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADDownloadChanged" object:nil];
}

- (void)refresh { [self.table reloadData]; }

- (UITextField *)field:(NSString *)text placeholder:(NSString *)ph keyboard:(UIKeyboardType)kb {
    UITextField *f = [UITextField new];
    f.text = text;
    f.placeholder = ph;
    f.textColor = UIColor.whiteColor;
    f.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.keyboardType = kb;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.textAlignment = NSTextAlignmentRight;
    f.delegate = self;
    return f;
}

// token 显示：默认只露出前后各 3 位，其余用圆点
- (NSString *)tokenDisplay {
    if (!self.token.length) return @"未填写";
    if (self.tokenShown) return self.token;
    if (self.token.length <= 10) return @"••••••••";
    return [NSString stringWithFormat:@"%@••••••%@", [self.token substringToIndex:5], [self.token substringFromIndex:self.token.length - 4]];
}

- (void)toggleToken {
    self.tokenShown = !self.tokenShown;
    [self.table reloadData];
}

- (void)editToken {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Token" message:@"粘贴服务端给你的 token" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.token;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        tf.placeholder = @"xmd_…";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.token = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [self save];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"从剪贴板粘贴" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *p = UIPasteboard.generalPasteboard.string;
        if (p.length) { self.token = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; [self save]; }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)save {
    [ADConfig shared].baseURL = self.baseField.text ?: @"";
    [ADConfig shared].token = self.token ?: @"";
    [[ADConfig shared] save];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    [self.table reloadData];
    [self test];
}

- (void)test {
    self.status.text = @"正在测试连接…";
    [self.table reloadData];
    __weak typeof(self) w = self;
    [[ADApi shared] albumDetail:@"XMID59325711" done:^(ADAlbum *a, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.status.text = err ? [@"连接失败：" stringByAppendingString:err] : @"连接正常，可以搜索和播放";
        [self.table reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"服务" : @"本机下载";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return self.status.text ?: @"点 Token 那一行可以粘贴或修改";
    if (![ADDownloader shared].tasks.count)
        return @"在专辑页点「缓存到本机」，音频会存进手机，离线也能听";
    return @"左滑删除或暂停，点击行可暂停/继续；本机下载不占用服务器";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 3;
    return MAX(1, (NSInteger)[ADDownloader shared].tasks.count) + 1;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.selectionStyle = UITableViewCellSelectionStyleNone;

    if (ip.section == 0) {
        if (ip.row == 0) {
            UILabel *name = [ADUtil label:nil size:15 color:UIColor.whiteColor];
            name.text = @"服务地址";
            name.frame = CGRectMake(16, 12, 76, 20);
            [c.contentView addSubview:name];
            CGFloat cw = c.contentView.bounds.size.width > 0 ? c.contentView.bounds.size.width : (t.bounds.size.width - 40);
            self.baseField.frame = CGRectMake(86, 6, MAX(80, cw - 86 - 34), 32);
            self.baseField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [c.contentView addSubview:self.baseField];
        } else if (ip.row == 1) {
            UILabel *name = [ADUtil label:nil size:15 color:UIColor.whiteColor];
            name.text = @"Token";
            name.frame = CGRectMake(16, 12, 60, 20);
            [c.contentView addSubview:name];

            UILabel *v = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.85]];
            v.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            v.textAlignment = NSTextAlignmentRight;
            v.lineBreakMode = NSLineBreakByTruncatingMiddle;
            v.text = [self tokenDisplay];
            v.frame = CGRectMake(80, 0, c.contentView.bounds.size.width - 80 - 44, 44);
            v.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [c.contentView addSubview:v];

            UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
            eye.frame = CGRectMake(c.contentView.bounds.size.width - 40, 2, 34, 40);
            eye.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            eye.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
            [eye setImage:[UIImage systemImageNamed:self.tokenShown ? @"eye" : @"eye.slash"] forState:UIControlStateNormal];
            [eye addTarget:self action:@selector(toggleToken) forControlEvents:UIControlEventTouchUpInside];
            [c.contentView addSubview:eye];
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            c.textLabel.text = @"测试连接";
            c.textLabel.textColor = [ADUtil brand];
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return c;
    }

    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.row == 0) {
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        c.textLabel.text = anyRunning ? @"全部暂停" : @"全部继续";
        c.textLabel.textColor = [ADUtil brand];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (!tasks.count) {
        c.textLabel.text = @"暂无本机下载";
        c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    } else {
        ADTask *task = tasks[ip.row - 1];
        c.textLabel.text = task.title.length ? task.title : task.albumId;
        NSString *st = task.state == ADTaskStateRunning ? @"下载中"
                     : (task.state == ADTaskStatePaused ? @"已暂停"
                     : (task.state == ADTaskStateDone ? @"已完成"
                     : (task.state == ADTaskStateFailed ? @"有失败" : @"排队中")));
        NSString *bytes = task.bytes > 0 ? [NSString stringWithFormat:@" · %.1fMB", task.bytes / 1048576.0] : @"";
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld/%ld%@", st, (long)task.done, (long)task.tracks.count, bytes];
    }
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        if (ip.row == 0) [self.baseField becomeFirstResponder];
        else if (ip.row == 1) [self editToken];
        else [self save];
        return;
    }
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.row == 0) {
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        if (anyRunning) [[ADDownloader shared] pauseAll]; else [[ADDownloader shared] resumeAll];
        [t reloadData];
        return;
    }
    if (tasks.count) {
        ADTask *task = tasks[ip.row - 1];
        if (task.state == ADTaskStateRunning || task.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:task];
        else [[ADDownloader shared] resumeTask:task];
        [t reloadData];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1 || ip.row == 0) return nil;
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if ((NSInteger)ip.row - 1 >= (NSInteger)tasks.count) return nil;
    ADTask *task = tasks[ip.row - 1];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        UIAlertController *q = [UIAlertController alertControllerWithTitle:@"删除下载" message:@"音频文件会一起删掉" preferredStyle:UIAlertControllerStyleAlert];
        [q addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
        [q addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [[ADDownloader shared] deleteTask:task];
            [t reloadData];
            done(YES);
        }]];
        [self presentViewController:q animated:YES completion:nil];
    }];
    UIContextualAction *pause = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:(task.state == ADTaskStateRunning ? @"暂停" : @"继续") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        if (task.state == ADTaskStateRunning || task.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:task];
        else [[ADDownloader shared] resumeTask:task];
        [t reloadData];
        done(YES);
    }];
    pause.backgroundColor = [ADUtil brand];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, pause]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self save]; return YES; }
@end
