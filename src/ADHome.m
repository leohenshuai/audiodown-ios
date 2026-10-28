#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "ADInternal.h"

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
@property (nonatomic, assign) NSInteger catSel;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, assign) NSInteger heroPage;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *heroViews;   // 每张继续收听大卡的可刷新控件
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@property (nonatomic, assign) BOOL needsSetup;
@property (nonatomic, strong) NSMutableArray<ADContinueCard *> *cards;
@property (nonatomic, assign) NSInteger loadGen;      // 每次拉取编号,旧的自动作废
@property (nonatomic, assign) NSInteger netFails;     // 连续失败次数,决定重试节奏
@property (nonatomic, strong) NSMutableDictionary *kwCache;   // 关键词分类:title → NSArray<ADAlbum*>
@property (nonatomic, strong) NSMutableSet *kwLoading;        // 正在请求的关键词分类 title
@property (nonatomic, assign) CGFloat tabsX;
@property (nonatomic, strong) NSMutableDictionary *kwEmpty;
@property (nonatomic, copy) NSString *catSelTitle;                  // 分类页签横向滚动位置
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
    self.kwCache = [NSMutableDictionary dictionary];
    self.kwLoading = [NSMutableSet set];
    self.kwEmpty = [NSMutableDictionary dictionary];
    self.tabsX = 0;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadCards) name:@"ADContinueChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshCards) name:@"ADPlayerTick" object:nil];
    // 从后台回来、网络恢复后,自动再拉一次,不用用户杀进程重开
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onForeground) name:UIApplicationDidBecomeActiveNotification object:nil];

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

- (void)onForeground {
    if (!self.sections.count) [self load];
    else if (self.netFails > 0) [self load];
}

- (void)reloadCards { [self build]; }
- (void)refreshCards { for (ADContinueCard *c in self.cards) [c refresh]; [self refreshHero]; }

- (void)load {
    self.loadGen += 1;
    NSInteger gen = self.loadGen;
    // 没有板块数据时(断网/失败),顺带清掉关键词分类的空结果,等这次拉通后重新搜
    if (self.refresh.isRefreshing || !self.sections.count) {
        [self.kwCache removeAllObjects];
        [self.kwEmpty removeAllObjects];
    }
    if (!self.sections.count) [self.spin startAnimating];
    __weak typeof(self) w = self;
    [[ADApi shared] discover:^(NSArray<NSDictionary *> *sections, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self || gen != self.loadGen) return;
        [self.spin stopAnimating];
        [self.refresh endRefreshing];
        if (sections.count) {
            self.sections = sections;
            self.netFails = 0;
            self.hint.text = @"";
            [self build];
            return;
        }
        self.netFails += 1;
        self.hint.text = [self netHintWith:err];
        [self retryLater];
    }];
}

- (NSString *)netHintWith:(NSString *)err {
    if (!err.length) return @"没有内容";
    if ([err isEqualToString:@"网络未连接"]) return @"网络未连接，恢复后会自动刷新";
    if ([err isEqualToString:@"请求超时"] || [err isEqualToString:@"连不上服务器"]) return [NSString stringWithFormat:@"%@，正在自动重试…", err];
    return [NSString stringWithFormat:@"%@，正在自动重试…", err];
}

// 失败后自动重试:2、4、6…最多 15 秒一次;应用在后台时暂停,回到前台由 onForeground 接着拉
- (void)retryLater {
    if (!self.sections.count) self.hint.text = self.hint.text.length ? self.hint.text : @"正在重试…";
    if (self.netFails > 200) return;
    NSInteger gen = self.loadGen;
    NSTimeInterval wait = MIN(15.0, 2.0 * self.netFails);
    __weak typeof(self) w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        if (gen != self.loadGen) return;                                    // 已经有更新的请求了
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        [self load];
    });
}

// 首页分类(E 样式):文字页签 → 本类精选大卡 → 热门榜前 5,数据全部来自发现页板块
- (NSArray<ADAlbum *> *)albumsOfSection:(NSDictionary *)sec {
    id pre = sec[@"albums"];
    if ([pre isKindOfClass:NSArray.class]) return (NSArray<ADAlbum *> *)pre;
    NSMutableArray *out = [NSMutableArray array];
    NSArray *its = sec[@"items"];
    if ([its isKindOfClass:NSArray.class]) for (id o in its) { ADAlbum *a = [ADAlbum fromJSON:o]; if (a) [out addObject:a]; }
    return out;
}

