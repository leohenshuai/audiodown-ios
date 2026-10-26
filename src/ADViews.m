#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

// ───────────── 卡片：继续收听 ─────────────
@interface ADContinueCard : UIView
@property (nonatomic, strong) ADAlbum *album;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, copy) void (^onPlay)(void);
@property (nonatomic, copy) void (^onMore)(void);
@property (nonatomic, copy) void (^onMenu)(void);
- (instancetype)initWithFrame:(CGRect)f album:(ADAlbum *)a info:(NSDictionary *)info;
- (void)refresh;
@end

@implementation ADContinueCard {
    UIImageView *_bg, *_cover;
    UILabel *_ep, *_title, *_chapter, *_meta, *_time;
    UIButton *_play;
    UIView *_track, *_fill;
}

- (instancetype)initWithFrame:(CGRect)f album:(ADAlbum *)a info:(NSDictionary *)info {
    if ((self = [super initWithFrame:f])) {
        _album = a; _info = info;
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
        self.layer.cornerRadius = 22;
        self.clipsToBounds = YES;

        _bg = [[UIImageView alloc] initWithFrame:self.bounds];
        _bg.contentMode = UIViewContentModeScaleAspectFill;
        _bg.clipsToBounds = YES;
        _bg.alpha = 0.55;
        [self addSubview:_bg];
        UIView *shade = [[UIView alloc] initWithFrame:self.bounds];
        shade.backgroundColor = [UIColor colorWithRed:0.11 green:0.06 blue:0.04 alpha:0.82];
        [self addSubview:shade];

        CGFloat w = f.size.width;
        CGFloat cw = 104;
        _cover = [[UIImageView alloc] initWithFrame:CGRectMake((w - cw) / 2, 14, cw, cw)];
        _cover.layer.cornerRadius = 14;
        _cover.clipsToBounds = YES;
        [self addSubview:_cover];

        _ep = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.6]];
        _ep.frame = CGRectMake(12, 124, w - 24, 15);
        _title = [ADUtil label:@"PingFangSC-Semibold" size:17 color:UIColor.whiteColor];
        _title.frame = CGRectMake(12, 142, w - 24, 40);
        _title.numberOfLines = 2;
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _chapter = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.72]];
        _chapter.frame = CGRectMake(12, 184, w - 24, 17);
        _chapter.font = [UIFont systemFontOfSize:12];
        _chapter.lineBreakMode = NSLineBreakByTruncatingTail;
        _meta = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
        _meta.frame = CGRectMake(12, 203, w - 24, 15);
        [self addSubview:_ep]; [self addSubview:_title]; [self addSubview:_chapter]; [self addSubview:_meta];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLong:)];
        lp.minimumPressDuration = 0.45;
        [self addGestureRecognizer:lp];

        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(12, f.size.height - 44, w - 62, 32)];
        pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        pill.layer.cornerRadius = 16;
        [self addSubview:pill];

        _play = [UIButton buttonWithType:UIButtonTypeSystem];
        _play.frame = CGRectMake(4, 0, 32, 32);
        _play.tintColor = UIColor.whiteColor;
        [_play setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
        [_play addTarget:self action:@selector(tapPlay) forControlEvents:UIControlEventTouchUpInside];
        [pill addSubview:_play];

        _track = [[UIView alloc] initWithFrame:CGRectMake(38, 14, w - 62 - 38 - 54, 4)];
        _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        _track.layer.cornerRadius = 2;
        [pill addSubview:_track];
        _fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 4)];
        _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
        _fill.layer.cornerRadius = 2;
        [_track addSubview:_fill];

        _time = [ADUtil label:@"PingFangSC-Medium" size:13 color:UIColor.whiteColor];
        _time.frame = CGRectMake(w - 62 - 50, 7, 46, 18);
        _time.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _time.textAlignment = NSTextAlignmentRight;
        [pill addSubview:_time];

        UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
        more.frame = CGRectMake(w - 46, f.size.height - 44, 40, 32);
        [more setTitle:@"···" forState:UIControlStateNormal];
        [more setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
        more.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        [more addTarget:self action:@selector(tapMore) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:more];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapCard)];
        [self addGestureRecognizer:tap];

        [self refresh];
    }
    return self;
}

- (void)refresh {
    [ADUtil cover:_cover url:_album.cover];
    _bg.image = _cover.image;
    NSInteger idx = [_info[@"index"] integerValue];
    _ep.text = [NSString stringWithFormat:@"第 %ld 集 · %@", (long)idx + 1, _album.anchor.length ? _album.anchor : @""];
    _title.text = _album.title;
    NSString *chapter = _info[@"title"];
    _chapter.text = chapter.length ? chapter : @"";
    NSInteger left = MAX(0, _album.trackCount - idx - 1);
    _meta.text = [NSString stringWithFormat:@"剩余 %ld 集", (long)left];
    double sec = [_info[@"seconds"] doubleValue];
    double dur = [_info[@"duration"] doubleValue];
    _time.text = [NSString stringWithFormat:@"%@", [ADUtil time:sec]];
    CGFloat full = _track.bounds.size.width;
    CGFloat p = (dur > 0) ? (sec / dur) : 0;
    _fill.frame = CGRectMake(0, 0, MAX(4, full * MIN(1, p)), 4);

    BOOL playing = ADPlayer.shared.isPlaying && ADPlayer.shared.album && [ADPlayer.shared.album.albumId isEqualToString:_album.albumId];
    [_play setImage:[UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
}

- (void)handleLong:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        [ADHaptic heavy];
        [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.96, 0.96); }
                         completion:^(BOOL f) {
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:0 animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
        }];
        if (self.onMenu) self.onMenu();
    }
}
- (void)tapPlay { [ADHaptic tap]; if (self.onPlay) self.onPlay(); }
- (void)tapMore { [ADHaptic tap]; if (self.onMore) self.onMore(); }
- (void)tapCard {
    [ADHaptic tap];
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────── 小卡片 ─────────────
@interface ADSmallCard : UIView
@property (nonatomic, strong) ADAlbum *album;
- (instancetype)initWithFrame:(CGRect)f album:(ADAlbum *)a;
@end

@implementation ADSmallCard {
    UIImageView *_cover;
    UILabel *_title;
}
- (instancetype)initWithFrame:(CGRect)f album:(ADAlbum *)a {
    if ((self = [super initWithFrame:f])) {
        _cover = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, f.size.width)];
        _cover.layer.cornerRadius = 12;
        _cover.clipsToBounds = YES;
        [ADUtil cover:_cover url:a.cover];
        [self addSubview:_cover];
        _title = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.85]];
        _title.frame = CGRectMake(0, f.size.width + 6, f.size.width, 32);
        _title.numberOfLines = 2;
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _title.text = a.title;
        [self addSubview:_title];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)];
        [self addGestureRecognizer:t];
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _cover.layer.shadowColor = UIColor.blackColor.CGColor;
        _cover.layer.shadowOpacity = 0.35;
        _cover.layer.shadowRadius = 14;
        _cover.layer.shadowOffset = CGSizeMake(0, 8);
        self.album = a;
    }
    return self;
}
- (void)open {
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UINavigationController *nav = nil;
    UIViewController *vc = win.rootViewController;
    if ([vc isKindOfClass:ADDockController.class]) vc = ((ADDockController *)vc).selectedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)vc;
    ADAlbumController *a = [ADAlbumController new];
    a.album = self.album;
    [nav pushViewController:a animated:YES];
}
@end

// ───────────── 迷你播放条 ─────────────
@interface ADMiniBar : UIView
+ (instancetype)shared;
- (void)refresh;
@end

@implementation ADMiniBar {
    UIImageView *_cover;
    UILabel *_title, *_sub;
    UIButton *_btn, *_back, *_fold;
    UIView *_track, *_fill;
    BOOL _collapsed, _spinPaused, _skipping;
    NSTimer *_collapseTimer;
    UIView *_hole;
    UIView *_disc;          // 圆形裁剪容器：收起时是正圆，里面的封面负责旋转
}
+ (instancetype)shared {
    static ADMiniBar *m; static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [[ADMiniBar alloc] initWithFrame:CGRectMake(0, 0, 320, 58)];
        [m build];
    });
    return m;
}
- (void)build {
    [ADLiquid glass:self radius:16];
    [ADLiquid float:self];
    self.layer.shadowOpacity = 0.28;
    _disc = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 42, 42)];
    _disc.clipsToBounds = YES;
    _disc.layer.cornerRadius = 8;
    if (@available(iOS 13.0, *)) _disc.layer.cornerCurve = kCACornerCurveContinuous;
    _cover = [[UIImageView alloc] initWithFrame:_disc.bounds];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    [_disc addSubview:_cover];
    _title = [ADUtil label:@"PingFangSC-Semibold" size:14 color:UIColor.whiteColor];
    _sub = [ADUtil label:nil size:11 color:[UIColor colorWithWhite:1 alpha:0.55]];
    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn.tintColor = UIColor.whiteColor;
    [_btn addTarget:self action:@selector(tapPlay) forControlEvents:UIControlEventTouchUpInside];
    _back = [UIButton buttonWithType:UIButtonTypeSystem];
    _back.tintColor = UIColor.whiteColor;
    [_back setImage:[UIImage systemImageNamed:@"gobackward.15" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [_back addTarget:self action:@selector(tapBack) forControlEvents:UIControlEventTouchUpInside];
    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    _fill = [UIView new];
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.75];
    [self addSubview:_disc]; [self addSubview:_title]; [self addSubview:_sub];
    _fold = [UIButton buttonWithType:UIButtonTypeSystem];
    _fold.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    [_fold setImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [_fold addTarget:self action:@selector(foldNow) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_btn]; [self addSubview:_back]; [self addSubview:_fold]; [self addSubview:_track]; [self addSubview:_fill];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBar)]];

    // 下滑 = 立刻收起，上滑 = 展开
    UISwipeGestureRecognizer *swDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(foldNow)];
    swDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self addGestureRecognizer:swDown];
    UISwipeGestureRecognizer *swUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(unfoldNow)];
    swUp.direction = UISwipeGestureRecognizerDirectionUp;
    [self addGestureRecognizer:swUp];
    // 左滑 = 下一集，右滑 = 上一集
    UISwipeGestureRecognizer *swL = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeNext)];
    swL.direction = UISwipeGestureRecognizerDirectionLeft;
    [self addGestureRecognizer:swL];
    UISwipeGestureRecognizer *swR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipePrev)];
    swR.direction = UISwipeGestureRecognizerDirectionRight;
    [self addGestureRecognizer:swR];
    // 收起成圆球后像唱片：中间一个小孔
    _hole = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 11, 11)];
    _hole.backgroundColor = [UIColor colorWithRed:0.08 green:0.06 blue:0.05 alpha:0.95];
    _hole.layer.cornerRadius = 5.5;
    _hole.layer.borderWidth = 1.2;
    _hole.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    _hole.userInteractionEnabled = NO;
    _hole.hidden = YES;
    [self addSubview:_hole];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerChanged" object:nil];
}

