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
    self.intro.frame = CGRectMake(16, 140, w - 32, 0);
    [head addSubview:self.cover];
    [head addSubview:self.titleLabel];
    [head addSubview:self.meta];
    [head addSubview:self.intro];
    self.table.tableHeaderView = head;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleFav)];

    [self fillHeader];
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] albumDetail:self.album.albumId done:^(ADAlbum *a, NSString *err) {
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
    self.intro.frame = CGRectMake(16, 136, w - 32, sz.height);
    UIView *head = self.table.tableHeaderView;
    CGFloat h = 136 + sz.height + 12;
    head.frame = CGRectMake(0, 0, w, h);
    self.table.tableHeaderView = head;

    BOOL fav = [[ADStore shared] isFavorite:self.album.albumId];
    [self.navigationItem.rightBarButtonItem setImage:[UIImage systemImageNamed:fav ? @"heart.fill" : @"heart"]];
    self.navigationItem.rightBarButtonItem.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
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
    [[ADApi shared] tracksOf:self.album.albumId page:self.page done:^(NSArray<ADTrack *> *list, NSInteger total, NSString *err) {
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
@property (nonatomic, strong) UITextField *baseField, *tokenField;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSArray<NSDictionary *> *downloads;
@property (nonatomic, copy) void (^onSaved)(BOOL ok);
@end

@implementation ADSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.title = @"设置";
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    self.baseField = [self field:[ADConfig shared].baseURL placeholder:@"https://服务器地址:端口"];
    self.tokenField = [self field:[ADConfig shared].token placeholder:@"粘贴 token"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    self.status = [ADUtil label:nil size:12 color:[ADUtil dim]];
    [self loadDownloads];
}

- (UITextField *)field:(NSString *)text placeholder:(NSString *)ph {
    UITextField *f = [UITextField new];
    f.text = text;
    f.placeholder = ph;
    f.textColor = UIColor.whiteColor;
    f.font = [UIFont systemFontOfSize:14];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.keyboardType = UIKeyboardTypeURL;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.delegate = self;
    return f;
}

- (void)save {
    [ADConfig shared].baseURL = self.baseField.text;
    [ADConfig shared].token = self.tokenField.text;
    [[ADConfig shared] save];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    [self test];
}

- (void)test {
    self.status.text = @"正在测试连接…";
    __weak typeof(self) w = self;
    [[ADApi shared] albumDetail:@"XMID59325711" done:^(ADAlbum *a, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.status.text = err ? [@"连接失败：" stringByAppendingString:err] : [NSString stringWithFormat:@"连接正常 · %@", a.title];
        if (self.onSaved) self.onSaved(err == nil);
    }];
}

- (void)loadDownloads {
    __weak typeof(self) w = self;
    [[ADApi shared] downloads:^(NSArray<NSDictionary *> *items, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.downloads = items;
        [self.table reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return @[@"服务", @"下载任务", @""][s];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 3;
    if (s == 1) return MAX(1, (NSInteger)self.downloads.count);
    return 1;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [ADUtil card];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [ADUtil dim];
    c.textLabel.font = [UIFont systemFontOfSize:14];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    if (ip.section == 0) {
        UITextField *f = ip.row == 0 ? self.baseField : self.tokenField;
        if (ip.row < 2) {
            c.textLabel.text = ip.row == 0 ? @"服务地址" : @"Token";
            f.frame = CGRectMake(t.bounds.size.width - 230, 8, 214, 30);
            f.textAlignment = NSTextAlignmentRight;
            f.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [c.contentView addSubview:f];
        } else {
            c.textLabel.text = @"测试连接";
            c.textLabel.textColor = [ADUtil brand];
        }
    } else if (ip.section == 1) {
        if (!self.downloads.count) {
            c.textLabel.text = @"暂无任务";
            c.textLabel.textColor = [ADUtil dim];
        } else {
            NSDictionary *d = self.downloads[ip.row];
            c.textLabel.text = d[@"albumTitle"] ?: d[@"albumId"] ?: @"任务";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@/%@", d[@"status"] ?: @"", d[@"done"] ?: @0, d[@"total"] ?: @0];
        }
    } else {
        c.textLabel.text = @"刷新下载任务";
        c.textLabel.textColor = [ADUtil brand];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 2) [self save];
    if (ip.section == 2) [self loadDownloads];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self save]; return YES; }
@end
