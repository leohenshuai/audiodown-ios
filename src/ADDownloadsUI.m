#import "AD.h"

// ───────────── 本机下载：专辑卡片列表 ─────────────
static NSString *ADSize2(double b) {
    if (b >= 1073741824.0) return [NSString stringWithFormat:@"%.2f GB", b / 1073741824.0];
    if (b >= 1048576.0) return [NSString stringWithFormat:@"%.1f MB", b / 1048576.0];
    if (b > 0) return [NSString stringWithFormat:@"%.0f KB", b / 1024.0];
    return @"0 MB";
}
static UIImage *ADSym(NSString *n, CGFloat sz, UIImageSymbolWeight w) {
    return [UIImage systemImageNamed:n withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:sz weight:w]];
}
static NSString *ADStateText(ADTask *t, NSInteger local, NSInteger failed) {
    switch (t.state) {
        case ADTaskStateRunning: return @"下载中";
        case ADTaskStateQueued: return @"排队中";
        case ADTaskStatePaused: return @"已暂停";
        case ADTaskStateFailed: return [NSString stringWithFormat:@"%ld 集失败", (long)failed];
        default: return local >= (NSInteger)t.tracks.count ? @"已完成" : @"部分完成";
    }
}
static UIColor *ADStateColor(ADTask *t) {
    switch (t.state) {
        case ADTaskStateRunning: return [ADUtil brand];
        case ADTaskStateFailed: return [UIColor systemRedColor];
        case ADTaskStateDone: return [UIColor systemGreenColor];
        default: return [UIColor colorWithWhite:1 alpha:0.55];
    }
}

@interface ADDLCard : UITableViewCell
@property (nonatomic, strong) UIView *card, *barBg, *barFill;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title, *state, *meta, *cur;
@property (nonatomic, strong) UIButton *action;
@property (nonatomic, assign) CGFloat frac;
@property (nonatomic, copy) void (^onAction)(void);
@end
@implementation ADDLCard
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [UIView new];
        [ADLiquid glassLite:self.card radius:22];
        [self.contentView addSubview:self.card];
        self.cover = [UIImageView new];
        self.cover.layer.cornerRadius = 14; self.cover.clipsToBounds = YES;
        self.cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        self.title = [ADUtil label:@"PingFangSC-Semibold" size:16.5 color:UIColor.whiteColor]; self.title.numberOfLines = 1;
        self.state = [ADUtil label:nil size:11 color:UIColor.whiteColor]; self.state.numberOfLines = 1;
        self.state.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        self.state.textAlignment = NSTextAlignmentCenter; self.state.layer.cornerRadius = 9; self.state.clipsToBounds = YES;
        self.meta = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.55]]; self.meta.numberOfLines = 1;
        self.cur = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.45]]; self.cur.numberOfLines = 1;
        self.barBg = [UIView new]; self.barBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12]; self.barBg.layer.cornerRadius = 2;
        self.barFill = [UIView new]; self.barFill.layer.cornerRadius = 2; [self.barBg addSubview:self.barFill];
        self.action = [UIButton buttonWithType:UIButtonTypeSystem];
        [ADLiquid glassButton:self.action radius:20];
        self.action.tintColor = UIColor.whiteColor;
        [self.action addTarget:self action:@selector(tapAction) forControlEvents:UIControlEventTouchUpInside];
        for (UIView *v in @[self.cover, self.title, self.state, self.meta, self.cur, self.barBg, self.action]) [self.card addSubview:v];
    }
    return self;
}
- (void)tapAction { [ADHaptic tap]; if (self.onAction) self.onAction(); }
- (void)setHighlighted:(BOOL)h animated:(BOOL)a {
    [super setHighlighted:h animated:a];
    [UIView animateWithDuration:h ? 0.12 : 0.38 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.card.transform = h ? CGAffineTransformMakeScale(0.975, 0.975) : CGAffineTransformIdentity; } completion:nil];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    self.card.frame = CGRectMake(16, 6, W - 32, H - 12);
    CGFloat cw = self.card.bounds.size.width, ch = self.card.bounds.size.height;
    self.cover.frame = CGRectMake(14, (ch - 76) / 2, 76, 76);
    CGFloat x = 104, tw = cw - x - 62;
    self.title.frame = CGRectMake(x, 14, tw, 21);
    CGSize ss = [self.state.text sizeWithAttributes:@{NSFontAttributeName: self.state.font}];
    self.state.frame = CGRectMake(x, 40, ss.width + 16, 18);
    self.meta.frame = CGRectMake(x + ss.width + 24, 40, tw - ss.width - 24, 18);
    self.cur.frame = CGRectMake(x, 62, tw, 16);
    self.barBg.frame = CGRectMake(x, ch - 18, tw, 4);
    self.barFill.frame = CGRectMake(0, 0, MAX(self.frac > 0 ? 4 : 0, tw * self.frac), 4);
    self.action.frame = CGRectMake(cw - 54, (ch - 40) / 2, 40, 40);
    [ADLiquid corner:20 on:self.action];
}
@end