- (void)swipeSkip:(BOOL)next {
    if (_collapsed || _skipping) return;
    ADPlayer *p = ADPlayer.shared;
    NSInteger i = p.index, n = (NSInteger)p.tracks.count;
    BOOL ok = next ? (i + 1 < n) : (i > 0);
    CGFloat dx = next ? -28 : 28;
    if (!ok) {   // 到头了：橡皮筋回弹 + 警示触感
        [ADHaptic warning];
        [UIView animateWithDuration:0.12 animations:^{ for (UIView *v in @[_disc, _title, _sub]) v.transform = CGAffineTransformMakeTranslation(-dx * 0.35, 0); }
                         completion:^(BOOL f) {
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.8 options:0 animations:^{ for (UIView *v in @[_disc, _title, _sub]) v.transform = CGAffineTransformIdentity; } completion:nil];
        }];
        return;
    }
    _skipping = YES;
    [ADHaptic select];
    [_collapseTimer invalidate]; _collapseTimer = nil;
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UIView *v in @[_title, _sub, _disc]) { v.transform = CGAffineTransformMakeTranslation(dx, 0); v.alpha = 0; }
    } completion:^(BOOL f) {
        if (next) [p next]; else [p playAt:i - 1];
        for (UIView *v in @[_title, _sub, _disc]) v.transform = CGAffineTransformMakeTranslation(-dx, 0);
        [UIView animateWithDuration:0.38 delay:0.05 usingSpringWithDamping:0.78 initialSpringVelocity:0.4 options:0 animations:^{
            for (UIView *v in @[_title, _sub, _disc]) { v.transform = CGAffineTransformIdentity; v.alpha = 1; }
        } completion:^(BOOL f2) { _skipping = NO; }];
        [self scheduleCollapse];
    }];
}
- (void)swipeNext { [self swipeSkip:YES]; }
- (void)swipePrev { [self swipeSkip:NO]; }

// 收起成圆球后：播放时封面缓慢旋转，暂停时停在当前角度
// 旋转作用在 _cover(位于 _disc 内),外层 _disc 负责圆形裁剪,所以封面不会超出圆
- (void)updateSpin {
    CALayer *L = _cover.layer;
    BOOL playing = ADPlayer.shared.isPlaying;
    if (!_collapsed) {
        if ([L animationForKey:@"spin"]) [L removeAnimationForKey:@"spin"];
        L.speed = 1; L.timeOffset = 0; L.beginTime = 0; _spinPaused = NO;
        return;
    }
    if (![L animationForKey:@"spin"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @0; a.toValue = @(M_PI * 2); a.duration = 9; a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        L.speed = 1; L.timeOffset = 0; L.beginTime = 0; _spinPaused = NO;
        [L addAnimation:a forKey:@"spin"];
    }
    if (playing && _spinPaused) {
        CFTimeInterval paused = L.timeOffset;
        L.speed = 1; L.timeOffset = 0; L.beginTime = 0;
        L.beginTime = [L convertTime:CACurrentMediaTime() fromLayer:nil] - paused;
        _spinPaused = NO;
    } else if (!playing && !_spinPaused) {
        L.timeOffset = [L convertTime:CACurrentMediaTime() fromLayer:nil];
        L.speed = 0; _spinPaused = YES;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (_collapsed) {
        CGFloat d = h - 14;
        _disc.frame = CGRectMake((w - d) / 2, (h - d) / 2, d, d);
        _disc.layer.cornerRadius = d / 2;
        _disc.layer.borderWidth = 1.5;
        _disc.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
        // 封面放大成能完全盖住圆的正方形(√2 倍),旋转时四角也不会漏出来;圆形裁剪由 _disc 负责
        CGFloat big = ceil(d * 1.42);
        _cover.bounds = CGRectMake(0, 0, big, big);
        _cover.center = CGPointMake(d / 2, d / 2);
        _hole.hidden = NO;
        _hole.center = CGPointMake(w / 2, h / 2);
        _title.hidden = YES;
        _sub.hidden = YES;
        _btn.hidden = YES;
        _back.hidden = YES;
        _fold.hidden = YES;
        _track.hidden = YES;
        _fill.hidden = YES;
        return;
    }
    _title.hidden = NO;
    _sub.hidden = NO;
    _btn.hidden = NO;
    _back.hidden = NO;
    _fold.hidden = NO;
    _track.hidden = NO;
    _fill.hidden = NO;
    _disc.layer.cornerRadius = 8;
    _disc.layer.borderWidth = 0;
    _hole.hidden = YES;
    _disc.frame = CGRectMake(8, (h - 42) / 2, 42, 42);
    _cover.transform = CGAffineTransformIdentity;
    _cover.frame = _disc.bounds;
    _fold.frame = CGRectMake(w - 32, (h - 36) / 2, 30, 36);
    _btn.frame = CGRectMake(w - 66, (h - 36) / 2, 34, 36);
    _back.frame = CGRectMake(w - 100, (h - 36) / 2, 32, 36);
    _title.frame = CGRectMake(58, 10, w - 166, 18);
    _sub.frame = CGRectMake(58, 29, w - 166, 15);
    _track.frame = CGRectMake(0, h - 2, w, 2);
    double cur = ADPlayer.shared.player ? CMTimeGetSeconds(ADPlayer.shared.player.currentTime) : 0;
    double dur = ADPlayer.shared.player.currentItem ? CMTimeGetSeconds(ADPlayer.shared.player.currentItem.duration) : 0;
    _fill.frame = CGRectMake(0, h - 2, (dur > 0 && !isnan(dur)) ? w * cur / dur : 0, 2);
}

// 位置：展开时贴在标签栏上方，收缩时缩成右边缘的小圆球
- (void)applyFrame:(BOOL)animated {
    UIWindow *key = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *root = key.rootViewController;
    CGRect target = self.frame;
    if ([root isKindOfClass:ADDockController.class]) {
        UIViewController *tab = root;
        if (self.superview != tab.view) {
            [tab.view addSubview:self];
        }
        [tab.view bringSubviewToFront:ADNavDock.shared];
        CGFloat W = tab.view.bounds.size.width;
        CGFloat h = _collapsed ? 50 : 58;
        CGFloat w = _collapsed ? 50 : W - 16;
        CGFloat bottom = tab.view.bounds.size.height - tab.view.safeAreaInsets.bottom - 8 - h;
        ADNavDock *dock = [ADNavDock shared];
        CGFloat aboveBar = dock.dockVisible ? (dock.topY - 10 - h) : 1e9;
        CGFloat y = MIN(bottom, aboveBar) + (58 - h) / 2.0;
        CGFloat x = _collapsed ? (W - w - 6) : 8;
        target = CGRectMake(x, y, w, h);
    } else if (!self.superview && key) {
        [key addSubview:self];
    }
    __weak typeof(self) wself = self;
    void (^apply)(void) = ^{
        __strong typeof(wself) me = wself; if (!me) return;
        me.frame = target;
        [ADLiquid corner:(me->_collapsed ? 25 : 16) on:me];
        me.clipsToBounds = NO;
        me.layer.shadowColor = UIColor.blackColor.CGColor;
        me.layer.shadowOpacity = me->_collapsed ? 0.45 : 0.30;
        me.layer.shadowRadius = me->_collapsed ? 14 : 24;
        me.layer.shadowOffset = CGSizeMake(0, me->_collapsed ? 5 : 12);
    };
    if (CGRectEqualToRect(self.frame, target)) { apply(); return; }
    if (animated) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.3
                            options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];
    } else {
        apply();
    }
    [self setNeedsLayout];
}

- (void)scheduleCollapse {
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    if (_collapsed) return;
    _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:8.0 target:self selector:@selector(collapseNow) userInfo:nil repeats:NO];
}

- (void)collapseNow {
    _collapseTimer = nil;
    if (_collapsed || !ADPlayer.shared.current) return;
    _collapsed = YES;
    [self applyFrame:YES];
    [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }];
    [self updateSpin];
}

- (void)expandNow {
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    if (!_collapsed) return;
    _collapsed = NO;
    [self applyFrame:YES];
    [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }];
    [self updateSpin];
    [self scheduleCollapse];
}

- (void)refresh {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;

    // 统一挂在标签栏控制器上：任何页面都能实时看到
    UIWindow *key = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *root = key.rootViewController;
    BOOL playerOpen = [root.presentedViewController isKindOfClass:ADPlayerController.class];
    if (!t || playerOpen) {
        if (!self.hidden) self.hidden = YES;
        [_collapseTimer invalidate];
        _collapseTimer = nil;
        return;
    }
    if (self.hidden) {
        self.hidden = NO;
        if (!self.superview) {
            self.alpha = 0;
            [UIView animateWithDuration:0.22 animations:^{ self.alpha = 1; }];
        }
    }

    _title.text = t.title;
    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    _sub.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    [ADUtil cover:_cover url:p.album.cover];
    [_btn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    CGFloat full = self.bounds.size.width;
    _fill.frame = CGRectMake(0, self.bounds.size.height - 2, (dur > 0 && !isnan(dur)) ? full * cur / dur : 0, 2);

    // 不管播放还是暂停，闲置 8 秒都会收缩
    if (!_collapsed && !_collapseTimer) [self scheduleCollapse];
    [self applyFrame:NO];
    [self updateSpin];
}

- (void)foldNow {
    [ADHaptic select];
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    if (_collapsed || !ADPlayer.shared.current) return;
    _collapsed = YES;
    [self applyFrame:YES];
    [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }];
    [self updateSpin];
}

- (void)unfoldNow {
    if (_collapsed) [self expandNow];
}

- (void)tapPlay {
    [ADHaptic tap];
    if (_collapsed) { [self expandNow]; return; }
    [ADPlayer.shared toggle];
    [self refresh];
    [self scheduleCollapse];
}

- (void)tapBack {
    [ADHaptic tap];
    if (_collapsed) { [self expandNow]; return; }
    [ADPlayer.shared seekBy:-15];
    [self scheduleCollapse];
}

- (void)tapBar {
    [ADHaptic tap];
    if (_collapsed) { [self expandNow]; return; }
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────── 首页 ─────────────
@interface ADDiscoverController () <UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *cats;
@property (nonatomic, assign) BOOL catsOpen;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@property (nonatomic, assign) BOOL needsSetup;
@property (nonatomic, strong) NSMutableArray<ADContinueCard *> *cards;
@end

@implementation ADDiscoverController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.navigationController.navigationBar.hidden = YES;

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.delegate = self;
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    self.refresh = [UIRefreshControl new];
    self.refresh.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.refresh addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10, *)) self.scroll.refreshControl = self.refresh;
    [self.view addSubview:self.scroll];

    self.hint = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spin.color = UIColor.whiteColor;
    [self.view addSubview:self.hint];
    [self.view addSubview:self.spin];
    self.cards = [NSMutableArray array];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadCards) name:@"ADContinueChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshCards) name:@"ADPlayerTick" object:nil];

    [self load];
    self.needsSetup = ([ADConfig shared].token.length == 0);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
    [self build];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [ADMiniBar.shared refresh];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.needsSetup) {
        self.needsSetup = NO;
        UIViewController *root = UIApplication.sharedApplication.windows.firstObject.rootViewController;
        if ([root isKindOfClass:ADDockController.class]) ((ADDockController *)root).selectedIndex = 3;
    }
}

