#import "AD.h"
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ADInternal.h"

// ───────────── 播放器 ─────────────
@interface ADPlayerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *coverLabel;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *mid, *duration, *status;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *playBtn, *starBtn, *moreBtn;
@property (nonatomic, strong) AVRoutePickerView *routeView;
@property (nonatomic, strong) UIButton *rateBtn, *sleepBtn;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) UITableView *queue;
@property (nonatomic, strong) UIView *queueDim;
@property (nonatomic, assign) BOOL showQueue;
@property (nonatomic, assign) BOOL queueDesc, queueSelecting;
@property (nonatomic, strong) NSMutableSet *queueSel;
@property (nonatomic, strong) UIView *queueBar;
@property (nonatomic, assign) NSInteger queueSeenCount;
@property (nonatomic, strong) UIButton *sortBtn, *pickBtn, *selBtn, *dlBtn;
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
    self.playBtn.tintColor = [UIColor colorWithWhite:0.09 alpha:1];
    self.playBtn.backgroundColor = UIColor.whiteColor;
    self.playBtn.layer.cornerRadius = 32;
    self.playBtn.layer.shadowColor = UIColor.blackColor.CGColor;
    self.playBtn.layer.shadowOpacity = 0.35; self.playBtn.layer.shadowRadius = 18; self.playBtn.layer.shadowOffset = CGSizeMake(0, 8);
    [self.playBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.playBtn addTarget:self action:@selector(ctlDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self.playBtn addTarget:self action:@selector(ctlUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

    for (UIView *v in @[self.cover, self.titleLabel, self.subLabel, self.starBtn, more, self.slider,
                        self.elapsed, self.mid, self.duration, self.status, self.playBtn]) {
        [self.view addSubview:v];
    }

    // 控制行
    UIButton *prev = [self iconButton:@"backward.end.fill" size:19 action:@selector(prev)];
    UIButton *back = [self iconButton:@"gobackward.15" size:26 action:@selector(back15)];
    UIButton *fwd = [self iconButton:@"goforward.15" size:26 action:@selector(fwd15)];
    UIButton *next = [self iconButton:@"forward.end.fill" size:19 action:@selector(next)];
    prev.tag = 201; back.tag = 202; fwd.tag = 203; next.tag = 204;
    for (UIButton *b in @[prev, back, fwd, next]) {
        b.tintColor = [UIColor colorWithWhite:1 alpha:0.92];
        [b addTarget:self action:@selector(ctlDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [b addTarget:self action:@selector(ctlUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self.view addSubview:b];
    }

    // 底部工具行
    self.rateBtn = [self textButton:@"1x" action:@selector(showRateMenu)];
    self.sleepBtn = [self iconButton:@"moon.zzz.fill" size:22 action:@selector(showSleepMenu)];
    UIButton *list = [self iconButton:@"list.bullet" size:22 action:@selector(showQueueList)];
    self.rateBtn.tag = 301; self.sleepBtn.tag = 302; list.tag = 304;
    [self.view addSubview:self.rateBtn];
    [self.view addSubview:self.sleepBtn];
    [self.view addSubview:list];

    UIView *toolPill = [[UIView alloc] initWithFrame:CGRectZero];
    toolPill.tag = 900;
    toolPill.userInteractionEnabled = NO;
    [ADLiquid glass:toolPill radius:24 alpha:0.05];
    [ADLiquid float:toolPill];
    toolPill.layer.shadowOpacity = 0.22;
    [self.view addSubview:toolPill];
    [self.view insertSubview:toolPill belowSubview:self.rateBtn];

    self.routeView = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 44, 36)];
    self.routeView.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    self.routeView.activeTintColor = [ADUtil brand];
    self.routeView.prioritizesVideoDevices = NO;
    [self.view addSubview:self.routeView];

    self.queue = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    [ADLiquid glass:self.queue radius:20 alpha:0.035];
    self.queue.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    self.queue.dataSource = self;
    self.queue.delegate = self;
    self.queue.hidden = YES;
    self.queue.layer.cornerRadius = 18;
    self.queue.clipsToBounds = YES;
    self.queueDim = [[UIView alloc] initWithFrame:self.view.bounds];
    self.queueDim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    self.queueDim.hidden = YES;
    [self.queueDim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeQueue)]];
    [self.view addSubview:self.queueDim];
    [self.view addSubview:self.queue];

    self.queueSel = [NSMutableSet set];
    self.queueBar = [[UIView alloc] initWithFrame:CGRectZero];
    [ADLiquid glass:self.queueBar radius:16 alpha:0.05];
    self.queueBar.hidden = YES;
    [self.view addSubview:self.queueBar];
    self.sortBtn = [self barButton:@"正序" action:@selector(toggleQueueSort)];
    self.pickBtn = [self barButton:@"选集" action:@selector(showQueuePicker)];
    self.selBtn  = [self barButton:@"多选" action:@selector(toggleQueueSelect)];
    self.dlBtn   = [self barButton:@"缓存整本" action:@selector(queueDownload)];
    for (UIButton *b in @[self.sortBtn, self.pickBtn, self.selBtn, self.dlBtn]) [self.queueBar addSubview:b];

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
    [ADLiquid glassButton:b radius:22];
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
    CGFloat top = safeTop + 16;
    CGFloat bottomPad = safeBottom + 16;
    CGFloat blockH = 70 + 28 + 30 + 80 + 40;
    CGFloat lastGap = 30;                 // 控制行与底部工具行：工具条整体比之前再下移约 12pt
    CGFloat coverMax = MIN(W - 24, H * 0.52);
    CGFloat leftover = H - top - bottomPad - blockH - coverMax - lastGap;
    CGFloat coverH = coverMax;
    if (leftover < 0) { coverH = MAX(140, coverMax + leftover); leftover = 0; }
    CGFloat gap = MIN(22.0, MAX(6.0, leftover / 4.0));
    CGFloat extra = MAX(0, leftover - gap * 4.0);
    top += extra * 0.55;                  // 多出来的空间主要给顶部（封面与标题之间）
    bottomPad += extra * 0.45;

    CGFloat y = top;
    self.cover.frame = CGRectMake((W - coverH) / 2, y, coverH, coverH);
    self.coverLabel.frame = self.cover.bounds;
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

    // 播放控件整体上移约 10pt：主键 72 圆形白底，副键 48 点击区域，间距均匀
    CGFloat cy = y + 36;
    self.playBtn.frame = CGRectMake(W / 2 - 32, cy - 32, 64, 64);
    [self.view viewWithTag:202].frame = CGRectMake(W / 2 - 32 - 20 - 44, cy - 22, 44, 44);
    [self.view viewWithTag:203].frame = CGRectMake(W / 2 + 32 + 20, cy - 22, 44, 44);
    [self.view viewWithTag:201].frame = CGRectMake(W / 2 - 32 - 20 - 44 - 12 - 44, cy - 22, 44, 44);
    [self.view viewWithTag:204].frame = CGRectMake(W / 2 + 32 + 20 + 44 + 12, cy - 22, 44, 44);
    y += 80 + lastGap;

    UIView *toolPill = [self.view viewWithTag:900];
    toolPill.frame = CGRectMake(W / 2 - 156, y - 4, 312, 46);
    UIButton *rate = (UIButton *)[self.view viewWithTag:301];
    rate.frame = CGRectMake(W / 2 - 150, y + 2, 58, 36);
    [self.view viewWithTag:302].frame = CGRectMake(W / 2 - 69, y + 2, 58, 36);
    self.routeView.frame = CGRectMake(W / 2 + 18, y + 2, 44, 36);
    self.queueDim.frame = self.view.bounds;
    [self.view viewWithTag:304].frame = CGRectMake(W / 2 + 106, y + 2, 44, 36);

    CGRect qf = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
    self.queue.frame = qf;
    self.queueBar.frame = CGRectMake(16, qf.origin.y - 44, W - 32, 40);
    self.queueBar.hidden = !self.showQueue;
    CGFloat bw = (W - 32) / 4.0;
    CGFloat bx = 0;
    for (UIButton *b in @[self.sortBtn, self.pickBtn, self.selBtn, self.dlBtn]) {
        b.frame = CGRectMake(bx, 0, bw, 40);
        bx += bw;
    }
}

- (void)tintFromCover {
    UIImage *img = self.cover.image;
    if (!img) return;
    NSString *key = [NSString stringWithFormat:@"%p", img];
    if ([objc_getAssociatedObject(self, "tintKey") isEqual:key]) return;
    objc_setAssociatedObject(self, "tintKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIColor *c = [ADLiquid tintFromImage:img];
    if (c) [ADLiquid recolor:self.view with:c];
}

- (void)sync {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t) return;
    self.titleLabel.text = t.title;
    self.subLabel.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    self.status.text = p.statusText ?: @"";
    [ADUtil cover:self.cover url:p.album.cover];
    // 封面保持裁圆角；投影放在它后面单独一层，避免 clipsToBounds 吃掉阴影
    self.cover.layer.cornerCurve = kCACornerCurveContinuous;
    self.cover.layer.cornerRadius = 26;
    self.cover.clipsToBounds = YES;
    UIView *shadow = [self.view viewWithTag:8802];
    if (!shadow) {
        shadow = [UIView new];
        shadow.tag = 8802;
        shadow.userInteractionEnabled = NO;
        shadow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
        shadow.layer.cornerCurve = kCACornerCurveContinuous;
        shadow.layer.cornerRadius = 26;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        shadow.layer.shadowOpacity = 0.6;
        shadow.layer.shadowRadius = 30;
        shadow.layer.shadowOffset = CGSizeMake(0, 18);
        [self.view insertSubview:shadow belowSubview:self.cover];
    }
    shadow.frame = self.cover.frame;
    [ADLiquid breathe:shadow on:p.isPlaying];
    [ADLiquid breathe:self.cover on:p.isPlaying];
    [self tintFromCover];
    if (!self.coverLabel) {
        self.coverLabel = [ADUtil label:@"PingFangSC-Semibold" size:44 color:[UIColor colorWithWhite:1 alpha:0.28]];
        self.coverLabel.textAlignment = NSTextAlignmentCenter;
        self.coverLabel.tag = 8801;
        [self.cover addSubview:self.coverLabel];
    }
    self.coverLabel.text = p.album.title.length ? [p.album.title substringToIndex:1] : @"听";

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
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightBold]]
                   forState:UIControlStateNormal];
    self.playBtn.imageEdgeInsets = p.isPlaying ? UIEdgeInsetsZero : UIEdgeInsetsMake(0, 3, 0, 0);   // 三角形视觉居中
    UIButton *rateBtn = (UIButton *)[self.view viewWithTag:301];
    [rateBtn setTitle:[NSString stringWithFormat:@"%.2gx", p.rate] forState:UIControlStateNormal];
    UIButton *sleepBtn = (UIButton *)[self.view viewWithTag:302];
    if (p.stopAfterChapter) {
        [sleepBtn setTitle:@"" forState:UIControlStateNormal];
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        // 定时状态已经在下面按钮上显示了,中间只留码率,不再重复
        self.mid.text = mid ?: @"在线播放";
    } else if (p.sleepDeadline > 0) {
        double left = p.sleepDeadline - [NSDate date].timeIntervalSince1970;
        // 开了定时就把按钮直接换成剩余时间（和听见有声一致）
        [sleepBtn setImage:nil forState:UIControlStateNormal];
        NSInteger t = MAX(0, (NSInteger)lround(left));
        NSString *txt = t >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld", (long)(t / 3600), (long)(t % 3600 / 60)]
                                  : [NSString stringWithFormat:@"%ld:%02ld", (long)(t / 60), (long)(t % 60)];
        [sleepBtn setTitle:txt forState:UIControlStateNormal];
        sleepBtn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        sleepBtn.titleLabel.adjustsFontSizeToFitWidth = YES;     // 再长也不截断成 "1:…"
        sleepBtn.titleLabel.minimumScaleFactor = 0.8;
        [sleepBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = mid ?: @"在线播放";
    } else {
        [sleepBtn setTitle:@"" forState:UIControlStateNormal];
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = UIColor.whiteColor;
    }
    BOOL fav = [[ADStore shared] isFavorite:p.album.albumId];
    [self.starBtn setImage:[UIImage systemImageNamed:(fav ? @"star.fill" : @"star") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    self.starBtn.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    if (self.showQueue) {
        [self.queue reloadData];
        // 队列条数变了(后台补齐目录/整队替换):当前集的位置也变了,重新定位一次
        NSInteger now = (NSInteger)ADPlayer.shared.tracks.count;
        if (now != self.queueSeenCount) { self.queueSeenCount = now; [self scrollQueueToCurrent:NO]; }
        else [self clampQueueOffset];
    }
}

- (void)toggleFav {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    [[ADStore shared] toggleFavorite:p.album];
    [self sync];
}

- (void)showMore {
    [ADHaptic tap];
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    NSArray *modes = @[@"顺序播放", @"单集循环", @"整本循环"];
    NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:@"ad_playmode"];
    if (mode < 0 || mode > 2) mode = 0;
    NSArray *opts = @[@"从头播放", @"缓存整本到本机", @"打开专辑（排序 / 选集 / 下载）", @"在此处添加书签", @"书签列表",
                      [NSString stringWithFormat:@"播放模式：%@", modes[mode]],
                      [NSString stringWithFormat:@"跳过片头片尾：%@", ADSkipSummary(p.album)]];
    [ADOptionSheet showIn:self title:p.album.title options:opts destructive:-1 choose:^(NSInteger i) {
        if (i == 0) { [p playAt:0]; return; }
        if (i == 1) { [[ADDownloader shared] addAlbum:p.album tracks:p.tracks]; return; }
        if (i == 3) { [self addBookmark]; return; }
        if (i == 4) {
            ADBookmarksController *bc = [ADBookmarksController new];
            UINavigationController *bn = [[UINavigationController alloc] initWithRootViewController:bc];
            bn.modalPresentationStyle = UIModalPresentationPageSheet;
            [self presentViewController:bn animated:YES completion:nil];
            return;
        }
        if (i == 5) { [self pickPlayMode]; return; }
        if (i == 6) { ADEditSkip(self, p.album); return; }   // 必须在下面的“打开专辑”兜底之前返回
        ADAlbum *album = p.album;
        [self dismissViewControllerAnimated:YES completion:^{
            UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
            UINavigationController *nav = nil;
            if ([root isKindOfClass:ADDockController.class]) {
                UIViewController *sel = ((ADDockController *)root).selectedViewController;
                if ([sel isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)sel;
            } else if ([root isKindOfClass:UINavigationController.class]) {
                nav = (UINavigationController *)root;
            }
            if (!nav) return;
            ADAlbumController *vc = [ADAlbumController new];
            vc.album = album;
            [nav pushViewController:vc animated:YES];
        }];
    }];
}

- (void)pickPlayMode {
    NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:@"ad_playmode"];
    NSArray *names = @[@"顺序播放", @"单集循环", @"整本循环"];
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger k = 0; k < 3; k++) [opts addObject:[NSString stringWithFormat:@"%@%@", k == mode ? @"✓ " : @"", names[k]]];
    [ADOptionSheet showIn:self title:@"播放模式" options:opts destructive:-1 choose:^(NSInteger i) {
        [NSUserDefaults.standardUserDefaults setInteger:i forKey:@"ad_playmode"];
        [ADHaptic success];
    }];
}