@interface ADDownloadsController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIButton *back, *allBtn;
@property (nonatomic, strong) UILabel *head, *sum, *empty;
@property (nonatomic, strong) UIImageView *emptyIcon;
@property (nonatomic, assign) CFTimeInterval lastRefresh;
@end

@implementation ADDownloadsController
- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = 120;
    self.table.contentInset = UIEdgeInsetsMake(4, 0, 110, 0);
    [self.table registerClass:ADDLCard.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:self.table];

    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    [self.back setImage:ADSym(@"chevron.left", 17, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    self.allBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.allBtn radius:18];
    self.allBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.allBtn addTarget:self action:@selector(toggleAll) forControlEvents:UIControlEventTouchUpInside];
    self.head = [ADUtil label:@"PingFangSC-Semibold" size:30 color:UIColor.whiteColor];
    self.head.text = @"本机下载"; self.head.numberOfLines = 1;
    self.sum = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.5]]; self.sum.numberOfLines = 1;
    self.emptyIcon = [[UIImageView alloc] initWithImage:ADSym(@"arrow.down.circle", 46, UIImageSymbolWeightLight)];
    self.emptyIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.22]; self.emptyIcon.contentMode = UIViewContentModeCenter;
    self.empty = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.45]];
    self.empty.textAlignment = NSTextAlignmentCenter;
    self.empty.text = @"还没有下载\n在专辑页点下载按钮，选择整本或分段";
    for (UIView *v in @[self.back, self.allBtn, self.head, self.sum, self.emptyIcon, self.empty]) [self.view addSubview:v];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed) name:@"ADDownloadChanged" object:nil];
}
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
    [self reload];
}
- (void)viewWillDisappear:(BOOL)a {
    [super viewWillDisappear:a];
    // 设置页用系统导航栏，返回时恢复
    if (self.navigationController.viewControllers.count >= 1 && ![self.navigationController.viewControllers containsObject:self])
        self.navigationController.navigationBar.hidden = NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.navigationController.viewControllers.count > 1; }
- (void)goBack {
    [ADHaptic tap];
    self.navigationController.navigationBar.hidden = NO;
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, top = MAX(self.view.safeAreaInsets.top, 47);
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    self.allBtn.frame = CGRectMake(W - 16 - 96, top + 6, 96, 36);
    self.head.frame = CGRectMake(72, top + 6, W - 72 - 120, 38);
    self.sum.frame = CGRectMake(20, top + 54, W - 40, 18);
    self.table.frame = CGRectMake(0, top + 78, W, self.view.bounds.size.height - top - 78);
    self.emptyIcon.frame = CGRectMake(0, self.view.bounds.size.height / 2 - 100, W, 60);
    self.empty.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 34, W - 60, 50);
}