- (void)reloadCards { [self build]; }
- (void)refreshCards { for (ADContinueCard *c in self.cards) [c refresh]; }

- (void)load {
    if (!self.sections.count) [self.spin startAnimating];
    __weak typeof(self) w = self;
    [[ADApi shared] discover:^(NSArray<NSDictionary *> *sections, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        [self.spin stopAnimating];
        [self.refresh endRefreshing];
        if (sections.count) {
            self.sections = sections;
            [self build];
        }
        self.hint.text = sections.count ? @"" : (err ?: @"没有内容");
    }];
    [[ADApi shared] categories:^(NSArray<NSDictionary *> *list, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (list.count) {
            NSArray *sorted = [list sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [@([a[@"orderNum"] integerValue]) compare:@([b[@"orderNum"] integerValue])];
            }];
            if (![sorted isEqualToArray:self.cats ?: @[]]) { self.cats = sorted; [self build]; }
        }
    }];
}

// 首页分类区:两行图标格,默认显示 8 个,"全部"展开
- (CGFloat)buildCats:(CGFloat)y width:(CGFloat)W {
    NSArray *cats = self.cats;
    if (!cats.count) {
        // 接口还没回来时用固定分类兜底,避免页面跳动
        NSMutableArray *fb = [NSMutableArray array];
        for (NSString *t in @[@"有声书", @"儿童", @"相声评书", @"音乐", @"历史", @"悬疑", @"外语", @"个人成长"]) [fb addObject:@{@"title": t}];
        cats = fb;
    }
    UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:24 color:UIColor.whiteColor];
    t.frame = CGRectMake(16, y, W - 120, 32);
    t.text = @"分类";
    [self.scroll addSubview:t];
    if (cats.count > 8) {
        UIButton *all = [UIButton buttonWithType:UIButtonTypeSystem];
        all.frame = CGRectMake(W - 16 - 80, y + 2, 80, 28);
        all.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        all.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        all.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
        [all setTitle:(self.catsOpen ? @"收起 ▴" : [NSString stringWithFormat:@"全部 %lu ▾", (unsigned long)cats.count]) forState:UIControlStateNormal];
        [all addTarget:self action:@selector(toggleCats) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:all];
    }
    y += 42;
    NSInteger show = self.catsOpen ? cats.count : MIN(8, (NSInteger)cats.count);
    NSInteger cols = 4;
    CGFloat gap = 10, cw = floor((W - 32 - gap * (cols - 1)) / cols), ch = 78;
    for (NSInteger i = 0; i < show; i++) {
        NSString *title = cats[i][@"title"];
        NSInteger r = i / cols, c = i % cols;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(16 + c * (cw + gap), y + r * (ch + gap), cw, ch);
        [ADLiquid glassButton:b radius:16];
        b.tag = 7000 + i;
        b.accessibilityLabel = title;
        UIColor *col = [ADCategoryController colorFor:title];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectMake((cw - 34) / 2, 11, 34, 34)];
        bg.userInteractionEnabled = NO;
        bg.layer.cornerRadius = 10;
        if (@available(iOS 13.0, *)) bg.layer.cornerCurve = kCACornerCurveContinuous;
        bg.backgroundColor = [col colorWithAlphaComponent:0.22];
        UIImageView *ic = [[UIImageView alloc] initWithFrame:bg.bounds];
        ic.contentMode = UIViewContentModeCenter;
        ic.tintColor = col;
        ic.image = [UIImage systemImageNamed:[ADCategoryController iconFor:title] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]];
        [bg addSubview:ic];
        [b addSubview:bg];
        UILabel *l = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.86]];
        l.textAlignment = NSTextAlignmentCenter;
        l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.8;
        l.frame = CGRectMake(4, 51, cw - 8, 18);
        l.text = title;
        [b addSubview:l];
        [b addTarget:self action:@selector(openCat:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
    }
    NSInteger rows = (show + cols - 1) / cols;
    return y + rows * (ch + gap) - gap + 24;
}

- (void)toggleCats {
    [ADHaptic select];
    self.catsOpen = !self.catsOpen;
    CGPoint off = self.scroll.contentOffset;
    [self build];
    self.scroll.contentOffset = off;
}

- (void)openCat:(UIButton *)b {
    [ADHaptic tap];
    ADCategoryController *vc = [ADCategoryController new];
    vc.catTitle = b.accessibilityLabel;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)build {
    for (UIView *v in self.scroll.subviews) [v removeFromSuperview];
    [self.cards removeAllObjects];
    CGFloat W = self.view.bounds.size.width;
    CGFloat safeTop = MAX(self.view.safeAreaInsets.top, 47);
    CGFloat y = safeTop;

    // 顶部标题
    UILabel *logo = [ADUtil label:@"PingFangSC-Semibold" size:34 color:UIColor.whiteColor];
    logo.frame = CGRectMake(16, y + 6, 130, 40);
    logo.text = @"阅听";
    [self.scroll addSubview:logo];
    UILabel *sub = [ADUtil label:nil size:16 color:[UIColor colorWithWhite:1 alpha:0.4]];
    sub.frame = CGRectMake(104, y + 18, 120, 20);
    sub.text = @"";
    [self.scroll addSubview:sub];

    NSArray *icons = @[@"clock.arrow.circlepath"];
    NSArray *sels = @[@"openHistory"];
    for (NSInteger i = 0; i < 1; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(W - 16 - 44 - i * 56, y + 4, 44, 44);
        [ADLiquid glassButton:b radius:22];
        b.tintColor = (i == 1) ? [ADUtil brand] : UIColor.whiteColor;
        [b setImage:[UIImage systemImageNamed:icons[i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
        SEL sel = NSSelectorFromString(sels[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
    }
    y += 62;

    UIButton *searchPill = [UIButton buttonWithType:UIButtonTypeCustom];
    searchPill.frame = CGRectMake(16, y, W - 32, 44);
    [ADLiquid glassButton:searchPill radius:22];
    [searchPill addTarget:self action:@selector(gotoSearch) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *mag = [[UIImageView alloc] initWithFrame:CGRectMake(16, 12, 20, 20)];
    mag.image = [UIImage systemImageNamed:@"magnifyingglass"
                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]];
    mag.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
    [searchPill addSubview:mag];
    UILabel *ph = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.42]];
    ph.text = @"搜书名、作者或主播";
    ph.frame = CGRectMake(46, 12, W - 32 - 80, 20);
    [searchPill addSubview:ph];
    [self.scroll addSubview:searchPill];
    y += 44 + 18;
    [ADLiquid rise:searchPill delay:0.02];

    // 分类
    y = [self buildCats:y width:W];

    // 继续收听
    NSArray<ADAlbum *> *hist = [ADStore shared].history;
    NSMutableArray *items = [NSMutableArray array];
    for (ADAlbum *a in hist) {
        NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
        if (info) [items addObject:@[a, info]];
        if (items.count >= 8) break;
    }
    if (items.count) {
        UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:24 color:UIColor.whiteColor];
        t.frame = CGRectMake(16, y, W - 32, 32);
        t.text = @"继续收听";
        [self.scroll addSubview:t];
        y += 40;

        CGFloat cardW = W * 0.50, cardH = 258;
        UIScrollView *hs = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, W, cardH)];
        hs.showsHorizontalScrollIndicator = NO;
        hs.contentSize = CGSizeMake(16 + items.count * (cardW + 14), cardH);
        for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
            ADAlbum *a = items[i][0];
            NSDictionary *info = items[i][1];
            ADContinueCard *c = [[ADContinueCard alloc] initWithFrame:CGRectMake(16 + i * (cardW + 14), 0, cardW, cardH) album:a info:info];
            __weak typeof(self) w = self;
            c.onPlay = ^{ [w playCard:a]; };
            c.onMore = ^{ [w moreCard:a]; };
            c.onMenu = ^{ [w menuCard:a]; };
            [hs addSubview:c];
            [self.cards addObject:c];
        }
        [self.scroll addSubview:hs];
        y += cardH + 22;
    }

    // 推荐内容面板
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0)];
    panel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.035];
    panel.layer.borderWidth = 0.65;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.09].CGColor;
    panel.layer.cornerRadius = 20;
    panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.scroll addSubview:panel];
    CGFloat py = 24;
    UILabel *rt = [ADUtil label:@"PingFangSC-Semibold" size:24 color:UIColor.whiteColor];
    rt.frame = CGRectMake(16, py, W - 32, 32);
    rt.text = @"推荐内容";
    [panel addSubview:rt];
    py += 44;

    // 推荐：两行横向
    NSMutableArray<ADAlbum *> *rec = [NSMutableArray array];
    for (NSDictionary *sec in self.sections) {
        NSArray *its = sec[@"items"];
        if (![its isKindOfClass:NSArray.class]) continue;
        for (id o in its) { ADAlbum *a = [ADAlbum fromJSON:o]; if (a) [rec addObject:a]; if (rec.count >= 24) break; }
        if (rec.count >= 24) break;
    }
    if (rec.count) {
        CGFloat cw = 118, gap = 12;
        NSInteger perRow = 2;
        NSUInteger rows = (rec.count + 2) / 3;   // 每列 2 个，横向滚动
        NSInteger cols = (NSInteger)(rec.count + perRow - 1) / perRow;
        CGFloat hsH = perRow * (cw + 34) + 4;
        UIScrollView *hs = [[UIScrollView alloc] initWithFrame:CGRectMake(0, py, W, hsH)];
        hs.showsHorizontalScrollIndicator = NO;
        hs.contentSize = CGSizeMake(16 + cols * (cw + gap), hsH);
        for (NSInteger i = 0; i < (NSInteger)rec.count; i++) {
            NSInteger col = i / perRow, row = i % perRow;
            ADSmallCard *c = [[ADSmallCard alloc] initWithFrame:CGRectMake(16 + col * (cw + gap), row * (cw + 34), cw, cw + 34) album:rec[i]];
            [hs addSubview:c];
        }
        [panel addSubview:hs];
        py += hsH + 16;
        (void)rows;
    }

    // 接口板块
    for (NSDictionary *sec in self.sections) {
        NSArray *its = sec[@"items"];
        if (![its isKindOfClass:NSArray.class] || !its.count) continue;
        UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:19 color:UIColor.whiteColor];
        t.frame = CGRectMake(16, py, W - 32, 26);
        t.text = sec[@"title"] ?: @"推荐";
        [panel addSubview:t];
        py += 34;

        CGFloat cw = 104, gap = 10;
        UIScrollView *hs = [[UIScrollView alloc] initWithFrame:CGRectMake(0, py, W, cw + 34)];
        hs.showsHorizontalScrollIndicator = NO;
        hs.contentSize = CGSizeMake(16 + its.count * (cw + gap), cw + 34);
        for (NSInteger i = 0; i < (NSInteger)its.count; i++) {
            ADAlbum *a = [ADAlbum fromJSON:its[i]];
            if (!a) continue;
            ADSmallCard *c = [[ADSmallCard alloc] initWithFrame:CGRectMake(16 + i * (cw + gap), 0, cw, cw + 34) album:a];
            [hs addSubview:c];
        }
        [panel addSubview:hs];
        py += cw + 34 + 20;
    }

    py += 110;
    CGRect pf = panel.frame;
    pf.size.height = py;
    panel.frame = pf;
    self.scroll.contentSize = CGSizeMake(W, y + py);

    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 40, W - 60, 40);
    self.spin.center = CGPointMake(W / 2, self.view.bounds.size.height / 2 - 70);

    [ADMiniBar.shared refresh];
}