- (void)addBookmark {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t || !p.album) return;
    double sec = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    if (isnan(sec) || sec < 0) sec = 0;
    NSString *msg = [NSString stringWithFormat:@"%@ · %@", t.title ?: @"", [ADUtil time:sec]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加书签" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"备注（可不填）"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADStore shared] addBookmark:@{
            @"albumId": p.album.albumId ?: @"", @"albumTitle": p.album.title ?: @"",
            @"cover": p.album.cover ?: @"", @"provider": p.album.provider ?: @"", @"anchor": p.album.anchor ?: @"",
            @"trackId": t.trackId ?: @"", @"trackTitle": t.title ?: @"",
            @"index": @(p.index + p.episodeBase), @"seconds": @(sec),
            @"note": [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
            @"ts": @([NSDate date].timeIntervalSince1970)}];
        [ADHaptic success];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // 播放页收起后让迷你条立刻回来
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
}

- (void)showRateMenu {
    [ADHaptic tap];
    NSArray *rates = @[@0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    NSMutableArray *opts = [NSMutableArray array];
    NSInteger cur = 0;
    for (NSInteger i = 0; i < (NSInteger)rates.count; i++) {
        double v = [rates[i] doubleValue];
        [opts addObject:[NSString stringWithFormat:@"%@%@", v == 1.0 ? @"正常 1x" : [NSString stringWithFormat:@"%gx", v],
                         fabs(v - ADPlayer.shared.rate) < 0.001 ? @"  ✓" : @""]];
        if (fabs(v - ADPlayer.shared.rate) < 0.001) cur = i;
    }
    [ADOptionSheet showIn:self title:@"播放速度" options:opts destructive:-1 choose:^(NSInteger i) {
        ADPlayer.shared.rate = [rates[i] doubleValue];
        [self sync];
    }];
}

- (void)showSleepMenu {
    [ADHaptic tap];
    ADPlayer *pl = ADPlayer.shared;
    BOOL active = (pl.sleepDeadline > 0 || pl.stopAfterChapter);
    NSMutableArray *opts = [NSMutableArray arrayWithObjects:@"15 分钟", @"30 分钟", @"45 分钟", @"60 分钟", @"90 分钟", @"自定义时长…",
                            pl.stopAfterChapter ? @"✓ 播完本集后停止" : @"播完本集后停止", nil];
    NSInteger n = opts.count;
    if (active) [opts addObject:@"取消定时关闭"];
    double now = [NSDate date].timeIntervalSince1970;
    NSArray *mins = @[@15, @30, @45, @60, @90];
    [ADOptionSheet showIn:self title:@"定时关闭" options:opts
              destructive:(active ? n : -1)
                   choose:^(NSInteger i) {
        if (i < 5) {
            ADPlayer.shared.stopAfterChapter = NO;
            ADPlayer.shared.sleepDeadline = now + [mins[i] doubleValue] * 60;
            [self sync];
        } else if (i == 5) {
            [self askCustomSleep];
        } else if (i == 6) {
            ADPlayer.shared.sleepDeadline = 0;
            ADPlayer.shared.stopAfterChapter = !ADPlayer.shared.stopAfterChapter;
            [self sync];
        } else {
            ADPlayer.shared.sleepDeadline = 0;
            ADPlayer.shared.stopAfterChapter = NO;
            [self sync];
        }
    }];
}

- (void)askCustomSleep {
    UIAlertController *c = [UIAlertController alertControllerWithTitle:@"自定义定时" message:@"输入分钟数，也可写 1h30m、90s" preferredStyle:UIAlertControllerStyleAlert];
    [c addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDefault;
        tf.placeholder = @"例如 20";
    }];
    [c addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *y) {
        double sec = [ADUtil parseDuration:c.textFields.firstObject.text];
        if (sec <= 0) return;
        ADPlayer.shared.sleepDeadline = [NSDate date].timeIntervalSince1970 + sec;
        [self sync];
    }]];
    [c addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:c animated:YES completion:nil];
}