// 12 个关键词分类:点选后用搜索接口取书
- (NSArray<NSDictionary *> *)kwCats {
    return @[
        @{@"title": @"悬疑", @"words": @[@"悬疑", @"推理", @"鬼故事"]},
        @{@"title": @"盗墓", @"words": @[@"盗墓", @"探险"]},
        @{@"title": @"玄幻", @"words": @[@"玄幻", @"修仙"]},
        @{@"title": @"都市", @"words": @[@"都市", @"逆袭"]},
        @{@"title": @"言情", @"words": @[@"言情", @"总裁"]},
        @{@"title": @"历史", @"words": @[@"历史", @"三国", @"通史"]},
        @{@"title": @"武侠", @"words": @[@"武侠", @"江湖"]},
        @{@"title": @"科幻", @"words": @[@"科幻", @"末日"]},
        @{@"title": @"广播剧", @"words": @[@"广播剧"]},
        @{@"title": @"国学", @"words": @[@"国学", @"诗词"]},
        @{@"title": @"财经", @"words": @[@"财经", @"商业"]},
        @{@"title": @"心理", @"words": @[@"心理", @"情商"]},
    ];
}

- (NSArray<NSDictionary *> *)catSections {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *taken = [NSMutableSet set];
    for (NSDictionary *sec in self.sections) {
        NSArray *its = sec[@"items"];
        if ([its isKindOfClass:NSArray.class] && its.count && [sec[@"title"] length]) {
            [out addObject:sec];
            [taken addObject:sec[@"title"]];
        }
    }
    // 服务端板块之后追加关键词分类(同名跳过)
    for (NSDictionary *k in [self kwCats]) {
        NSString *title = k[@"title"];
        if (![title isKindOfClass:NSString.class] || !title.length) continue;
        if ([taken containsObject:title]) continue;
        NSMutableDictionary *sec = [NSMutableDictionary dictionary];
        sec[@"title"] = title;
        sec[@"rankTitle"] = [title stringByAppendingString:@"热门"];
        sec[@"hotWords"] = [k[@"words"] isKindOfClass:NSArray.class] ? k[@"words"] : @[];
        sec[@"kw"] = @YES;
        NSArray *cached = self.kwCache[title];
        if ([cached isKindOfClass:NSArray.class] && cached.count) sec[@"albums"] = cached;
        [out addObject:sec];
        [taken addObject:title];
    }
    return out;
}

// ── 关键词分类取书:并行搜索,回调可能来两次(先缓存后网络),容忍 ──
- (void)loadKw:(NSDictionary *)sec {
    NSString *title = sec[@"title"];
    if (![title isKindOfClass:NSString.class] || !title.length) return;
    if (self.kwCache[title] || self.kwEmpty[title]) return;
    if ([self.kwLoading containsObject:title]) return;
    NSArray *raw = sec[@"hotWords"];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) for (id w in raw) if ([w isKindOfClass:NSString.class] && [w length]) [words addObject:w];
    if (!words.count) return;
    [self.kwLoading addObject:title];

    NSMutableArray *slots = [NSMutableArray array];   // 每个词一袋结果,占位 NSNull
    for (NSInteger i = 0; i < (NSInteger)words.count; i++) [slots addObject:[NSNull null]];
    NSInteger total = (NSInteger)words.count;
    __block NSInteger done = 0;
    __weak typeof(self) w = self;
    for (NSInteger i = 0; i < total; i++) {
        NSString *q = words[i];
        __block BOOL got = NO;                        // 该词是否已采纳结果
        __block NSInteger cbCount = 0;                // 该词回调次数(缓存一次 + 网络一次)
        [[ADApi shared] search:q page:1 done:^(NSArray<ADAlbum *> *list, BOOL more, BOOL cached, NSString *err) {
            BOOL ok = [list isKindOfClass:NSArray.class] && list.count > 0;
            NSInteger left = 0;
            @synchronized (slots) {
                if (got && !cached && cbCount == 1 && ok) {   // 先用了缓存,网络新结果到了:替换并刷新缓存
                    cbCount += 1; slots[i] = [list copy];
                    __strong typeof(w) self = w;
                    if (self && self.kwCache[title]) { [self.kwCache removeObjectForKey:title]; [self.kwLoading addObject:title]; [self finishKw:title slots:slots]; }
                    return;
                }
                if (got) return;
                cbCount += 1;
                if (!ok && cached && cbCount == 1) return;   // 先到的缓存空结果:等网络那次,不计数
                got = YES;
                if (ok) slots[i] = [list copy];
                else slots[i] = @[];
                done += 1;
                left = total - done;
            }
            if (left > 0) return;
            __strong typeof(w) self = w; if (!self) return;
            [self finishKw:title slots:slots];
        }];
    }
    // 兜底:网络长时间无回音也别卡在“加载中”
    __weak typeof(self) w2 = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(w2) self = w2; if (!self) return;
        [self finishKw:title slots:slots];
    });
}