// 继续收听卡片菜单（长按和 ··· 共用）
- (void)menuCard:(ADAlbum *)a {
    ADStore *st = [ADStore shared];
    BOOL fav = [st isFavorite:a.albumId];
    NSArray *opts = @[@"继续播放", @"从头播放", (fav ? @"取消收藏" : @"收藏到书架"), @"打开专辑", @"重新获取封面", @"从继续收听移除"];
    [ADOptionSheet showIn:self title:a.title options:opts destructive:5 choose:^(NSInteger i) {
        if (i == 0) { [self playCard:a]; }
        else if (i == 1) { [self playFromStart:a]; }
        else if (i == 2) { [st toggleFavorite:a]; [ADHaptic success]; [self build]; }
        else if (i == 3) {
            ADAlbumController *vc = [ADAlbumController new]; vc.album = a;
            [self.navigationController pushViewController:vc animated:YES];
        }
        else if (i == 4) { [self refetchCover:a]; }
        else { [ADHaptic warning]; [st removeContinue:a.albumId]; [self build]; }
    }];
}

- (void)playFromStart:(ADAlbum *)a {
    __block BOOL fired = NO;
    [[ADApi shared] tracksOf:a.albumId page:1 done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        if (!list.count || fired) return;
        fired = YES;
        ADPlayer *p = ADPlayer.shared;
        p.album = a; p.tracks = list;
        [[ADStore shared] setPosition:0 for:list[0].trackId];
        [[ADStore shared] touchHistory:a];
        [p playAt:0];
        [p ensureFullQueue];
    }];
}

- (void)refetchCover:(ADAlbum *)a {
    // 先删本地封面缓存，再回服务端取一次详情，封面就会重新下载
    if (a.cover.length) {
        NSString *p = [NSString stringWithFormat:@"%@/Documents/cache/covers/%lu.jpg", NSHomeDirectory(), (unsigned long)a.cover.hash];
        [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
    }
    __weak typeof(self) w = self;
    [[ADApi shared] albumDetail:a.albumId done:^(ADAlbum *d, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        if (d.cover.length && [d.cover hasPrefix:@"http"]) a.cover = d.cover;
        [[ADStore shared] save];
        [self build];
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)s {
    static CGFloat lastY = 0;
    [ADLiquid followScroll:s lastY:&lastY];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)s {
    [UIView animateWithDuration:0.3 animations:^{ ADNavDock.shared.transform = CGAffineTransformIdentity; ADNavDock.shared.alpha = 1; }];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)s willDecelerate:(BOOL)d {
    if (!d) [self scrollViewDidEndDecelerating:s];
}

- (void)gotoSearch {
    [ADHaptic tap];
    UIViewController *root = UIApplication.sharedApplication.windows.firstObject.rootViewController;
    if ([root isKindOfClass:ADDockController.class]) ((ADDockController *)root).selectedIndex = 1;
}

- (void)openHistory {
    [ADHaptic tap];
    [self.navigationController pushViewController:[ADHistoryController new] animated:YES];
}

- (void)openDownloads {
    [ADHaptic tap];
    [self.navigationController pushViewController:[ADDownloadsController new] animated:YES];
}

- (void)playCard:(ADAlbum *)a {
    ADPlayer *p = ADPlayer.shared;
    if (p.album && [p.album.albumId isEqualToString:a.albumId]) { [p toggle]; [self refreshCards]; return; }
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    NSInteger idx = [info[@"index"] integerValue];
    [[ADApi shared] tracksOf:a.albumId page:1 done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        if (!list.count) return;
        [ADPlayer.shared playAlbum:a tracks:list at:idx];
        [self refreshCards];
    }];
}

- (void)moreCard:(ADAlbum *)a { [ADHaptic tap]; [self menuCard:a]; }
@end

// ───────────── 搜索结果行 ─────────────
@interface ADSearchCell : UICollectionViewCell
- (void)fill:(ADAlbum *)a keyword:(NSString *)kw;
@end
@implementation ADSearchCell {
    UIView *_card;
    UIImageView *_cover, *_chev;
    UILabel *_title, *_sub, *_meta;
    UILabel *_p[3];
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _card = [UIView new];
        [ADLiquid glassLite:_card radius:20];
        [self.contentView addSubview:_card];
        _cover = [UIImageView new];
        _cover.layer.cornerRadius = 12; _cover.clipsToBounds = YES;
        _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        _title = [ADUtil label:nil size:16 color:UIColor.whiteColor]; _title.numberOfLines = 1;
        _sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.7]]; _sub.numberOfLines = 1;
        _meta = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.45]]; _meta.numberOfLines = 1;
        _chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
        _chev.tintColor = [UIColor colorWithWhite:1 alpha:0.28];
        for (UIView *v in @[_cover, _title, _sub, _meta, _chev]) [_card addSubview:v];
        for (int i = 0; i < 3; i++) {
            UILabel *l = [ADUtil label:nil size:10.5 color:UIColor.whiteColor];
            l.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
            l.numberOfLines = 1; l.textAlignment = NSTextAlignmentCenter;
            l.layer.cornerRadius = 9; l.clipsToBounds = YES; l.hidden = YES;
            [_card addSubview:l]; _p[i] = l;
        }
    }
    return self;
}
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.12 : 0.38 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.975, 0.975) : CGAffineTransformIdentity; } completion:nil];
}
- (void)fill:(ADAlbum *)a keyword:(NSString *)kw {
    [ADUtil cover:_cover url:a.cover];
    NSDictionary *base = @{NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: UIColor.whiteColor};
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:a.title ?: @"" attributes:base];
    if (kw.length && a.title.length) {
        NSRange r = [a.title rangeOfString:kw options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) [as addAttribute:NSForegroundColorAttributeName value:[ADUtil brand] range:r];
    }
    _title.attributedText = as;
    NSString *who = a.anchor.length ? a.anchor : (a.author.length ? a.author : @"");
    _sub.text = who.length ? who : @"有声书";
    NSMutableArray *bits = [NSMutableArray array];
    if (a.trackCount > 0) [bits addObject:[NSString stringWithFormat:@"%ld 集", (long)a.trackCount]];
    if (a.playCount > 0) [bits addObject:[NSString stringWithFormat:@"%@播放", [ADUtil count:a.playCount]]];
    if (a.provider.length) [bits addObject:a.provider];
    _meta.text = [bits componentsJoinedByString:@" · "];
    ADStore *st = [ADStore shared];
    NSMutableArray *tags = [NSMutableArray array];   // @[文字, 是否强调]
    if ([st isAlbumDone:a.albumId]) [tags addObject:@[@"已听完", @YES]];
    if (a.isPaid) [tags addObject:@[@"VIP", @YES]];
    if ([st isFavorite:a.albumId]) [tags addObject:@[@"已收藏", @NO]];
    ADTask *tk = [[ADDownloader shared] taskForAlbum:a.albumId];
    if (tk && tk.done > 0) [tags addObject:@[@"已缓存", @NO]];
    for (int i = 0; i < 3; i++) {
        UILabel *l = _p[i];
        if (i < (NSInteger)tags.count) {
            BOOL hot = [tags[i][1] boolValue];
            l.text = tags[i][0]; l.hidden = NO;
            l.backgroundColor = hot ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.12];
            l.textColor = hot ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.78];
        } else l.hidden = YES;
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    _card.frame = CGRectMake(12, 4, W - 24, H - 8);
    CGFloat cw = _card.bounds.size.width, ch = _card.bounds.size.height;
    _cover.frame = CGRectMake(12, (ch - 76) / 2, 76, 76);
    CGFloat x = 102, tw = cw - x - 30;
    _title.frame = CGRectMake(x, 12, tw, 20);
    _sub.frame = CGRectMake(x, 34, tw, 16);
    _meta.frame = CGRectMake(x, 52, tw, 16);
    _chev.frame = CGRectMake(cw - 26, (ch - 14) / 2, 14, 14);
    CGFloat px = x;
    for (int i = 0; i < 3; i++) {
        UILabel *l = _p[i]; if (l.hidden) continue;
        CGSize sz = [l.text sizeWithAttributes:@{NSFontAttributeName: l.font}];
        l.frame = CGRectMake(px, ch - 12 - 18, sz.width + 16, 18);
        px += sz.width + 16 + 6;
    }
}
@end

// ───────────── 搜索 ─────────────
@interface ADSearchController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchBarDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSMutableArray<ADAlbum *> *list;
@property (nonatomic, assign) NSInteger page;
@property (nonatomic, assign) BOOL loading, more;
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIScrollView *cats;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, assign) BOOL localMode;
@property (nonatomic, assign) NSInteger catIndex;
@property (nonatomic, assign) NSInteger autoPages;
@property (nonatomic, strong) NSMutableArray *chips;
@property (nonatomic, strong) UIScrollView *panel;
@property (nonatomic, strong) NSArray<ADAlbum *> *recs;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@end

@implementation ADSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.navigationController.navigationBar.hidden = YES;
    UILabel *stitle = [ADUtil label:@"PingFangSC-Semibold" size:34 color:UIColor.whiteColor];
    stitle.text = @"搜索"; stitle.tag = 76; stitle.numberOfLines = 1;
    [self.view addSubview:stitle];
    UIView *spill = [UIView new];
    spill.tag = 77; spill.userInteractionEnabled = NO;
    [ADLiquid glassLite:spill radius:22];
    [self.view addSubview:spill];
    self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.bar.placeholder = @"书名 / 作者 / 主播";
    self.bar.searchBarStyle = UISearchBarStyleMinimal;
    self.bar.delegate = self;
    self.bar.tintColor = [ADUtil brand];
    self.bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self.bar setSearchFieldBackgroundImage:[UIImage new] forState:UIControlStateNormal];
    self.bar.backgroundImage = [UIImage new];
    self.bar.searchTextField.textColor = UIColor.whiteColor;
    self.bar.searchTextField.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.bar];
    [self layoutChrome];
    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    (void)w;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(self.view.bounds.size.width, 108);
    lo.minimumInteritemSpacing = 0;
    lo.minimumLineSpacing = 0;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 108, self.view.bounds.size.width, self.view.bounds.size.height - 108) collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(4, 0, 140, 0);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:ADSearchCell.class forCellWithReuseIdentifier:@"c"];
    self.cv.refreshControl = [[UIRefreshControl alloc] init];
    self.cv.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.cv.refreshControl addTarget:self action:@selector(refreshSearch) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.cv];
    self.hint = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hint];
    self.list = [NSMutableArray array];
    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"在线", @"本地"]];
    self.seg.selectedSegmentIndex = 0;
    self.seg.frame = CGRectMake(16, 0, 130, 32);
    if (@available(iOS 13.0, *)) {
        self.seg.selectedSegmentTintColor = [ADUtil brand];
        self.seg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    }
    [self.seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7]} forState:UIControlStateNormal];
    [self.seg addTarget:self action:@selector(switchMode) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.seg];

    self.cats = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    self.cats.showsHorizontalScrollIndicator = NO;
    self.cats.contentInset = UIEdgeInsetsMake(0, 12, 0, 12);
    [self.view addSubview:self.cats];
    [self buildChips];

    self.panel = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.showsVerticalScrollIndicator = NO;
    self.panel.contentInset = UIEdgeInsetsMake(0, 0, 140, 0);
    [self.view addSubview:self.panel];
    [self rebuildPanel];
    [self loadRecs];
    [self updatePanel];
}