- (void)showQueueList {
    ADPlayer *p = ADPlayer.shared;
    if (!p.tracks.count) return;
    [self openQueue];
}

- (void)ctlDown:(UIButton *)b {
    [ADHaptic select];
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        b.transform = CGAffineTransformMakeScale(0.9, 0.9); b.alpha = 0.8;
    } completion:nil];
}
- (void)ctlUp:(UIButton *)b {
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.9 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        b.transform = CGAffineTransformIdentity; b.alpha = 1;
    } completion:nil];
}
- (void)sliderBegin { self.dragging = YES; }
- (void)sliderMoving { self.elapsed.text = [ADUtil time:self.slider.value]; }
- (void)sliderEnd { self.dragging = NO; [ADHaptic soft]; [ADPlayer.shared seekTo:self.slider.value]; }
- (void)toggle { [ADHaptic tap]; [ADPlayer.shared toggle]; [self sync]; }
- (void)prev { [ADHaptic tap]; [ADPlayer.shared prev]; [self sync]; }
- (void)next { [ADHaptic tap]; [ADPlayer.shared next]; [self sync]; }
- (void)back15 { [ADHaptic tap]; [ADPlayer.shared seekBy:-15]; }
- (void)fwd15 { [ADHaptic tap]; [ADPlayer.shared seekBy:15]; }