- (void)changed {
    // 下载进度通知很频繁，0.3 秒内只刷可见行
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastRefresh < 0.3) return;
    self.lastRefresh = now;
    [self reload];
}
- (void)reload {
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    double bytes = 0; NSInteger eps = 0, running = 0;
    for (ADTask *t in tasks) { bytes += [[ADDownloader shared] bytesForTask:t]; eps += [[ADDownloader shared] localCountOf:t]; if (t.state == ADTaskStateRunning || t.state == ADTaskStateQueued) running++; }
    self.sum.text = tasks.count ? [NSString stringWithFormat:@"%ld 本 · %ld 集 · %@%@", (long)tasks.count, (long)eps, ADSize2(bytes), running ? [NSString stringWithFormat:@" · %ld 本进行中", (long)running] : @""] : @"";
    self.empty.hidden = self.emptyIcon.hidden = tasks.count > 0;
    self.allBtn.hidden = tasks.count == 0;
    [self.allBtn setTitle:(running ? @"全部暂停" : @"全部继续") forState:UIControlStateNormal];
    [self.allBtn setTitleColor:(running ? UIColor.whiteColor : [ADUtil brand]) forState:UIControlStateNormal];
    [self.table reloadData];
}
- (void)toggleAll {
    [ADHaptic tap];
    BOOL running = NO;
    for (ADTask *t in [ADDownloader shared].tasks) if (t.state == ADTaskStateRunning || t.state == ADTaskStateQueued) running = YES;
    if (running) [[ADDownloader shared] pauseAll]; else [[ADDownloader shared] resumeAll];
    [self reload];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [ADDownloader shared].tasks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADDLCard *c = [t dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    ADDownloader *dl = [ADDownloader shared];
    ADTask *k = dl.tasks[ip.row];
    NSInteger total = k.tracks.count, local = [dl localCountOf:k], failed = [dl failedCountOf:k];
    double bytes = [dl bytesForTask:k];
    [ADUtil cover:c.cover url:k.cover];
    c.title.text = k.title.length ? k.title : k.albumId;
    c.state.text = ADStateText(k, local, failed);
    UIColor *sc = ADStateColor(k);
    c.state.backgroundColor = [sc colorWithAlphaComponent:0.2];
    c.state.textColor = sc;
    c.meta.text = [NSString stringWithFormat:@"%ld/%ld 集 · %@", (long)local, (long)total, ADSize2(bytes)];
    // 当前这一集的进度
    BOOL isCur = (k.state == ADTaskStateRunning && dl.currentTrackId.length);
    double frac = total > 0 ? (double)local / total : 0;
    if (isCur) {
        NSString *name = nil;
        for (ADTrack *x in k.tracks) if ([x.trackId isEqualToString:dl.currentTrackId]) { name = x.title; break; }
        double p = dl.currentExpected > 0 ? dl.currentWritten / dl.currentExpected : 0;
        c.cur.text = name ? [NSString stringWithFormat:@"正在下载：%@ %@", name, dl.currentExpected > 0 ? [NSString stringWithFormat:@"%ld%%", (long)lround(p * 100)] : @"获取地址…"] : @"正在准备…";
        c.cur.textColor = [ADUtil brand];
        if (total > 0) frac = (local + p) / total;
    } else if (failed > 0) {
        c.cur.text = [NSString stringWithFormat:@"%ld 集下载失败，点进去可重试", (long)failed];
        c.cur.textColor = [UIColor systemRedColor];
    } else {
        c.cur.text = local >= total ? @"全部可离线收听" : @"点进去查看单集";
        c.cur.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    }
    c.frac = MIN(1, frac);
    c.barFill.backgroundColor = k.state == ADTaskStateDone ? [UIColor systemGreenColor] : [ADUtil brand];
    BOOL active = (k.state == ADTaskStateRunning || k.state == ADTaskStateQueued);
    NSString *ic = active ? @"pause.fill" : (local >= total ? @"chevron.right" : (failed ? @"arrow.clockwise" : @"play.fill"));
    [c.action setImage:ADSym(ic, 15, UIImageSymbolWeightBold) forState:UIControlStateNormal];
    c.action.tintColor = active ? UIColor.whiteColor : (local >= total ? [UIColor colorWithWhite:1 alpha:0.5] : [ADUtil brand]);
    __weak typeof(self) w = self;
    c.onAction = ^{
        if (active) [dl pauseTask:k];
        else if (local >= total) { [w openTask:k]; return; }
        else if (failed) [dl retryFailed:k];
        else [dl resumeTask:k];
        [w reload];
    };
    [c setNeedsLayout];
    return c;
}
- (void)openTask:(ADTask *)k {
    ADDownloadDetailController *vc = [ADDownloadDetailController new];
    vc.task = k;
    [self.navigationController pushViewController:vc animated:YES];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic tap];
    [self openTask:[ADDownloader shared].tasks[ip.row]];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    ADTask *k = [ADDownloader shared].tasks[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [self confirmDelete:k done:done];
    }];
    del.image = ADSym(@"trash.fill", 16, UIImageSymbolWeightSemibold);
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)t contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)p {
    ADTask *k = [ADDownloader shared].tasks[ip.row];
    [ADHaptic heavy];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        UIAction *open = [UIAction actionWithTitle:@"编辑单集" image:ADSym(@"list.bullet", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(UIAction *a) { [self openTask:k]; }];
        UIAction *album = [UIAction actionWithTitle:@"打开专辑" image:ADSym(@"book", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(UIAction *a) {
            ADAlbum *al = [ADAlbum new]; al.albumId = k.albumId; al.title = k.title; al.cover = k.cover; al.anchor = k.anchor; al.provider = k.provider;
            ADAlbumController *vc = [ADAlbumController new]; vc.album = al;
            [self.navigationController pushViewController:vc animated:YES];
        }];
        UIAction *retry = [UIAction actionWithTitle:@"重试失败的集" image:ADSym(@"arrow.clockwise", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(UIAction *a) { [[ADDownloader shared] retryFailed:k]; }];
        UIAction *del = [UIAction actionWithTitle:@"删除整本" image:ADSym(@"trash", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(UIAction *a) { [self confirmDelete:k done:nil]; }];
        del.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithTitle:k.title ?: @"" children:@[open, album, retry, del]];
    }];
}
- (void)confirmDelete:(ADTask *)k done:(void (^)(BOOL))done {
    UIAlertController *q = [UIAlertController alertControllerWithTitle:@"删除整本下载？" message:[NSString stringWithFormat:@"《%@》的 %ld 集音频会一起删除", k.title ?: @"", (long)[[ADDownloader shared] localCountOf:k]] preferredStyle:UIAlertControllerStyleAlert];
    [q addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { if (done) done(NO); }]];
    [q addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [ADHaptic warning];
        [[ADDownloader shared] deleteTask:k];
        [self reload];
        if (done) done(YES);
    }]];
    [self presentViewController:q animated:YES completion:nil];
}
@end