- (void)switchMode {
    self.localMode = (self.seg.selectedSegmentIndex == 1);
    [self layoutChrome];
    [self updatePanel];
    self.page = 1;
    self.autoPages = 0;
    if (self.localMode) {
        [self.bar resignFirstResponder];
        self.bar.placeholder = @"搜索本机下载、书架、历史";
        [self.cv reloadData];
        self.hint.text = [self visible].count ? @"" : @"本机还没有内容，先在专辑页「缓存到本机」或收藏";
    } else {
        self.bar.placeholder = @"书名 / 作者 / 主播";
        if (self.keyword.length) { [self.list removeAllObjects]; self.more = YES; [self loadPage]; }
        else { [self.cv reloadData]; self.hint.text = @""; }
    }
    [self paintChips];
}

- (NSArray<ADAlbum *> *)localAlbums {
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (ADTask *t in [ADDownloader shared].tasks) {
        if (!t.albumId.length || [seen containsObject:t.albumId]) continue;
        ADAlbum *a = [ADAlbum new];
        a.albumId = t.albumId;
        a.title = t.title.length ? t.title : t.albumId;
        a.cover = t.cover;
        [arr addObject:a];
        [seen addObject:t.albumId];
    }
    for (ADAlbum *a in [ADStore shared].favorites)
        if (![seen containsObject:a.albumId]) { [arr addObject:a]; [seen addObject:a.albumId]; }
    for (ADAlbum *a in [ADStore shared].history)
        if (![seen containsObject:a.albumId]) { [arr addObject:a]; [seen addObject:a.albumId]; }
    return arr;
}

- (void)searchBar:(UISearchBar *)b textDidChange:(NSString *)t {
    NSString *q = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (self.localMode) {
        [self.cv reloadData];
        self.hint.text = [self visible].count ? @"" : (q.length ? @"本机没有匹配的内容" : @"本机还没有内容，先在专辑页「缓存到本机」或收藏");
        self.hint.hidden = self.hint.text.length == 0;
        return;
    }
    if (!q.length) {
        // 清空搜索词：结果要跟着清掉，回到「历史/热词/推荐」面板
        self.keyword = @"";
        [self.list removeAllObjects];
        self.page = 1;
        self.more = NO;
        self.autoPages = 0;
        self.hint.text = @"";
        [self.cv reloadData];
        [self updatePanel];
    }
}


- (NSCharacterSet *)noiseChars {
    static NSCharacterSet *cs; static dispatch_once_t once;
    dispatch_once(&once, ^{
        cs = [NSCharacterSet characterSetWithCharactersInString:@" ，,、|｜·•:：;；!！?？.。《》<>「」【】()（）[]-—_/\\\"'’“”\n\t"];
    });
    return cs;
}

- (NSString *)normText:(NSString *)s {
    if (!s.length) return @"";
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[self noiseChars]];
    return [[parts componentsJoinedByString:@""] lowercaseString];
}

- (NSInteger)relevanceOf:(ADAlbum *)a {
    NSString *kw = self.keyword ?: @"";
    NSString *nk = [self normText:kw];
    if (!nk.length) return 0;
    NSString *nt = [self normText:a.title ?: @""];
    if ([nt containsString:nk]) return 0;               // 完整关键词命中（忽略空格标点）
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *t in [kw componentsSeparatedByCharactersInSet:[self noiseChars]]) {
        NSString *n = [self normText:t];
        if (n.length) [tokens addObject:n];
    }
    NSInteger miss = 0;
    for (NSString *t in tokens) if (![nt containsString:t]) miss += 1;
    return 1 + miss;                                    // 命中词越多越靠前
}

- (NSArray *)catTitles {
    return @[@"全部", @"有声书", @"相声评书", @"音乐", @"儿童", @"历史", @"外语", @"个人成长"];
}

- (NSArray *)catWords:(NSInteger)i {
    NSArray *map = @[@[], @[],
                     @[@"相声", @"评书", @"单口", @"德云", @"郭德纲", @"小品", @"段子", @"说书"],
                     @[@"音乐", @"钢琴", @"古筝", @"纯音乐", @"轻音乐", @"歌曲", @"助眠", @"白噪音", @"吉他", @"睡眠"],
                     @[@"儿童", @"宝宝", @"睡前", @"童话", @"儿歌", @"绘本", @"成语", @"幼儿"],
                     @[@"历史", @"史", @"三国", @"明", @"清", @"唐", @"宋", @"通史", @"春秋", @"帝王"],
                     @[@"英语", @"日语", @"韩语", @"口语", @"单词", @"雅思", @"托福", @"听力", @"法语"],
                     @[@"成长", @"职场", @"情商", @"自律", @"思维", @"沟通", @"心理", @"认知"]];
    return (i >= 0 && i < (NSInteger)map.count) ? map[i] : @[];
}

- (void)buildChips {
    for (UIView *v in self.cats.subviews) [v removeFromSuperview];
    NSArray *titles = [self catTitles];
    CGFloat x = 12;
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = 100 + i;
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        CGSize sz = [titles[i] sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}];
        CGFloat w = sz.width + 26;
        b.frame = CGRectMake(x, 6, w, 30);
        b.layer.cornerRadius = 15;
        [b addTarget:self action:@selector(tapChip:) forControlEvents:UIControlEventTouchUpInside];
        [self.cats addSubview:b];
        x += w + 8;
    }
    self.cats.contentSize = CGSizeMake(x + 4, 40);
    [self paintChips];
}

- (void)paintChips {
    NSArray *titles = [self catTitles];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = (UIButton *)[self.cats viewWithTag:100 + i];
        BOOL on = (i == self.catIndex);
        b.backgroundColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.1];
        [b setTitleColor:(on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.72]) forState:UIControlStateNormal];
    }
}

- (void)tapChip:(UIButton *)b {
    [ADHaptic select];
    self.catIndex = b.tag - 100;
    [self paintChips];
    [self.cv reloadData];
    if (self.catIndex != 0 && self.list.count && [self visible].count < 6 && self.more) {
        self.autoPages = 0;
        [self loadPage];
    }
}

- (NSString *)hayOf:(ADAlbum *)a {
    return [NSString stringWithFormat:@"%@ %@ %@ %@", a.title ?: @"", a.anchor ?: @"", a.author ?: @"", a.intro ?: @""];
}

- (BOOL)titleMatches:(ADAlbum *)a category:(NSInteger)idx {
    NSArray *words = [self catWords:idx];
    if (!words.count) return NO;
    NSString *hay = [self hayOf:a];
    for (NSString *w in words) if ([hay rangeOfString:w].location != NSNotFound) return YES;
    return NO;
}

- (BOOL)catMatch:(ADAlbum *)a {
    if (self.catIndex == 0) return YES;
    if (self.catIndex == 1) {
        // 这个服务本身就是有声书库，「有声书」= 不属于其他分类的全部内容
        for (NSInteger i = 2; i < (NSInteger)[self catTitles].count; i++) {
            if ([self titleMatches:a category:i]) return NO;
        }
        return YES;
    }
    return [self titleMatches:a category:self.catIndex];
}