- (void)cycleRateUnused {
    NSArray *rates = @[@0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    float cur = ADPlayer.shared.rate;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"播放速度" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in rates) {
        BOOL on = fabs([n floatValue] - cur) < 0.001;
        NSString *t = [NSString stringWithFormat:@"%@%@x", on ? @"✓ " : @"", n];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.rate = [n floatValue];
            [self sync];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = [self.view viewWithTag:301];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cycleSleepUnused {
    NSArray *mins = @[@0, @15, @30, @45, @60, @90];
    double now = [NSDate date].timeIntervalSince1970;
    double left = ADPlayer.shared.sleepDeadline > 0 ? (ADPlayer.shared.sleepDeadline - now) / 60.0 : 0;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"睡眠定时" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (ADPlayer.shared.stopAfterChapter) {
        [a addAction:[UIAlertAction actionWithTitle:@"✓ 本集播完停止" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = NO;
            [self sync];
        }]];
    } else {
        [a addAction:[UIAlertAction actionWithTitle:@"本集播完停止" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = YES;
            ADPlayer.shared.sleepDeadline = 0;
            [self sync];
        }]];
    }
    for (NSNumber *n in mins) {
        double m = [n doubleValue];
        BOOL on = (m == 0) ? (ADPlayer.shared.sleepDeadline <= 0 && !ADPlayer.shared.stopAfterChapter) : (fabs(left - m) < 1.5);
        NSString *t = m == 0 ? [NSString stringWithFormat:@"%@关闭定时", on ? @"✓ " : @""]
                             : [NSString stringWithFormat:@"%@%ld 分钟", on ? @"✓ " : @"", (long)m];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = NO;
            ADPlayer.shared.sleepDeadline = m > 0 ? [NSDate date].timeIntervalSince1970 + m * 60 : 0;
            [self sync];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.sleepBtn;
    [self presentViewController:a animated:YES completion:nil];
}

- (UIButton *)barButton:(NSString *)t action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.9] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (NSInteger)queueRowForIndex:(NSInteger)idx {
    NSInteger n = ADPlayer.shared.tracks.count;
    if (n <= 0) return 0;
    if (idx >= n) idx = n - 1;
    return self.queueDesc ? (n - 1 - idx) : idx;
}