// ───────────── 某本书的单集：查看进度 / 多选编辑 ─────────────
@interface ADDLEpCell : UITableViewCell
@property (nonatomic, strong) UILabel *num, *name, *sub;
@property (nonatomic, strong) UIImageView *mark;
@property (nonatomic, strong) UIView *ring;
@property (nonatomic, strong) CAShapeLayer *ringFill;
@end
@implementation ADDLEpCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.num = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.38]];
        self.num.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        self.num.textAlignment = NSTextAlignmentCenter; self.num.numberOfLines = 1;
        self.name = [ADUtil label:nil size:15.5 color:UIColor.whiteColor]; self.name.numberOfLines = 1;
        self.name.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightMedium];
        self.sub = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]]; self.sub.numberOfLines = 1;
        self.mark = [UIImageView new]; self.mark.contentMode = UIViewContentModeCenter;
        // 环形进度
        self.ring = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
        CAShapeLayer *bg = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(13, 13) radius:11 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        bg.path = path.CGPath; bg.fillColor = UIColor.clearColor.CGColor; bg.lineWidth = 3;
        bg.strokeColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
        self.ringFill = [CAShapeLayer layer];
        self.ringFill.path = path.CGPath; self.ringFill.fillColor = UIColor.clearColor.CGColor; self.ringFill.lineWidth = 3;
        self.ringFill.strokeColor = [ADUtil brand].CGColor; self.ringFill.lineCap = kCALineCapRound; self.ringFill.strokeEnd = 0;
        [self.ring.layer addSublayer:bg]; [self.ring.layer addSublayer:self.ringFill];
        for (UIView *v in @[self.num, self.name, self.sub, self.mark, self.ring]) [self.contentView addSubview:v];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    self.num.frame = CGRectMake(10, 0, 44, H);
    self.name.frame = CGRectMake(58, 11, W - 58 - 60, 20);
    self.sub.frame = CGRectMake(58, 33, W - 58 - 60, 16);
    self.mark.frame = CGRectMake(W - 52, 0, 36, H);
    self.ring.center = CGPointMake(W - 34, H / 2);
}
@end

@interface ADDownloadDetailController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIButton *back, *editBtn, *allBtn;
@property (nonatomic, strong) UILabel *head, *sum;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *barLabel;
@property (nonatomic, strong) UIButton *barDel, *barRedo;
@property (nonatomic, assign) BOOL editing2;
@property (nonatomic, strong) NSMutableSet<NSString *> *sel;
@property (nonatomic, assign) CFTimeInterval lastRefresh;
@end