- (NSArray<ADAlbum *> *)visible {
    if (self.localMode) {
        NSString *q = [[self.bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
        NSArray *all = [self localAlbums];
        if (!q.length) return all;
        NSMutableArray *arr = [NSMutableArray array];
        for (ADAlbum *a in all) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", a.title ?: @"", a.anchor ?: @"", a.author ?: @""] lowercaseString];
            if ([hay rangeOfString:q].location != NSNotFound) [arr addObject:a];
        }
        return arr;
    }
    if (self.catIndex == 0) return self.list;
    NSMutableArray *arr = [NSMutableArray array];
    for (ADAlbum *a in self.list) {
        // 关键词完全命中的结果永远保留，避免切分类后把要的书过滤掉
        if ([self catMatch:a] || [self relevanceOf:a] == 0) [arr addObject:a];
    }
    return arr;
}
// ── 空状态面板：搜索历史 / 热门搜索 / 推荐收听 ──
- (NSMutableArray<NSString *> *)history {
    if (!_history) {
        NSArray *a = [NSUserDefaults.standardUserDefaults arrayForKey:@"ad_search_history"];
        _history = a ? [a mutableCopy] : [NSMutableArray array];
    }
    return _history;
}

- (void)rememberKeyword:(NSString *)k {
    if (!k.length) return;
    [self.history removeObject:k];
    [self.history insertObject:k atIndex:0];
    while (self.history.count > 12) [self.history removeLastObject];
    [NSUserDefaults.standardUserDefaults setObject:self.history forKey:@"ad_search_history"];
    [self rebuildPanel];
}

- (NSArray<NSString *> *)hotWords {
    return @[@"郭德纲", @"三国演义", @"睡前故事", @"白噪音", @"英语听力",
             @"鬼吹灯", @"明朝那些事", @"儿童成语", @"盗墓笔记", @"助眠轻音乐"];
}

- (CGFloat)addChips:(NSArray<NSString *> *)words atY:(CGFloat)y tagBase:(NSInteger)base {
    UIFont *f = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    CGFloat x = 16, maxX = self.view.bounds.size.width - 16;
    for (NSInteger i = 0; i < (NSInteger)words.count; i++) {
        NSString *w = words[i];
        CGSize sz = [w sizeWithAttributes:@{NSFontAttributeName: f}];
        CGFloat bw = sz.width + 26;
        if (x + bw > maxX) { x = 16; y += 38; }
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(x, y, bw, 30);
        b.tag = base + i;
        b.titleLabel.font = f;
        [b setTitle:w forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        b.layer.cornerRadius = 15;
        b.layer.borderWidth = 0.6; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        [b addTarget:self action:@selector(tapWord:) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:b];
        x += bw + 8;
    }
    return y + 30;
}

- (void)rebuildPanel {
    for (UIView *v in self.panel.subviews) [v removeFromSuperview];
    CGFloat W = self.view.bounds.size.width;
    CGFloat y = 6;

    if (self.history.count) {
        UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
        t.text = @"搜索历史";
        t.frame = CGRectMake(16, y, 160, 22);
        [self.panel addSubview:t];

        UIButton *clr = [UIButton buttonWithType:UIButtonTypeSystem];
        clr.frame = CGRectMake(W - 72, y - 4, 56, 30);
        clr.titleLabel.font = [UIFont systemFontOfSize:13];
        [clr setTitle:@"清空" forState:UIControlStateNormal];
        [clr setTitleColor:[ADUtil dim] forState:UIControlStateNormal];
        [clr addTarget:self action:@selector(clearHistory) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:clr];
        y += 30;
        y = [self addChips:self.history atY:y tagBase:1000];
        y += 16;
    }

    UILabel *h = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
    h.text = @"大家都在搜";
    h.frame = CGRectMake(16, y, 200, 22);
    [self.panel addSubview:h];
    y += 30;
    y = [self addChips:self.hotWords atY:y tagBase:2000];
    y += 22;

    if (self.recs.count) {
        UILabel *r = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
        r.text = @"推荐收听";
        r.frame = CGRectMake(16, y, 200, 22);
        [self.panel addSubview:r];
        y += 32;
        for (NSInteger i = 0; i < (NSInteger)self.recs.count; i++) {
            ADAlbum *a = self.recs[i];
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(16, y, W - 32, 62);
            [ADLiquid glassLite:row radius:16];
            row.tag = 3000 + i;
            [row addTarget:self action:@selector(tapRec:) forControlEvents:UIControlEventTouchUpInside];

            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 48, 48)];
            iv.layer.cornerRadius = 9;
            iv.clipsToBounds = YES;
            iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
            [ADUtil cover:iv url:a.cover];
            [row addSubview:iv];

            UILabel *t = [ADUtil label:nil size:14 color:UIColor.whiteColor];
            t.frame = CGRectMake(66, 9, W - 32 - 66 - 34, 20);
            t.numberOfLines = 1;
            t.text = a.title;
            [row addSubview:t];

            UILabel *sub = [ADUtil label:nil size:11 color:[ADUtil dim]];
            sub.frame = CGRectMake(66, 31, W - 32 - 66 - 34, 18);
            sub.text = [NSString stringWithFormat:@"%@%@", a.anchor.length ? a.anchor : @"有声书",
                        a.trackCount > 0 ? [NSString stringWithFormat:@" · %ld 集", (long)a.trackCount] : @""];
            [row addSubview:sub];

            UIImageView *chev = [[UIImageView alloc] initWithFrame:CGRectMake(W - 32 - 28, 23, 16, 16)];
            chev.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]];
            chev.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
            [row addSubview:chev];

            [self.panel addSubview:row];
            y += 70;
        }
    }

    self.panel.contentSize = CGSizeMake(W, y + 20);
}

- (void)loadRecs {
    __weak typeof(self) w = self;
    [[ADApi shared] discover:^(NSArray<NSDictionary *> *sections, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        NSMutableArray *arr = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *sec in sections) {
            NSArray *its = sec[@"items"];
            if (![its isKindOfClass:NSArray.class]) continue;
            for (id o in its) {
                ADAlbum *a = [ADAlbum fromJSON:o];
                if (!a || [seen containsObject:a.albumId]) continue;
                [seen addObject:a.albumId];
                [arr addObject:a];
                if (arr.count >= 6) break;
            }
            if (arr.count >= 6) break;
        }
        self.recs = arr;
        [self rebuildPanel];
    }];
}

- (void)clearHistory {
    [self.history removeAllObjects];
    [NSUserDefaults.standardUserDefaults setObject:@[] forKey:@"ad_search_history"];
    [self rebuildPanel];
}

- (void)tapWord:(UIButton *)b {
    [ADHaptic tap];
    NSInteger tag = b.tag;
    NSString *word = nil;
    if (tag >= 2000 && tag < 3000) {
        NSArray *hw = [self hotWords];
        NSInteger i = tag - 2000;
        if (i < (NSInteger)hw.count) word = hw[i];
    } else if (tag >= 1000 && tag < 2000) {
        NSInteger i = tag - 1000;
        if (i < (NSInteger)self.history.count) word = self.history[i];
    }
    if (word.length) [self startSearch:word];
}

- (void)tapRec:(UIButton *)b {
    [ADHaptic tap];
    NSInteger i = b.tag - 3000;
    if (i < 0 || i >= (NSInteger)self.recs.count) return;
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.recs[i];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)startSearch:(NSString *)q {
    [ADHaptic heavy];
    q = [q stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!q.length) return;
    self.localMode = NO;
    self.seg.selectedSegmentIndex = 0;
    self.bar.text = q;
    [self.bar resignFirstResponder];
    self.keyword = q;
    self.page = 1;
    self.more = YES;
    self.autoPages = 0;
    self.list = [NSMutableArray array];
    if (self.catIndex != 0) { self.catIndex = 0; [self paintChips]; }
    [self.cv reloadData];
    self.hint.text = @"搜索中…";
    self.hint.hidden = NO;
    [self rememberKeyword:q];
    [self updatePanel];
    [self loadPage];
}

- (void)updatePanel {
    BOOL show = (!self.localMode && self.keyword.length == 0);
    self.panel.hidden = !show;
    self.cv.hidden = show;
    if (show) self.hint.hidden = YES;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.navigationController.navigationBar.hidden = YES; [self layoutChrome]; }
- (void)layoutChrome {
    CGFloat top = MAX(self.view.safeAreaInsets.top, 47);
    CGFloat W = self.view.bounds.size.width;
    [self.view viewWithTag:76].frame = CGRectMake(16, top - 4, 120, 42);
    self.seg.frame = CGRectMake(W - 16 - 130, top + 2, 130, 32);
    [self.view viewWithTag:77].frame = CGRectMake(16, top + 46, W - 32, 44);
    self.bar.frame = CGRectMake(10, top + 46, W - 20, 44);
    self.cats.frame = CGRectMake(0, top + 98, W, 40);
    self.cats.hidden = self.localMode;
    CGFloat gridTop = self.localMode ? top + 98 : top + 138;
    self.cv.frame = CGRectMake(0, gridTop, W, self.view.bounds.size.height - gridTop);
    UICollectionViewFlowLayout *lo = (UICollectionViewFlowLayout *)self.cv.collectionViewLayout;
    if ([lo isKindOfClass:UICollectionViewFlowLayout.class] && lo.itemSize.width != W) { lo.itemSize = CGSizeMake(W, 108); [lo invalidateLayout]; }
    self.panel.frame = self.cv.frame;
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2, self.view.bounds.size.width - 60, 40);
    [ADMiniBar.shared refresh];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)b {
    [b resignFirstResponder];
    if (self.localMode) { [self.cv reloadData]; return; }
    [self startSearch:b.text];
}
- (void)refreshSearch {
    [self.cv.refreshControl endRefreshing];
    if (!self.keyword.length) return;
    self.page = 1;
    [self.list removeAllObjects];
    [self loadPage];
}

- (void)loadPage {
    if (self.loading || !self.more) return;
    self.loading = YES;
    __weak typeof(self) w = self;
    [[ADApi shared] search:self.keyword page:self.page done:^(NSArray<ADAlbum *> *list, BOOL more, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.loading = NO;
        self.more = list.count > 0;
        if (list.count) {
            if (self.page == 1) [self.list removeAllObjects];
            [self.list addObjectsFromArray:list];
            self.page += 1;
        }
        NSInteger hits = 0;
        for (ADAlbum *a in self.list) if ([self relevanceOf:a] == 0) hits += 1;
        if (hits == 0 && self.more && self.autoPages < 2) {
            // 第一屏没有标题含关键词的，自动再翻两页
            self.autoPages += 1;
            [self loadPage];
        }
        if (self.keyword.length) {
            [self.list sortUsingComparator:^NSComparisonResult(ADAlbum *x, ADAlbum *y) {
                NSInteger sx = [self relevanceOf:x], sy = [self relevanceOf:y];
                if (sx == sy) return NSOrderedSame;
                return sx < sy ? NSOrderedAscending : NSOrderedDescending;
            }];
        }
        NSArray *shown = [self visible];
        if (self.catIndex != 0 && shown.count < 6 && self.more && self.autoPages < 6) {
            self.autoPages += 1;
            [self loadPage];
        }
        self.hint.text = (self.list.count ? (shown.count ? @"" : @"这个分类里没有结果，换个分类或关键词") : (err ?: @"没有找到"));
        [self.cv reloadData];
    }];
}
- (void)scrollViewDidScroll:(UIScrollView *)s {
    if (s.contentOffset.y + s.bounds.size.height > s.contentSize.height - 300) [self loadPage];
    static CGFloat lastY = 0;
    [ADLiquid followScroll:s lastY:&lastY];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)s {
    [UIView animateWithDuration:0.3 animations:^{ ADNavDock.shared.transform = CGAffineTransformIdentity; ADNavDock.shared.alpha = 1; }];
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return [self visible].count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADSearchCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    NSArray *vis = [self visible];
    if (ip.item >= (NSInteger)vis.count) return cell;
    NSString *kw = self.localMode ? [self.bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : self.keyword;
    [cell fill:vis[ip.item] keyword:kw];
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic tap];
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = [self visible][ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end

// ───────────── 书架 ─────────────
// 三种显示方式：0 详细列表 / 1 紧凑列表 / 2 封面墙
static void ADAlbumProgress(ADAlbum *a, NSInteger *listened, NSInteger *total, double *prog) {
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    NSInteger idx = [info[@"index"] integerValue];
    NSInteger t = a.trackCount;
    if (t <= 0) {
        ADTask *task = [[ADDownloader shared] taskForAlbum:a.albumId];
        t = (NSInteger)task.tracks.count;
    }
    double sec = [info[@"seconds"] doubleValue];
    double dur = [info[@"duration"] doubleValue];
    double inner = (dur > 1) ? MIN(1.0, sec / dur) : 0;
    double p = (t > 0) ? ((double)idx + inner) / (double)t : 0;
    if (p < 0) p = 0;
    if (p > 1) p = 1;
    if (prog) *prog = p;
    if (total) *total = t;
    if (listened) *listened = info ? MIN(idx + 1, MAX(t, 1)) : 0;
}

@interface ADShelfCell : UICollectionViewCell
- (void)fill:(ADAlbum *)a mode:(NSInteger)mode width:(CGFloat)w;
@end

@implementation ADShelfCell

- (UILabel *)pill:(NSString *)t {
    UILabel *l = [ADUtil label:nil size:10.5 color:UIColor.whiteColor];
    l.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    l.text = t; l.numberOfLines = 1;
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    l.layer.cornerRadius = 9; l.clipsToBounds = YES;
    CGSize sz = [t sizeWithAttributes:@{NSFontAttributeName: l.font}];
    l.frame = CGRectMake(0, 0, sz.width + 14, 18);
    return l;
}

- (UIImageView *)icon:(NSString *)n color:(UIColor *)c {
    UIImageView *v = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:n withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]]];
    v.tintColor = c; v.contentMode = UIViewContentModeScaleAspectFit;
    v.frame = CGRectMake(0, 0, 14, 14);
    return v;
}

- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.12 : 0.38 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.975, 0.975) : CGAffineTransformIdentity; } completion:nil];
}

- (UIView *)bar:(CGRect)f prog:(double)prog {
    UIView *bar = [[UIView alloc] initWithFrame:f];
    bar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    bar.layer.cornerRadius = f.size.height / 2;
    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(prog > 0 ? f.size.height : 0, f.size.width * prog), f.size.height)];
    fill.backgroundColor = [ADUtil brand];
    fill.layer.cornerRadius = f.size.height / 2;
    [bar addSubview:fill];
    return bar;
}

- (void)fill:(ADAlbum *)a mode:(NSInteger)mode width:(CGFloat)w {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.contentView.backgroundColor = UIColor.clearColor;
    ADStore *st = [ADStore shared];
    NSInteger listened = 0, total = 0;
    double prog = 0;
    ADAlbumProgress(a, &listened, &total, &prog);
    BOOL fav = [st isFavorite:a.albumId], pin = [st isPinned:a.albumId], done = [st isAlbumDone:a.albumId];
    ADTask *task = [[ADDownloader shared] taskForAlbum:a.albumId];
    BOOL dl = (task && task.done > 0);
    NSDictionary *info = [st lastInfoOf:a.albumId];

    if (mode == 2) {
        // 封面墙：进度条压在封面底部，状态用角标
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, w)];
        iv.layer.cornerRadius = 14; iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        [ADUtil cover:iv url:a.cover];
        [self.contentView addSubview:iv];
        if (prog > 0.001 && !done) {
            UIView *shade = [[UIView alloc] initWithFrame:CGRectMake(0, w - 22, w, 22)];
            shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
            [iv addSubview:shade];
            [iv addSubview:[self bar:CGRectMake(8, w - 10, w - 16, 3) prog:prog]];
        }
        CGFloat bx = w - 6;
        NSMutableArray *views = [NSMutableArray array];
        if (done) [views addObject:[self pill:@"已听完"]];
        if (pin) { UIImageView *p = [self icon:@"pin.fill" color:UIColor.whiteColor]; [views addObject:p]; }
        if (dl) { UIImageView *p = [self icon:@"arrow.down.circle.fill" color:UIColor.whiteColor]; [views addObject:p]; }
        for (UIView *v in views) {
            bx -= v.bounds.size.width;
            v.frame = CGRectMake(bx, 8, v.bounds.size.width, v.bounds.size.height);
            if ([v isKindOfClass:UIImageView.class]) {
                UIView *bg = [[UIView alloc] initWithFrame:CGRectInset(v.frame, -4, -4)];
                bg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; bg.layer.cornerRadius = bg.bounds.size.width / 2;
                [iv addSubview:bg];
            }
            [iv addSubview:v];
            bx -= 8;
        }
        if (fav) { UIImageView *h = [self icon:@"heart.fill" color:[ADUtil brand]]; h.frame = CGRectMake(8, 8, 15, 15); [iv addSubview:h]; }
        UILabel *t = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.9]];
        t.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        t.frame = CGRectMake(2, w + 7, w - 4, 34);
        t.numberOfLines = 2; t.text = a.title;
        [self.contentView addSubview:t];
        return;
    }

    BOOL compact = (mode == 1);
    CGFloat H = compact ? 68 : 124;
    CGFloat inY = compact ? 4 : 5;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, inY, w - 24, H - inY * 2)];
    [ADLiquid glassLite:card radius:compact ? 18 : 22];
    [self.contentView addSubview:card];
    CGFloat cw = card.bounds.size.width, ch = card.bounds.size.height;

    NSString *who = a.anchor.length ? a.anchor : (a.author.length ? a.author : @"");
    NSString *curText = info ? [NSString stringWithFormat:@"第 %ld 集 · %@", (long)[info[@"index"] integerValue] + 1, info[@"title"] ?: @""] : @"还没开始听";
    UIColor *pctColor = (prog >= 1 || done) ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.85];

    if (compact) {
        UIImageView *cv = [[UIImageView alloc] initWithFrame:CGRectMake(10, (ch - 44) / 2, 44, 44)];
        cv.layer.cornerRadius = 9; cv.clipsToBounds = YES;
        cv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        [ADUtil cover:cv url:a.cover];
        [card addSubview:cv];
        UILabel *pct = [ADUtil label:nil size:13 color:pctColor];
        pct.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        pct.textAlignment = NSTextAlignmentRight; pct.numberOfLines = 1;
        pct.frame = CGRectMake(cw - 12 - 44, 0, 44, ch);
        pct.text = [NSString stringWithFormat:@"%ld%%", (long)lround(prog * 100.0)];
        [card addSubview:pct];
        UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
        t.numberOfLines = 1; t.frame = CGRectMake(66, 8, cw - 66 - 62, 20); t.text = a.title;
        [card addSubview:t];
        UILabel *s = [ADUtil label:nil size:12 color:[ADUtil dim]];
        s.numberOfLines = 1; s.frame = CGRectMake(66, 29, cw - 66 - 62, 16);
        s.text = info ? [NSString stringWithFormat:@"%@%@第 %ld 集", who, who.length ? @" · " : @"", (long)[info[@"index"] integerValue] + 1] : (who.length ? who : @"还没开始听");
        [card addSubview:s];
        if (prog > 0.001) [card addSubview:[self bar:CGRectMake(66, ch - 9, cw - 66 - 62, 2) prog:prog]];
        return;
    }

    UIImageView *cv = [[UIImageView alloc] initWithFrame:CGRectMake(14, 15, 84, 84)];
    cv.layer.cornerRadius = 14; cv.clipsToBounds = YES;
    cv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    [ADUtil cover:cv url:a.cover];
    [card addSubview:cv];
    CGFloat x = 112, tw = cw - x - 14;

    UILabel *title = [ADUtil label:@"PingFangSC-Semibold" size:16.5 color:UIColor.whiteColor];
    title.numberOfLines = 1; title.frame = CGRectMake(x, 14, tw, 21); title.text = a.title;
    [card addSubview:title];

    // 状态小图标放在作者行右端
    NSMutableArray *icons = [NSMutableArray array];
    if (done) [icons addObject:[self icon:@"checkmark.seal.fill" color:[ADUtil brand]]];
    if (fav) [icons addObject:[self icon:@"heart.fill" color:[ADUtil brand]]];
    if (pin) [icons addObject:[self icon:@"pin.fill" color:[UIColor colorWithWhite:1 alpha:0.7]]];
    if (dl) [icons addObject:[self icon:@"arrow.down.circle.fill" color:[UIColor colorWithWhite:1 alpha:0.7]]];
    CGFloat ix = cw - 14;
    for (UIImageView *ic in icons) { ix -= 14; ic.frame = CGRectMake(ix, 39, 14, 14); [card addSubview:ic]; ix -= 6; }
    UILabel *author = [ADUtil label:nil size:12.5 color:[ADUtil dim]];
    author.numberOfLines = 1; author.frame = CGRectMake(x, 37, MAX(40, ix - x), 17);
    author.text = who.length ? who : @"有声书";
    [card addSubview:author];

    UILabel *cur = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
    cur.numberOfLines = 1; cur.frame = CGRectMake(x, 57, tw, 16); cur.text = curText;
    [card addSubview:cur];

    [card addSubview:[self bar:CGRectMake(x, 82, tw, 4) prog:prog]];

    UILabel *cnt = [ADUtil label:nil size:11 color:[UIColor colorWithWhite:1 alpha:0.5]];
    cnt.numberOfLines = 1; cnt.frame = CGRectMake(x, 91, tw * 0.7, 15);
    cnt.text = total > 0 ? [NSString stringWithFormat:@"已听 %ld/%ld 章", (long)listened, (long)total] : @"";
    [card addSubview:cnt];
    UILabel *pct = [ADUtil label:nil size:12 color:pctColor];
    pct.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    pct.textAlignment = NSTextAlignmentRight; pct.numberOfLines = 1;
    pct.frame = CGRectMake(cw - 14 - 60, 91, 60, 15);
    pct.text = [NSString stringWithFormat:@"%ld%%", (long)lround(prog * 100.0)];
    [card addSubview:pct];
}
@end

@interface ADShelfController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UICollectionViewFlowLayout *lo;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UILabel *hint, *countLabel;
@property (nonatomic, assign) NSInteger mode, filter;
@property (nonatomic, strong) UIScrollView *chips;
@end

@implementation ADShelfController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.navigationController.navigationBar.hidden = YES;
    self.mode = 0;
    self.filter = 0;

    UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:34 color:UIColor.whiteColor];
    t.text = @"书架";
    t.tag = 99;
    [self.view addSubview:t];

    self.countLabel = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.45]];
    [self.view addSubview:self.countLabel];

    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:gear radius:22];
    gear.tag = 98;
    gear.tintColor = UIColor.whiteColor;
    [gear setImage:[UIImage systemImageNamed:@"line.3.horizontal" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [gear addTarget:self action:@selector(showShelfMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:gear];

    UIButton *modeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:modeBtn radius:22];
    modeBtn.tag = 97; modeBtn.tintColor = UIColor.whiteColor;
    [modeBtn addTarget:self action:@selector(cycleMode) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:modeBtn];
    [self paintModeButton];

    self.chips = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.chips.showsHorizontalScrollIndicator = NO;
    self.chips.contentInset = UIEdgeInsetsMake(0, 12, 0, 12);
    [self.view addSubview:self.chips];
    [self buildFilterChips];

    UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"books.vertical" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightLight]]];
    emptyIcon.tag = 96; emptyIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.22]; emptyIcon.contentMode = UIViewContentModeCenter;
    [self.view addSubview:emptyIcon];

    self.lo = [UICollectionViewFlowLayout new];
    self.lo.minimumInteritemSpacing = 12;
    self.lo.minimumLineSpacing = 0;
    self.lo.sectionInset = UIEdgeInsetsZero;
    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    [self.cv registerClass:ADShelfCell.class forCellWithReuseIdentifier:@"shelf"];
    self.cv.refreshControl = [[UIRefreshControl alloc] init];
    self.cv.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.cv.refreshControl addTarget:self action:@selector(pullRefresh) forControlEvents:UIControlEventValueChanged];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    lp.minimumPressDuration = 0.45;
    [self.cv addGestureRecognizer:lp];
    [self.view addSubview:self.cv];

    self.hint = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.numberOfLines = 0;
    [self.view addSubview:self.hint];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
    [self reloadData];
    [self layoutChrome];
}

- (NSArray *)filterNames { return @[@"全部", @"收藏", @"想听", @"置顶", @"已下载", @"最近播放"]; }