// 合并各词结果并按 playCount 降序,写缓存;主线程执行且只生效一次
- (void)finishKw:(NSString *)title slots:(NSArray *)slots {
    __weak typeof(self) w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        if (![self.kwLoading containsObject:title]) return;   // 已经处理过
        [self.kwLoading removeObject:title];
        if (!self.kwCache) self.kwCache = [NSMutableDictionary dictionary];
        NSMutableArray<ADAlbum *> *all = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (id bag in slots) {
            if (![bag isKindOfClass:NSArray.class]) continue;
            for (id o in (NSArray *)bag) {
                if (![o isKindOfClass:ADAlbum.class]) continue;
                ADAlbum *a = (ADAlbum *)o;
                NSString *key = a.albumId.length ? a.albumId : a.title;
                if (!key.length || [seen containsObject:key]) continue;
                [seen addObject:key];
                [all addObject:a];
            }
        }
        NSArray<ADAlbum *> *sorted = [all sortedArrayUsingComparator:^NSComparisonResult(ADAlbum *a, ADAlbum *b) {
            return [@(b.playCount) compare:@(a.playCount)];
        }];
        if (sorted.count) self.kwCache[title] = sorted;
        else self.kwEmpty[title] = @YES;   // 本次没搜到:显示空态,下拉刷新后重试
        NSArray<NSDictionary *> *secs = [self catSections];
        if (self.catSel >= 0 && self.catSel < (NSInteger)secs.count) {
            NSDictionary *cur = secs[self.catSel];
            if ([cur[@"kw"] boolValue] && [cur[@"title"] isEqualToString:title]) {
                CGPoint off = self.scroll.contentOffset;
                [self build];
                self.scroll.contentOffset = off;
            }
        }
    });
}