@implementation ADDownloadDetailController
- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.sel = [NSMutableSet set];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.07];
    self.table.separatorInset = UIEdgeInsetsMake(0, 58, 0, 16);
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = 60;
    [self.table registerClass:ADDLEpCell.class forCellReuseIdentifier:@"e"];
    [self.view addSubview:self.table];

    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    [self.back setImage:ADSym(@"chevron.left", 17, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    self.editBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.editBtn radius:18];
    self.editBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.editBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.editBtn addTarget:self action:@selector(toggleEdit) forControlEvents:UIControlEventTouchUpInside];
    self.allBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.allBtn radius:18];
    self.allBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.allBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
    [self.allBtn addTarget:self action:@selector(selectAll) forControlEvents:UIControlEventTouchUpInside];

    self.cover = [UIImageView new];
    self.cover.layer.cornerRadius = 12; self.cover.clipsToBounds = YES;
    [ADUtil cover:self.cover url:self.task.cover];
    self.head = [ADUtil label:@"PingFangSC-Semibold" size:20 color:UIColor.whiteColor]; self.head.numberOfLines = 2;
    self.head.text = self.task.title;
    self.sum = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.55]]; self.sum.numberOfLines = 2;

    // 编辑时的底部操作条
    self.bar = [UIView new];
    [ADLiquid glass:self.bar radius:26 alpha:0.06];
    [ADLiquid float:self.bar];
    self.bar.hidden = YES;
    self.barLabel = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.75]]; self.barLabel.numberOfLines = 1;
    self.barRedo = [UIButton buttonWithType:UIButtonTypeSystem];
    self.barRedo.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14]; self.barRedo.layer.cornerRadius = 19;
    self.barRedo.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.barRedo setTitle:@"重新下载" forState:UIControlStateNormal];
    [self.barRedo setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.barRedo addTarget:self action:@selector(redoSel) forControlEvents:UIControlEventTouchUpInside];
    self.barDel = [UIButton buttonWithType:UIButtonTypeSystem];
    self.barDel.backgroundColor = [UIColor systemRedColor]; self.barDel.layer.cornerRadius = 19;
    self.barDel.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.barDel setTitle:@"删除" forState:UIControlStateNormal];
    [self.barDel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.barDel addTarget:self action:@selector(deleteSel) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[self.barLabel, self.barRedo, self.barDel]) [self.bar addSubview:v];

    for (UIView *v in @[self.back, self.editBtn, self.allBtn, self.cover, self.head, self.sum, self.bar]) [self.view addSubview:v];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed) name:@"ADDownloadChanged" object:nil];
    [self paint];
}
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
    [self reload];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return !self.editing2 && self.navigationController.viewControllers.count > 1; }
- (void)goBack { [ADHaptic tap]; [self.navigationController popViewControllerAnimated:YES]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = MAX(self.view.safeAreaInsets.top, 47);
    CGFloat sb = self.view.safeAreaInsets.bottom;
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    self.editBtn.frame = CGRectMake(W - 16 - 64, top + 6, 64, 36);
    self.allBtn.frame = CGRectMake(W - 16 - 64 - 8 - 64, top + 6, 64, 36);
    self.cover.frame = CGRectMake(20, top + 60, 72, 72);
    self.head.frame = CGRectMake(106, top + 60, W - 106 - 20, 50);
    self.sum.frame = CGRectMake(106, top + 104, W - 106 - 20, 34);
    CGFloat tt = top + 148;
    self.table.frame = CGRectMake(0, tt, W, H - tt);
    self.table.contentInset = UIEdgeInsetsMake(0, 0, self.editing2 ? 100 : 110, 0);
    self.bar.frame = CGRectMake(14, H - sb - 12 - 64, W - 28, 64);
    self.barLabel.frame = CGRectMake(18, 0, 120, 64);
    self.barDel.frame = CGRectMake(self.bar.bounds.size.width - 12 - 76, 13, 76, 38);
    self.barRedo.frame = CGRectMake(self.bar.bounds.size.width - 12 - 76 - 10 - 96, 13, 96, 38);
}