- (void)buildFilterChips {
    for (UIView *v in self.chips.subviews) [v removeFromSuperview];
    NSArray *names = [self filterNames];
    CGFloat x = 12;
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = 500 + i;
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [b setTitle:names[i] forState:UIControlStateNormal];
        CGSize sz = [names[i] sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}];
        b.frame = CGRectMake(x, 5, sz.width + 28, 32);
        b.layer.cornerRadius = 16;
        b.layer.borderWidth = 0.6;
        [b addTarget:self action:@selector(tapFilterChip:) forControlEvents:UIControlEventTouchUpInside];
        [self.chips addSubview:b];
        x += sz.width + 28 + 8;
    }
    self.chips.contentSize = CGSizeMake(x + 4, 42);
    [self paintFilterChips];
}

- (void)paintFilterChips {
    for (NSInteger i = 0; i < (NSInteger)[self filterNames].count; i++) {
        UIButton *b = (UIButton *)[self.chips viewWithTag:500 + i];
        BOOL on = (i == self.filter);
        b.backgroundColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.08];
        b.layer.borderColor = (on ? UIColor.clearColor : [UIColor colorWithWhite:1 alpha:0.12]).CGColor;
        [b setTitleColor:(on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.75]) forState:UIControlStateNormal];
    }
}

- (void)tapFilterChip:(UIButton *)b {
    [ADHaptic select];
    self.filter = b.tag - 500;
    [self reloadData];
}

- (void)paintModeButton {
    UIButton *m = (UIButton *)[self.view viewWithTag:97];
    NSArray *icons = @[@"list.bullet.rectangle", @"list.bullet", @"square.grid.3x3.fill"];
    [m setImage:[UIImage systemImageNamed:icons[self.mode] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
}

- (void)cycleMode {
    [ADHaptic select];
    self.mode = (self.mode + 1) % 3;
    [self paintModeButton];
    [UIView transitionWithView:self.cv duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ [self reloadData]; } completion:nil];
}

- (void)applyLayout {
    CGFloat W = self.view.bounds.size.width;
    if (self.mode == 2) {
        CGFloat w = (W - 16 * 2 - 12 * 2) / 3;
        self.lo.itemSize = CGSizeMake(w, w + 42);
        self.lo.minimumInteritemSpacing = 12;
        self.lo.minimumLineSpacing = 16;
        self.lo.sectionInset = UIEdgeInsetsMake(8, 16, 0, 16);
        self.cv.contentInset = UIEdgeInsetsMake(0, 0, 130, 0);
    } else if (self.mode == 1) {
        self.lo.itemSize = CGSizeMake(W, 68);
        self.lo.minimumInteritemSpacing = 0;
        self.lo.minimumLineSpacing = 0;
        self.lo.sectionInset = UIEdgeInsetsZero;
        self.cv.contentInset = UIEdgeInsetsMake(6, 0, 130, 0);
    } else {
        self.lo.itemSize = CGSizeMake(W, 124);
        self.lo.minimumInteritemSpacing = 0;
        self.lo.minimumLineSpacing = 0;
        self.lo.sectionInset = UIEdgeInsetsZero;
        self.cv.contentInset = UIEdgeInsetsMake(6, 0, 130, 0);
    }
    [self.lo invalidateLayout];
}

- (NSArray<ADAlbum *> *)buildItems {
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    void (^add)(ADAlbum *) = ^(ADAlbum *a) {
        if (!a.albumId.length || [seen containsObject:a.albumId]) return;
        [seen addObject:a.albumId];
        [arr addObject:a];
    };
    ADStore *st = [ADStore shared];
    if (self.filter == 1) {
        for (ADAlbum *a in st.favorites) add(a);
    } else if (self.filter == 2) {
        for (ADAlbum *a in st.wants) add(a);
    } else if (self.filter == 3) {
        for (ADAlbum *a in st.favorites) if ([st isPinned:a.albumId]) add(a);
        for (ADAlbum *a in st.history) if ([st isPinned:a.albumId]) add(a);
    } else if (self.filter == 4) {
        for (ADTask *t in [ADDownloader shared].tasks) {
            if (t.done <= 0) continue;
            ADAlbum *a = [ADAlbum new];
            a.albumId = t.albumId;
            a.title = t.title.length ? t.title : t.albumId;
            a.cover = t.cover;
            a.anchor = t.anchor;
            a.trackCount = (NSInteger)t.tracks.count;
            add(a);
        }
    } else if (self.filter == 5) {
        for (ADAlbum *a in st.history) add(a);
    } else {
        for (ADAlbum *a in st.favorites) add(a);
        for (ADAlbum *a in st.history) add(a);
    }
    // 置顶的排最前
    [arr sortUsingComparator:^NSComparisonResult(ADAlbum *x, ADAlbum *y) {
        BOOL px = [st isPinned:x.albumId], py = [st isPinned:y.albumId];
        if (px == py) return NSOrderedSame;
        return px ? NSOrderedAscending : NSOrderedDescending;
    }];
    return arr;
}

- (void)reloadData {
    self.items = [self buildItems];
    self.hint.hidden = self.items.count > 0;
    static NSArray *names = nil;
    static NSArray *emptyHint = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"全部", @"收藏", @"想听", @"置顶", @"已下载", @"最近播放"];
        emptyHint = @[@"还没有收藏和收听记录\n在专辑页点右上角收藏",
                      @"还没有收藏\n在专辑页点右上角 ♡",
                      @"想听是空的\n长按书架里的书可以加入想听",
                      @"还没有置顶\n长按一本书 → 置顶",
                      @"还没有下载\n在专辑页点「缓存到本机」",
                      @"还没有收听记录"];
    });
    if (self.items.count) self.hint.text = @"";
    else self.hint.text = emptyHint[self.filter];
    self.countLabel.text = [NSString stringWithFormat:@"%ld 本", (long)self.items.count];
    [self paintFilterChips];
    [self paintModeButton];
    [self.view viewWithTag:96].hidden = self.items.count > 0;
    [self applyLayout];
    [self.cv reloadData];
}

- (void)layoutChrome {
    CGFloat top = MAX(self.view.safeAreaInsets.top, 47);
    UILabel *t = [self.view viewWithTag:99];
    t.frame = CGRectMake(16, top - 4, 120, 42);
    CGSize sz = [t.text sizeWithAttributes:@{NSFontAttributeName: t.font}];
    self.countLabel.frame = CGRectMake(20 + sz.width, top + 14, 240, 22);
    UIButton *gear = (UIButton *)[self.view viewWithTag:98];
    gear.frame = CGRectMake(self.view.bounds.size.width - 60, top + 4, 44, 44);
    [self.view viewWithTag:97].frame = CGRectMake(self.view.bounds.size.width - 60 - 52, top + 4, 44, 44);
    self.chips.frame = CGRectMake(0, top + 54, self.view.bounds.size.width, 42);
    self.cv.frame = CGRectMake(0, top + 100, self.view.bounds.size.width, self.view.bounds.size.height - top - 100);
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 20, self.view.bounds.size.width - 60, 60);
    [self.view viewWithTag:96].frame = CGRectMake(0, self.view.bounds.size.height / 2 - 90, self.view.bounds.size.width, 60);
    [self applyLayout];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutChrome];
    [ADMiniBar.shared refresh];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self layoutChrome];
}

- (void)pullRefresh {
    [self.cv.refreshControl endRefreshing];
    [self reloadData];
}

- (void)goSettings {
    UIViewController *root = UIApplication.sharedApplication.windows.firstObject.rootViewController;
    if ([root isKindOfClass:ADDockController.class]) ((ADDockController *)root).selectedIndex = 3;
}

- (void)showShelfMenu {
    [ADHaptic tap];
    static NSArray *names = nil;
    static NSArray *modes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"全部", @"收藏", @"想听", @"置顶", @"已下载", @"最近播放"];
        modes = @[@"详细列表", @"紧凑列表", @"封面墙"];
    });
    NSString *f = [NSString stringWithFormat:@"分类：%@", names[self.filter]];
    NSString *m = [NSString stringWithFormat:@"显示方式：%@", modes[self.mode]];
    [ADOptionSheet showIn:self title:@"书架" options:@[f, m, @"刷新书架"] destructive:-1 choose:^(NSInteger i) {
        if (i == 0) [self pickFilter];
        else if (i == 1) [self pickMode];
        else [self reloadData];
    }];
}

- (void)pickFilter {
    NSArray *names = @[@"全部", @"收藏", @"想听", @"置顶", @"已下载", @"最近播放"];
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++)
        [opts addObject:[NSString stringWithFormat:@"%@%@", names[i], (i == self.filter ? @"  ✓" : @"")]];
    [ADOptionSheet showIn:self title:@"分类" options:opts destructive:-1 choose:^(NSInteger i) {
        self.filter = i;
        [self reloadData];
    }];
}

- (void)pickMode {
    NSArray *modes = @[@"详细列表", @"紧凑列表", @"封面墙"];
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)modes.count; i++)
        [opts addObject:[NSString stringWithFormat:@"%@%@", modes[i], (i == self.mode ? @"  ✓" : @"")]];
    [ADOptionSheet showIn:self title:@"显示方式" options:opts destructive:-1 choose:^(NSInteger i) {
        self.mode = i;
        [self reloadData];
    }];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [ADHaptic heavy];
    CGPoint p = [g locationInView:self.cv];
    NSIndexPath *ip = [self.cv indexPathForItemAtPoint:p];
    if (!ip || ip.item >= (NSInteger)self.items.count) return;
    ADAlbum *a = self.items[ip.item];
    [self menuFor:a];
}

- (void)menuFor:(ADAlbum *)a {
    ADStore *st = [ADStore shared];
    BOOL fav = [st isFavorite:a.albumId];
    BOOL want = [st isWanted:a.albumId];
    BOOL pin = [st isPinned:a.albumId];
    ADTask *task = [[ADDownloader shared] taskForAlbum:a.albumId];
    NSMutableArray *opts = [NSMutableArray array];
    [opts addObject:(fav ? @"取消收藏" : @"收藏")];
    [opts addObject:(want ? @"取消想听" : @"加入想听")];
    [opts addObject:@"删除下载"];
    [opts addObject:(pin ? @"取消置顶" : @"置顶")];
    [opts addObject:@"从书架移除"];
    NSInteger dl = 2, del = 4;
    if (!task || task.done <= 0) opts[dl] = @"删除下载（未下载）";
    [ADOptionSheet showIn:self title:a.title options:opts destructive:del choose:^(NSInteger i) {
        if (i == 0) [st toggleFavorite:a];
        else if (i == 1) [st toggleWant:a];
        else if (i == dl) {
            if (task && task.done > 0) [[ADDownloader shared] deleteTask:task];
        }
        else if (i == 3) [st togglePin:a.albumId];
        else [st removeHistory:a.albumId];
        if (i == del) [ADHaptic warning]; else [ADHaptic success];
        [self reloadData];
    }];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.items.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADShelfCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"shelf" forIndexPath:ip];
    [c fill:self.items[ip.item] mode:self.mode width:self.lo.itemSize.width];
    return c;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.items[ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