- (NSInteger)queueIndexForRow:(NSInteger)row {
    NSInteger n = ADPlayer.shared.tracks.count;
    if (n <= 0) return 0;
    return self.queueDesc ? (n - 1 - row) : row;
}

- (void)toggleQueueSort {
    self.queueDesc = !self.queueDesc;
    [self.sortBtn setTitle:(self.queueDesc ? @"倒序" : @"正序") forState:UIControlStateNormal];
    [self.queue reloadData];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:[self queueRowForIndex:ADPlayer.shared.index] inSection:0];
    if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
        [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (void)showQueuePicker {
    NSInteger total = ADPlayer.shared.tracks.count;
    if (!total) return;
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger start = 0; start < total; start += 60) {
        NSInteger end = MIN(start + 60, total);
        [opts addObject:[NSString stringWithFormat:@"%ld–%ld", (long)start + 1, (long)end]];
    }
    [ADOptionSheet showIn:self title:@"快速选集" options:opts destructive:-1 choose:^(NSInteger i) {
        NSInteger target = MIN(i * 60, MAX(0, (NSInteger)ADPlayer.shared.tracks.count - 1));
        NSIndexPath *ip = [NSIndexPath indexPathForRow:[self queueRowForIndex:target] inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
            [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }];
}

- (void)toggleQueueSelect {
    self.queueSelecting = !self.queueSelecting;
    if (!self.queueSelecting) [self.queueSel removeAllObjects];
    [self.selBtn setTitle:(self.queueSelecting ? @"取消多选" : @"多选") forState:UIControlStateNormal];
    [self updateQueueDl];
    [self.queue reloadData];
}

- (void)updateQueueDl {
    if (self.queueSelecting) {
        [self.dlBtn setTitle:[NSString stringWithFormat:@"缓存所选(%ld)", (long)self.queueSel.count] forState:UIControlStateNormal];
    } else {
        [self.dlBtn setTitle:@"缓存整本" forState:UIControlStateNormal];
    }
}

- (void)queueDownload {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    if (self.queueSelecting) {
        if (!self.queueSel.count) return;
        NSMutableArray *arr = [NSMutableArray array];
        for (ADTrack *t in p.tracks) if ([self.queueSel containsObject:t.trackId]) [arr addObject:t];
        [[ADDownloader shared] addTracks:p.album tracks:arr];
        self.queueSelecting = NO;
        [self.queueSel removeAllObjects];
        [self.selBtn setTitle:@"多选" forState:UIControlStateNormal];
        [self updateQueueDl];
        [self.queue reloadData];
        UIImpactFeedbackGenerator *g = [UIImpactFeedbackGenerator new];
        [g impactOccurred];
        return;
    }
    [[ADDownloader shared] addAlbum:p.album tracks:p.tracks];
    UIImpactFeedbackGenerator *g = [UIImpactFeedbackGenerator new];
    [g impactOccurred];
}

- (void)closeQueue {
    if (!self.showQueue) return;
    self.showQueue = NO;
    self.queueDim.hidden = YES;
    [UIView animateWithDuration:0.22 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        self.queue.frame = CGRectMake(16, H, W - 32, 300);
        self.queueBar.frame = CGRectMake(16, H, W - 32, 40);
        self.queueBar.alpha = 0;
    } completion:^(BOOL ok) {
        self.queue.hidden = YES;
        self.queueBar.hidden = YES;
        self.queueBar.alpha = 1;
    }];
}

- (void)openQueue {
    self.showQueue = !self.showQueue;
    self.queue.hidden = !self.showQueue;
    self.queueDim.hidden = !self.showQueue;
    self.queueBar.hidden = !self.showQueue;
    if (self.showQueue) { self.queueSelecting = NO; [self.queueSel removeAllObjects]; [self.selBtn setTitle:@"多选" forState:UIControlStateNormal]; [self updateQueueDl]; }
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        CGRect qf = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
        self.queue.frame = qf;
        self.queueBar.frame = CGRectMake(16, qf.origin.y - 44, W - 32, 40);
    } completion:^(BOOL f) {
        // 面板到位、布局稳定后再定位。以前在动画开始时就滚动,表格高度还没定,滚过头会空出一大块
        if (self.showQueue) [self scrollQueueToCurrent:NO];
    }];
    [self.queue reloadData];
    if (self.showQueue) {
        self.queueSeenCount = (NSInteger)ADPlayer.shared.tracks.count;
        [ADPlayer.shared ensureFullQueue];      // 打开队列时顺手把后面的目录补齐
    }
}