- (CGFloat)buildCats:(CGFloat)y width:(CGFloat)W {
    NSArray<NSDictionary *> *secs = [self catSections];
    if (!secs.count) return y;
    if (self.catSelTitle.length) {
        for (NSInteger i = 0; i < (NSInteger)secs.count; i++)
            if ([secs[i][@"title"] isEqualToString:self.catSelTitle]) { self.catSel = i; break; }
    }
    if (self.catSel >= (NSInteger)secs.count) self.catSel = 0;
    NSDictionary *sec = secs[self.catSel];
    UIColor *brand = [ADUtil brand];

    // 文字页签
    UIScrollView *tabs = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, W, 40)];
    tabs.showsHorizontalScrollIndicator = NO;
    CGFloat x = 16;
    for (NSInteger i = 0; i < (NSInteger)secs.count; i++) {
        BOOL on = (i == self.catSel);
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        UIFont *fnt = on ? [UIFont systemFontOfSize:18 weight:UIFontWeightBold] : [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        NSString *t = secs[i][@"title"];
        CGFloat tw = ceil([t sizeWithAttributes:@{NSFontAttributeName: fnt}].width);
        b.frame = CGRectMake(x, 0, tw, 34);
        b.titleLabel.font = fnt;
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:(on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.45]) forState:UIControlStateNormal];
        b.tag = 7000 + i;
        [b addTarget:self action:@selector(tapCatTab:) forControlEvents:UIControlEventTouchUpInside];
        [tabs addSubview:b];
        if (on) {
            UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(x + tw / 2 - 10, 34, 20, 3)];
            bar.backgroundColor = brand; bar.layer.cornerRadius = 1.5;
            [tabs addSubview:bar];
        }
        x += tw + 22;
    }
    tabs.contentSize = CGSizeMake(x, 40);
    tabs.contentOffset = CGPointMake(MIN(self.tabsX, MAX(0, tabs.contentSize.width - W)), 0);
    [self.scroll addSubview:tabs];
    UIButton *selBtn = (UIButton *)[tabs viewWithTag:7000 + self.catSel];
    if (selBtn) [tabs scrollRectToVisible:CGRectInset(selBtn.frame, -40, 0) animated:NO];
    y += 52;

    NSString *secTitle = sec[@"title"];
    BOOL kwCached = (secTitle.length && (self.kwCache[secTitle] != nil || self.kwEmpty[secTitle] != nil));
    BOOL kwPending = [sec[@"kw"] boolValue] && ![sec[@"albums"] isKindOfClass:NSArray.class] && !kwCached;
    if (kwPending) [self loadKw:sec];

    NSArray<ADAlbum *> *all = [self albumsOfSection:sec];
    NSArray<ADAlbum *> *rank = [all sortedArrayUsingComparator:^NSComparisonResult(ADAlbum *a, ADAlbum *b) {
        return [@(b.playCount) compare:@(a.playCount)];
    }];
    ADAlbum *hero = rank.firstObject;

    // 继续收听翻页卡(有收听记录时替代精选大卡)
    NSArray *conts = [self continueItems];
    if (conts.count) {
        y = [self buildContinuePager:conts y:y width:W];
        hero = nil;
    }
    // 关键词分类还没取到书:原精选/榜单的位置放加载提示
    if (kwPending) {
        UILabel *loading = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.45]];
        loading.text = @"加载中…";
        loading.textAlignment = NSTextAlignmentCenter;
        loading.frame = CGRectMake(16, y, W - 32, 120);
        [self.scroll addSubview:loading];
        return y + 120 + 22;
    }
    if ([sec[@"kw"] boolValue] && !all.count) {
        UILabel *empty = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.45]];
        empty.text = @"这个分类暂时没搜到内容";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.frame = CGRectMake(16, y, W - 32, 120);
        [self.scroll addSubview:empty];
        return y + 120 + 22;
    }
    // 精选大卡:虚化封面做底
    if (hero) {
        UIControl *card = [[UIControl alloc] initWithFrame:CGRectMake(16, y, W - 32, 200)];
        card.layer.cornerRadius = 24; card.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
        card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        UIImageView *bg = [[UIImageView alloc] initWithFrame:CGRectInset(card.bounds, -40, -40)];
        bg.contentMode = UIViewContentModeScaleAspectFill;
        bg.userInteractionEnabled = NO;
        [ADUtil cover:bg url:hero.cover];
        [card addSubview:bg];
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.frame = card.bounds; blur.userInteractionEnabled = NO;
        [card addSubview:blur];
        UIView *dim = [[UIView alloc] initWithFrame:card.bounds];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18]; dim.userInteractionEnabled = NO;
        [card addSubview:dim];
        card.layer.borderWidth = 0.6; card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;

        UIView *shadow = [[UIView alloc] initWithFrame:CGRectMake(16, 24, 132, 132)];
        shadow.userInteractionEnabled = NO;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor; shadow.layer.shadowOpacity = 0.45;
        shadow.layer.shadowRadius = 10; shadow.layer.shadowOffset = CGSizeMake(0, 6);
        UIImageView *cv = [[UIImageView alloc] initWithFrame:shadow.bounds];
        cv.layer.cornerRadius = 14; cv.clipsToBounds = YES; cv.contentMode = UIViewContentModeScaleAspectFill;
        [ADUtil cover:cv url:hero.cover];
        [shadow addSubview:cv];
        [card addSubview:shadow];

        CGFloat tx = 166, tw = W - 32 - tx - 14;
        UILabel *k = [ADUtil label:nil size:11.5 color:brand];
        k.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
        k.text = [NSString stringWithFormat:@"%@精选", sec[@"title"]];
        k.frame = CGRectMake(tx, 26, tw, 16);
        UILabel *tt = [ADUtil label:@"PingFangSC-Semibold" size:19 color:UIColor.whiteColor];
        tt.numberOfLines = 2; tt.text = hero.title;
        CGSize ts = [tt sizeThatFits:CGSizeMake(tw, 54)];
        tt.frame = CGRectMake(tx, 46, tw, MIN(ts.height, 52));
        UILabel *intro = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.72]];
        intro.numberOfLines = 2;
        intro.text = hero.intro.length ? hero.intro : (hero.anchor ?: @"");
        intro.frame = CGRectMake(tx, CGRectGetMaxY(tt.frame) + 4, tw, 36);
        UILabel *meta = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.5]];
        NSMutableArray *m = [NSMutableArray array];
        if (hero.trackCount > 0) [m addObject:[NSString stringWithFormat:@"%ld 集", (long)hero.trackCount]];
        if (hero.playCount > 0) [m addObject:[NSString stringWithFormat:@"%@次播放", [ADUtil count:hero.playCount]]];
        meta.text = [m componentsJoinedByString:@" · "];
        meta.frame = CGRectMake(tx, 136, tw, 16);
        for (UIView *v in @[k, tt, intro, meta]) { v.userInteractionEnabled = NO; [card addSubview:v]; }

        UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
        play.frame = CGRectMake(16, 164, 104, 26);
        play.backgroundColor = [UIColor colorWithWhite:1 alpha:0.94];
        play.layer.cornerRadius = 13;
        play.tintColor = [UIColor colorWithWhite:0.08 alpha:1];
        play.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        [play setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        [play setTitle:@" 立即收听" forState:UIControlStateNormal];
        [play addTarget:self action:@selector(playHero) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:play];

        [card addTarget:self action:@selector(openHero) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:card];
        y += 200 + 24;
    }

    // 热门榜
    UILabel *rt = [ADUtil label:@"PingFangSC-Semibold" size:20 color:UIColor.whiteColor];
    rt.frame = CGRectMake(16, y, 200, 28);
    rt.text = sec[@"rankTitle"] && [sec[@"rankTitle"] length] ? sec[@"rankTitle"] : @"热门榜";
    [self.scroll addSubview:rt];
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.frame = CGRectMake(W - 16 - 110, y, 110, 28);
    more.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    more.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    more.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
    [more setTitle:@"全部 ›" forState:UIControlStateNormal];
    [more addTarget:self action:@selector(openCatAll) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:more];
    y += 40;

    NSInteger n = MIN(5, (NSInteger)rank.count);
    for (NSInteger i = 0; i < n; i++) {
        ADAlbum *a = rank[i];
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0, y, W, 70)];
        row.tag = 7100 + i;
        UILabel *no = [ADUtil label:nil size:22 color:(i < 3 ? brand : [UIColor colorWithWhite:1 alpha:0.35])];
        no.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        no.textAlignment = NSTextAlignmentCenter;
        no.text = [NSString stringWithFormat:@"%ld", (long)i + 1];
        no.frame = CGRectMake(10, 14, 28, 28);
        UIImageView *cv = [[UIImageView alloc] initWithFrame:CGRectMake(44, 0, 56, 56)];
        cv.layer.cornerRadius = 10; cv.clipsToBounds = YES; cv.contentMode = UIViewContentModeScaleAspectFill;
        cv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        [ADUtil cover:cv url:a.cover];
        UILabel *tt = [ADUtil label:nil size:15 color:UIColor.whiteColor];
        tt.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        tt.text = a.title; tt.frame = CGRectMake(112, 7, W - 112 - 16, 20);
        UILabel *sb = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.48]];
        NSMutableArray *m = [NSMutableArray array];
        if (a.trackCount > 0) [m addObject:[NSString stringWithFormat:@"%ld 集", (long)a.trackCount]];
        if (a.playCount > 0) [m addObject:[NSString stringWithFormat:@"%@次", [ADUtil count:a.playCount]]];
        if (a.anchor.length) [m addObject:a.anchor];
        sb.text = [m componentsJoinedByString:@" · "]; sb.frame = CGRectMake(112, 31, W - 112 - 16, 16);
        for (UIView *v in @[no, cv, tt, sb]) { v.userInteractionEnabled = NO; [row addSubview:v]; }
        if (i < n - 1) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(112, 63, W - 112 - 16, 0.5)];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1]; line.userInteractionEnabled = NO;
            [row addSubview:line];
        }
        [row addTarget:self action:@selector(openRank:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:row];
        y += 70;
    }
    return y + 22;
}