- (void)paint {
    [self.editBtn setTitle:self.editing2 ? @"完成" : @"编辑" forState:UIControlStateNormal];
    self.allBtn.hidden = !self.editing2;
    NSInteger n = self.task.tracks.count;
    [self.allBtn setTitle:(self.sel.count == (NSUInteger)n && n ? @"全不选" : @"全选") forState:UIControlStateNormal];
    self.barLabel.text = [NSString stringWithFormat:@"已选 %ld 集", (long)self.sel.count];
    self.barDel.enabled = self.barRedo.enabled = self.sel.count > 0;
    self.barDel.alpha = self.barRedo.alpha = self.sel.count > 0 ? 1 : 0.4;
}
- (void)toggleEdit {
    [ADHaptic select];
    self.editing2 = !self.editing2;
    if (!self.editing2) [self.sel removeAllObjects];
    [self paint];
    self.bar.hidden = NO;
    self.bar.transform = self.editing2 ? CGAffineTransformMakeTranslation(0, 120) : CGAffineTransformIdentity;
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.4 options:0 animations:^{
        self.bar.transform = self.editing2 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 120);
    } completion:^(BOOL f) { if (!self.editing2) self.bar.hidden = YES; }];
    [self.view setNeedsLayout];
    [self.table reloadData];
}
- (void)selectAll {
    [ADHaptic select];
    NSInteger n = self.task.tracks.count;
    if (self.sel.count == (NSUInteger)n) [self.sel removeAllObjects];
    else for (ADTrack *t in self.task.tracks) [self.sel addObject:t.trackId];
    [self paint]; [self.table reloadData];
}
- (void)changed {
    if (![[ADDownloader shared].tasks containsObject:self.task]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastRefresh < 0.25) return;
    self.lastRefresh = now;
    [self reload];
}
- (void)reload {
    ADDownloader *dl = [ADDownloader shared];
    NSInteger total = self.task.tracks.count, local = [dl localCountOf:self.task], failed = [dl failedCountOf:self.task];
    NSString *st = ADStateText(self.task, local, failed);
    self.sum.text = [NSString stringWithFormat:@"%@ · 已存 %ld/%ld 集 · %@%@", st, (long)local, (long)total, ADSize2([dl bytesForTask:self.task]),
                     failed ? [NSString stringWithFormat:@"\n%ld 集失败，左滑可单独重试", (long)failed] : @""];
    // 只刷可见行，避免进度刷新时跳动
    if (self.table.visibleCells.count && self.table.numberOfSections && [self.table numberOfRowsInSection:0] == total) {
        for (NSIndexPath *ip in self.table.indexPathsForVisibleRows) [self fill:(ADDLEpCell *)[self.table cellForRowAtIndexPath:ip] at:ip.row];
    } else [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.task.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADDLEpCell *c = [t dequeueReusableCellWithIdentifier:@"e" forIndexPath:ip];
    [self fill:c at:ip.row];
    return c;
}
- (void)fill:(ADDLEpCell *)c at:(NSInteger)row {
    if (![c isKindOfClass:ADDLEpCell.class] || row >= (NSInteger)self.task.tracks.count) return;
    ADDownloader *dl = [ADDownloader shared];
    ADTrack *tr = self.task.tracks[row];
    c.num.text = [NSString stringWithFormat:@"%ld", (long)row + 1];
    c.name.text = tr.title;
    BOOL local = [dl hasLocal:tr.trackId];
    BOOL cur = (self.task.state == ADTaskStateRunning && [dl.currentTrackId isEqualToString:tr.trackId]);
    BOOL failed = !local && [dl isFailed:tr.trackId];
    BOOL active = (self.task.state == ADTaskStateRunning || self.task.state == ADTaskStateQueued);
    UIImageSymbolConfiguration *cf = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium];
    c.ring.hidden = YES; c.mark.hidden = NO;
    c.name.textColor = UIColor.whiteColor;
    if (self.editing2) {
        BOOL on = [self.sel containsObject:tr.trackId];
        c.mark.image = [UIImage systemImageNamed:on ? @"checkmark.circle.fill" : @"circle" withConfiguration:cf];
        c.mark.tintColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.4];
    }
    if (local) {
        c.sub.text = [NSString stringWithFormat:@"已下载 · %@%@", ADSize2([dl fileSize:tr.trackId]), tr.duration > 0 ? [NSString stringWithFormat:@" · %@", [ADUtil time:tr.duration]] : @""];
        c.sub.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        if (!self.editing2) { c.mark.image = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:cf]; c.mark.tintColor = [UIColor systemGreenColor]; }
    } else if (cur) {
        double p = dl.currentExpected > 0 ? dl.currentWritten / dl.currentExpected : 0;
        c.sub.text = dl.currentExpected > 0 ? [NSString stringWithFormat:@"下载中 %ld%% · %@ / %@", (long)lround(p * 100), ADSize2(dl.currentWritten), ADSize2(dl.currentExpected)] : @"正在获取音频地址…";
        c.sub.textColor = [ADUtil brand];
        c.name.textColor = [ADUtil brand];
        if (!self.editing2) {
            c.mark.hidden = YES; c.ring.hidden = NO;
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            c.ringFill.strokeEnd = MAX(0.04, p);
            [CATransaction commit];
        }
    } else if (failed) {
        c.sub.text = @"下载失败 · 左滑重试";
        c.sub.textColor = [UIColor systemRedColor];
        if (!self.editing2) { c.mark.image = [UIImage systemImageNamed:@"exclamationmark.circle.fill" withConfiguration:cf]; c.mark.tintColor = [UIColor systemRedColor]; }
    } else {
        c.sub.text = active ? @"等待下载" : @"未下载";
        c.sub.textColor = [UIColor colorWithWhite:1 alpha:0.4];
        if (!self.editing2) { c.mark.image = [UIImage systemImageNamed:active ? @"clock" : @"arrow.down.circle" withConfiguration:cf]; c.mark.tintColor = [UIColor colorWithWhite:1 alpha:0.35]; }
    }
    [c setNeedsLayout];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    ADTrack *tr = self.task.tracks[ip.row];
    if (self.editing2) {
        [ADHaptic select];
        if ([self.sel containsObject:tr.trackId]) [self.sel removeObject:tr.trackId]; else [self.sel addObject:tr.trackId];
        [self fill:(ADDLEpCell *)[t cellForRowAtIndexPath:ip] at:ip.row];
        [self paint];
        return;
    }
    // 非编辑：已下载的集直接播放
    if (![[ADDownloader shared] hasLocal:tr.trackId]) { [ADHaptic soft]; return; }
    [ADHaptic tap];
    ADAlbum *al = [ADAlbum new]; al.albumId = self.task.albumId; al.title = self.task.title; al.cover = self.task.cover; al.anchor = self.task.anchor; al.provider = self.task.provider;
    for (ADAlbum *x in [ADStore shared].history) if ([x.albumId isEqualToString:al.albumId]) { al = x; break; }
    [ADPlayer.shared playAlbum:al tracks:self.task.tracks at:ip.row];
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (self.editing2) return nil;
    ADTrack *tr = self.task.tracks[ip.row];
    BOOL local = [[ADDownloader shared] hasLocal:tr.trackId];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ADHaptic warning];
        [[ADDownloader shared] removeTracks:@[tr.trackId] fromTask:self.task];
        done(YES);
        [self.table reloadData]; [self reload];
    }];
    UIContextualAction *redo = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:local ? @"重下" : @"重试" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ADHaptic success];
        [[ADDownloader shared] redownload:@[tr.trackId] inTask:self.task];
        done(YES);
        [self reload];
    }];
    redo.backgroundColor = [ADUtil brand];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, redo]];
}

- (void)deleteSel {
    if (!self.sel.count) return;
    NSInteger n = self.sel.count;
    UIAlertController *q = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除 %ld 集？", (long)n] message:@"音频文件会删除，这几集也会从下载列表移除" preferredStyle:UIAlertControllerStyleAlert];
    [q addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [q addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [ADHaptic warning];
        NSArray *ids = self.sel.allObjects;
        BOOL all = (ids.count >= self.task.tracks.count);
        [[ADDownloader shared] removeTracks:ids fromTask:self.task];
        [self.sel removeAllObjects];
        if (all) { [self.navigationController popViewControllerAnimated:YES]; return; }
        [self toggleEdit];
        [self.table reloadData]; [self reload];
    }]];
    [self presentViewController:q animated:YES completion:nil];
}
- (void)redoSel {
    if (!self.sel.count) return;
    [ADHaptic success];
    [[ADDownloader shared] redownload:self.sel.allObjects inTask:self.task];
    [self.sel removeAllObjects];
    [self toggleEdit];
    [self reload];
}
@end
