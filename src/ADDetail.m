#import "AD.h"
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
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *duration, *status;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *playBtn, *rateBtn, *sleepBtn;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) UITableView *queue;
@property (nonatomic, assign) BOOL showQueue;
@end

@implementation ADPlayerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.04 blue:0.03 alpha:1];
    CGFloat w = self.view.bounds.size.width;

    self.cover = [[UIImageView alloc] initWithFrame:CGRectMake(w / 2 - 115, 80, 230, 230)];
    self.cover.layer.cornerRadius = 16;
    self.cover.clipsToBounds = YES;
    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:18 color:UIColor.whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.subLabel = [ADUtil label:nil size:13 color:[ADUtil dim]];
    self.subLabel.textAlignment = NSTextAlignmentCenter;
    self.status = [ADUtil label:nil size:12 color:[ADUtil brand]];
    self.status.textAlignment = NSTextAlignmentCenter;

    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = [ADUtil brand];
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.18];
    [self.slider addTarget:self action:@selector(sliderBegin) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(sliderMoving) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    self.elapsed = [ADUtil label:nil size:11 color:[ADUtil dim]];
    self.duration = [ADUtil label:nil size:11 color:[ADUtil dim]];
    self.duration.textAlignment = NSTextAlignmentRight;

    self.playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playBtn.tintColor = UIColor.whiteColor;
    [self.playBtn setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:62 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [self.playBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    UIButton *prev = [self icon:@"backward.end.fill" size:30 action:@selector(prev)];
    UIButton *next = [self icon:@"forward.end.fill" size:30 action:@selector(next)];
    UIButton *back = [self icon:@"gobackward.15" size:24 action:@selector(back15)];
    UIButton *fwd = [self icon:@"goforward.30" size:24 action:@selector(fwd30)];

    self.rateBtn = [self pill:@"1.0x" action:@selector(cycleRate)];
    self.sleepBtn = [self pill:@"定时" action:@selector(cycleSleep)];
    UIButton *close = [self icon:@"chevron.down" size:20 action:@selector(closeMe)];
    UIButton *list = [self icon:@"list.bullet" size:20 action:@selector(openQueue)];

    NSArray *all = @[self.cover, self.titleLabel, self.subLabel, self.status, self.slider, self.elapsed, self.duration, self.playBtn, prev, next, back, fwd, self.rateBtn, self.sleepBtn, close, list];
    for (UIView *v in all) [self.view addSubview:v];

    self.cover.frame = CGRectMake(w / 2 - 115, 90, 230, 230);
    self.titleLabel.frame = CGRectMake(24, 338, w - 48, 24);
    self.subLabel.frame = CGRectMake(24, 366, w - 48, 20);
    self.status.frame = CGRectMake(24, 388, w - 48, 18);
    self.slider.frame = CGRectMake(24, 418, w - 48, 28);
    self.elapsed.frame = CGRectMake(24, 448, 90, 16);
    self.duration.frame = CGRectMake(w - 114, 448, 90, 16);
    self.playBtn.frame = CGRectMake(w / 2 - 34, 480, 68, 68);
    prev.frame = CGRectMake(w / 2 - 112, 496, 40, 36);
    next.frame = CGRectMake(w / 2 + 72, 496, 40, 36);
    back.frame = CGRectMake(w / 2 - 168, 500, 34, 28);
    fwd.frame = CGRectMake(w / 2 + 134, 500, 34, 28);
    self.rateBtn.frame = CGRectMake(w / 2 - 120, 580, 100, 34);
    self.sleepBtn.frame = CGRectMake(w / 2 + 20, 580, 100, 34);
    close.frame = CGRectMake(16, 50, 36, 36);
    list.frame = CGRectMake(w - 52, 50, 36, 36);

    self.queue = [[UITableView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height, w, self.view.bounds.size.height * 0.6) style:UITableViewStylePlain];
    self.queue.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.queue.dataSource = self;
    self.queue.delegate = self;
    self.queue.hidden = YES;
    [self.view addSubview:self.queue];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerChanged" object:nil];
    [self sync];
}

- (UIButton *)icon:(NSString *)name size:(CGFloat)size action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)pill:(NSString *)t action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    b.layer.cornerRadius = 17;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)sync {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t) return;
    self.titleLabel.text = t.title;
    self.subLabel.text = p.album.title;
    self.status.text = p.statusText ?: @"";
    [ADUtil cover:self.cover url:p.album.cover];
    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    if (!self.dragging && dur > 0 && !isnan(dur)) {
        self.slider.maximumValue = dur;
        self.slider.value = cur;
    }
    self.elapsed.text = [ADUtil time:cur];
    self.duration.text = (dur > 0 && !isnan(dur)) ? [ADUtil time:dur] : @"--:--";
    [self.playBtn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:62 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [self.rateBtn setTitle:[NSString stringWithFormat:@"%.2gx", p.rate] forState:UIControlStateNormal];
    if (p.sleepDeadline > 0) {
        double left = p.sleepDeadline - [NSDate date].timeIntervalSince1970;
        [self.sleepBtn setTitle:[NSString stringWithFormat:@"%@后停", [ADUtil time:MAX(0, left)]] forState:UIControlStateNormal];
    } else {
        [self.sleepBtn setTitle:@"定时" forState:UIControlStateNormal];
    }
    if (self.showQueue) [self.queue reloadData];
}

- (void)sliderBegin { self.dragging = YES; }
- (void)sliderMoving { self.elapsed.text = [ADUtil time:self.slider.value]; }
- (void)sliderEnd { self.dragging = NO; [ADPlayer.shared seekTo:self.slider.value]; }
- (void)toggle { [ADPlayer.shared toggle]; [self sync]; }
- (void)prev { [ADPlayer.shared prev]; [self sync]; }
- (void)next { [ADPlayer.shared next]; [self sync]; }
- (void)back15 { [ADPlayer.shared seekBy:-15]; }
- (void)fwd30 { [ADPlayer.shared seekBy:30]; }

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
    CGRect f = self.queue.frame;
    f.origin.y = self.showQueue ? self.view.bounds.size.height * 0.4 : self.view.bounds.size.height;
    [UIView animateWithDuration:0.25 animations:^{ self.queue.frame = f; }];
    [self.queue reloadData];
    if (self.showQueue) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:ADPlayer.shared.index inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count) [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (void)closeMe { [self dismissViewControllerAnimated:YES completion:nil]; }

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