- (NSArray *)continueItems {
    NSMutableArray *items = [NSMutableArray array];
    for (ADAlbum *a in [ADStore shared].history) {
        NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
        if (info) [items addObject:@[a, info]];
        if (items.count >= 10) break;
    }
    return items;
}

// 与精选大卡同样式:虚化封面做底 + 左封面 + 右文字,左右翻页
- (CGFloat)buildContinuePager:(NSArray *)items y:(CGFloat)y width:(CGFloat)W {
    CGFloat cw = W - 32, ch = 200, gap = 12;
    self.heroViews = [NSMutableArray array];
    UIScrollView *pg = [[UIScrollView alloc] initWithFrame:CGRectMake(16, y, cw + gap, ch)];
    pg.pagingEnabled = YES;
    pg.clipsToBounds = NO;
    pg.showsHorizontalScrollIndicator = NO;
    pg.delegate = self;
    pg.contentSize = CGSizeMake(items.count * (cw + gap), ch);
    UIColor *brand = [ADUtil brand];
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        ADAlbum *a = items[i][0];
        NSDictionary *info = items[i][1];
        UIControl *card = [[UIControl alloc] initWithFrame:CGRectMake(i * (cw + gap), 0, cw, ch)];
        card.tag = 7200 + i;
        card.layer.cornerRadius = 24; card.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
        card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        card.layer.borderWidth = 0.6; card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        UIImageView *bg = [[UIImageView alloc] initWithFrame:CGRectInset(card.bounds, -40, -40)];
        bg.contentMode = UIViewContentModeScaleAspectFill; bg.userInteractionEnabled = NO;
        [ADUtil cover:bg url:a.cover];
        [card addSubview:bg];
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.frame = card.bounds; blur.userInteractionEnabled = NO;
        [card addSubview:blur];
        UIView *dim = [[UIView alloc] initWithFrame:card.bounds];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18]; dim.userInteractionEnabled = NO;
        [card addSubview:dim];

        UIView *shadow = [[UIView alloc] initWithFrame:CGRectMake(16, 20, 132, 132)];
        shadow.userInteractionEnabled = NO;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor; shadow.layer.shadowOpacity = 0.45;
        shadow.layer.shadowRadius = 10; shadow.layer.shadowOffset = CGSizeMake(0, 6);
        UIImageView *cv = [[UIImageView alloc] initWithFrame:shadow.bounds];
        cv.layer.cornerRadius = 14; cv.clipsToBounds = YES; cv.contentMode = UIViewContentModeScaleAspectFill;
        [ADUtil cover:cv url:a.cover];
        [shadow addSubview:cv];
        [card addSubview:shadow];

        CGFloat tx = 164, tw = cw - tx - 16;
        NSInteger idx = [info[@"index"] integerValue];
        UILabel *k = [ADUtil label:nil size:11.5 color:brand];
        k.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
        k.text = [NSString stringWithFormat:@"继续收听 · 第 %ld 集", (long)idx + 1];
        k.frame = CGRectMake(tx, 22, tw, 16);
        UILabel *tt = [ADUtil label:@"PingFangSC-Semibold" size:18 color:UIColor.whiteColor];
        tt.numberOfLines = 2; tt.lineBreakMode = NSLineBreakByTruncatingTail; tt.text = a.title;
        CGSize ts = [tt sizeThatFits:CGSizeMake(tw, 52)];
        tt.frame = CGRectMake(tx, 42, tw, MIN(ts.height, 50));
        UILabel *chap = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.72]];
        chap.numberOfLines = 2;
        NSString *ct = info[@"title"];
        chap.text = ct.length ? ct : (a.anchor ?: @"");
        chap.frame = CGRectMake(tx, CGRectGetMaxY(tt.frame) + 4, tw, 34);
        UIView *track = [[UIView alloc] initWithFrame:CGRectMake(tx, 132, tw, 4)];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16]; track.layer.cornerRadius = 2; track.clipsToBounds = YES;
        UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 4)];
        fill.backgroundColor = brand; fill.layer.cornerRadius = 2;
        [track addSubview:fill];
        UILabel *tm = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.5]];
        tm.frame = CGRectMake(tx, 142, tw, 16);
        for (UIView *v in @[k, tt, chap, track, tm]) { v.userInteractionEnabled = NO; [card addSubview:v]; }

        UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
        play.frame = CGRectMake(16, 164, 104, 26);
        play.backgroundColor = [UIColor colorWithWhite:1 alpha:0.94];
        play.layer.cornerRadius = 13;
        play.tintColor = [UIColor colorWithWhite:0.08 alpha:1];
        play.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        play.tag = 7300 + i;
        [play addTarget:self action:@selector(tapContPlay:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:play];

        UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
        more.frame = CGRectMake(cw - 50, ch - 38, 40, 30);
        more.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
        [more setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        more.tag = 7400 + i;
        [more addTarget:self action:@selector(tapContMore:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:more];

        [card addTarget:self action:@selector(tapContCard:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longContCard:)];
        [card addGestureRecognizer:lp];
        [pg addSubview:card];
        [self.heroViews addObject:@{@"album": a, @"fill": fill, @"track": track, @"time": tm, @"play": play, @"k": k}];
    }
    [self.scroll addSubview:pg];
    self.pager = pg;
    NSInteger page = MIN(self.heroPage, (NSInteger)items.count - 1);
    pg.contentOffset = CGPointMake(page * (cw + gap), 0);
    y += ch;
    if (items.count > 1) {
        UIPageControl *dots = [[UIPageControl alloc] initWithFrame:CGRectMake(0, y + 2, W, 20)];
        dots.numberOfPages = items.count;
        dots.currentPage = page;
        dots.hidesForSinglePage = YES;
        dots.pageIndicatorTintColor = [UIColor colorWithWhite:1 alpha:0.25];
        dots.currentPageIndicatorTintColor = UIColor.whiteColor;
        dots.userInteractionEnabled = NO;
        if (@available(iOS 14.0, *)) dots.backgroundStyle = UIPageControlBackgroundStyleMinimal;
        dots.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [self.scroll addSubview:dots];
        self.dots = dots;
        y += 22;
    } else self.dots = nil;
    [self refreshHero];
    return y + 22;
}

- (void)refreshHero {
    ADPlayer *p = ADPlayer.shared;
    for (NSDictionary *h in self.heroViews) {
        ADAlbum *a = h[@"album"];
        BOOL cur = p.album && [p.album.albumId isEqualToString:a.albumId];
        NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId] ?: @{};
        double sec = [info[@"seconds"] doubleValue], dur = [info[@"duration"] doubleValue];
        NSInteger idx = [info[@"index"] integerValue];
        if (cur && p.isPlaying) {
            AVPlayerItem *it = p.player.currentItem;
            double ps = it ? CMTimeGetSeconds(it.currentTime) : 0, pd = it ? CMTimeGetSeconds(it.duration) : 0;
            if (isnan(ps)) ps = 0;
            if (isnan(pd)) pd = 0;
            if (pd > 0) { sec = ps; dur = pd; }
            idx = p.index + p.episodeBase;
        }
        UIView *track = h[@"track"], *fill = h[@"fill"];
        CGFloat r = dur > 0 ? MIN(1, sec / dur) : 0;
        fill.frame = CGRectMake(0, 0, MAX(4, track.bounds.size.width * r), 4);
        UILabel *tm = h[@"time"];
        tm.text = dur > 0 ? [NSString stringWithFormat:@"%@ / %@", [ADUtil time:sec], [ADUtil time:dur]] : [NSString stringWithFormat:@"听到 %@", [ADUtil time:sec]];
        ((UILabel *)h[@"k"]).text = [NSString stringWithFormat:@"%@ · 第 %ld 集", (cur && p.isPlaying) ? @"正在播放" : @"继续收听", (long)idx + 1];
        UIButton *b = h[@"play"];
        BOOL playing = cur && p.isPlaying;
        [b setImage:[UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        [b setTitle:(playing ? @" 暂停" : @" 继续播放") forState:UIControlStateNormal];
    }
}

- (ADAlbum *)contAlbum:(NSInteger)i { return (i >= 0 && i < (NSInteger)self.heroViews.count) ? self.heroViews[i][@"album"] : nil; }
- (void)tapContPlay:(UIButton *)b { ADAlbum *a = [self contAlbum:b.tag - 7300]; if (!a) return; [ADHaptic tap]; [self playCard:a]; [self refreshHero]; }
- (void)tapContMore:(UIButton *)b { ADAlbum *a = [self contAlbum:b.tag - 7400]; if (a) [self moreCard:a]; }
- (void)tapContCard:(UIControl *)c { [self openAlbumVC:[self contAlbum:c.tag - 7200]]; }
- (void)longContCard:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    ADAlbum *a = [self contAlbum:g.view.tag - 7200];
    if (!a) return;
    [ADHaptic heavy];
    [self menuCard:a];
}

- (NSArray<ADAlbum *> *)curRank {
    NSArray *secs = [self catSections];
    if (self.catSel >= (NSInteger)secs.count) return @[];
    return [[self albumsOfSection:secs[self.catSel]] sortedArrayUsingComparator:^NSComparisonResult(ADAlbum *a, ADAlbum *b) {
        return [@(b.playCount) compare:@(a.playCount)];
    }];
}
- (void)tapCatTab:(UIButton *)b {
    NSInteger i = b.tag - 7000;
    if (i == self.catSel) return;
    [ADHaptic select];
    if ([b.superview isKindOfClass:UIScrollView.class]) self.tabsX = ((UIScrollView *)b.superview).contentOffset.x;
    self.catSel = i;
    NSArray *allSecs = [self catSections];
    self.catSelTitle = (i >= 0 && i < (NSInteger)allSecs.count) ? allSecs[i][@"title"] : nil;
    CGPoint off = self.scroll.contentOffset;
    [UIView transitionWithView:self.scroll duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self build];
        self.scroll.contentOffset = off;
    } completion:nil];
}
- (void)openAlbumVC:(ADAlbum *)a {
    if (!a) return;
    [ADHaptic tap];
    ADAlbumController *vc = [ADAlbumController new]; vc.album = a;
    [self.navigationController pushViewController:vc animated:YES];
}
- (void)openHero { [self openAlbumVC:[self curRank].firstObject]; }
- (void)playHero {
    ADAlbum *a = [self curRank].firstObject;
    if (!a) return;
    [ADHaptic tap];
    if ([[ADStore shared] lastInfoOf:a.albumId]) [self playCard:a];
    else [self playFromStart:a];
}
- (void)openRank:(UIControl *)r {
    NSArray *rk = [self curRank];
    NSInteger i = r.tag - 7100;
    if (i >= 0 && i < (NSInteger)rk.count) [self openAlbumVC:rk[i]];
}
- (void)openCatAll {
    NSArray *secs = [self catSections];
    if (self.catSel >= (NSInteger)secs.count) return;
    NSDictionary *sec = secs[self.catSel];
    [ADHaptic tap];
    ADCategoryController *vc = [ADCategoryController new];
    vc.catTitle = sec[@"title"];
    vc.seed = [self curRank];
    NSArray *hw = sec[@"hotWords"];
    NSMutableArray *kw = [NSMutableArray array];
    if ([hw isKindOfClass:NSArray.class]) for (id w in hw) if ([w isKindOfClass:NSString.class] && [w length]) [kw addObject:w];
    if (!kw.count) [kw addObjectsFromArray:[ADCategoryController keywordsFor:sec[@"title"]]];
    vc.keywords = kw;
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
    CGFloat hintY = y;


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

    py += 110;
    CGRect pf = panel.frame;
    pf.size.height = py;
    panel.frame = pf;
    self.scroll.contentSize = CGSizeMake(W, y + py);

    self.hint.frame = CGRectMake(24, hintY + 6, W - 48, 44);   // 放在内容区,不压卡片
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
    if (s == self.pager) {
        CGFloat pw = s.bounds.size.width;
        NSInteger pg = pw > 0 ? (NSInteger)lround(s.contentOffset.x / pw) : 0;
        if (pg != self.dots.currentPage && pg >= 0) { self.dots.currentPage = pg; [ADHaptic select]; }
        self.heroPage = MAX(0, pg);
        return;
    }
    static CGFloat lastY = 0;
    [ADLiquid followScroll:s lastY:&lastY];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)s {
    if (s == self.pager) return;
    [UIView animateWithDuration:0.3 animations:^{ ADNavDock.shared.transform = CGAffineTransformIdentity; ADNavDock.shared.alpha = 1; }];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)s willDecelerate:(BOOL)d {
    if (s == self.pager) return;
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
    [ADMiniBar.shared unfoldNow];   // 点继续播放时,右下角收起的播放条展开一下(8 秒后自动再收)
    if (p.album && [p.album.albumId isEqualToString:a.albumId]) { [p toggle]; [self refreshCards]; return; }
    // 交给播放器自己去按书签定位：它会翻到第 index/50+1 页，不会只拿第 1 页
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    [ADPlayer.shared openAlbum:a trackId:info[@"trackId"] index:[info[@"index"] integerValue] seconds:[info[@"seconds"] doubleValue] autoPlay:YES];
    [self refreshCards];
}

- (void)moreCard:(ADAlbum *)a { [ADHaptic tap]; [self menuCard:a]; }
@end