// 把当前播放的那一集滚到队列正中;条数不够铺满时回到顶部,绝不留空白
- (void)scrollQueueToCurrent:(BOOL)animated {
    NSInteger n = [self.queue numberOfRowsInSection:0];
    if (n <= 0) return;
    [self.queue layoutIfNeeded];
    NSInteger row = [self queueRowForIndex:ADPlayer.shared.index];
    if (row < 0 || row >= n) row = 0;
    [self.queue scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:animated];
    [self clampQueueOffset];
}

// 内容比面板矮,或偏移超出范围时拉回合法区间,上方不会出现空白
- (void)clampQueueOffset {
    UIScrollView *q = self.queue;
    CGFloat minY = -q.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, q.contentSize.height - q.bounds.size.height + q.adjustedContentInset.bottom);
    CGFloat y = q.contentOffset.y;
    if (y < minY) y = minY;
    if (y > maxY) y = maxY;
    if (fabs(y - q.contentOffset.y) > 0.5) q.contentOffset = CGPointMake(0, y);
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return ADPlayer.shared.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"q";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    NSInteger idx = [self queueIndexForRow:ip.row];
    ADTrack *tr = ADPlayer.shared.tracks[idx];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    BOOL done = [[ADStore shared] isDone:tr.trackId];
    c.textLabel.text = done ? [NSString stringWithFormat:@"✓ %@", tr.title] : tr.title;
    c.textLabel.textColor = (idx == ADPlayer.shared.index) ? [ADUtil brand]
                          : (done ? [UIColor colorWithWhite:1 alpha:0.55] : UIColor.whiteColor);
    if (self.queueSelecting) {
        c.accessoryType = [self.queueSel containsObject:tr.trackId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        c.tintColor = [ADUtil brand];
    } else {
        c.accessoryType = UITableViewCellAccessoryNone;
    }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger idx = [self queueIndexForRow:ip.row];
    if (self.queueSelecting) {
        ADTrack *tr = ADPlayer.shared.tracks[idx];
        if ([self.queueSel containsObject:tr.trackId]) [self.queueSel removeObject:tr.trackId];
        else [self.queueSel addObject:tr.trackId];
        [self updateQueueDl];
        [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    [ADPlayer.shared playAt:idx];
    [self closeQueue];
    [self sync];
}
@end
