#import "AD.h"

// ─────────────────────────────────────────────────────────────
//  ADLiquid —— iOS 26 风格设计系统（iOS 14+ 兼容实现）
//  这里所有的材质、动效都是新写的；不复用 4.x 的任何代码。
// ─────────────────────────────────────────────────────────────

static NSInteger const kBlurTag  = 9821;
static NSInteger const kTintTag  = 9822;
static NSInteger const kRimTag   = 9823;
static NSInteger const kMarkTag  = 9820;
static NSInteger const kSpecTag  = 9824;
static NSInteger const kLiteTag  = 9825;

#pragma mark - 渐变视图（自带 CAGradientLayer，随尺寸自适应）

@interface ADGradientView : UIView
- (CAGradientLayer *)grad;
@end

@implementation ADGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
- (CAGradientLayer *)grad { return (CAGradientLayer *)self.layer; }
@end

#pragma mark - 悬浮导航胶囊

@interface ADNavDock ()
- (void)layoutIn:(UITabBarController *)tab;
- (void)movePill:(BOOL)animated;
- (void)paint:(BOOL)animated;
@end

@implementation ADNavDock {
    UIView *_pill;
    NSMutableArray<UIButton *> *_items;
}

+ (instancetype)shared {
    static ADNavDock *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[ADNavDock alloc] initWithFrame:CGRectMake(0, 0, 320, 62)];
        [d build];
    });
    return d;
}

- (void)build {
    _dockVisible = YES;
    [ADLiquid glass:self radius:31 alpha:0.05];
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.55;
    self.layer.shadowRadius = 28;
    self.layer.shadowOffset = CGSizeMake(0, 14);

    _pill = [[UIView alloc] initWithFrame:CGRectZero];
    _pill.layer.cornerRadius = 21;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.layer.borderWidth = 0.6;
    _pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.20].CGColor;
    _pill.userInteractionEnabled = NO;
    ADGradientView *pg = [[ADGradientView alloc] initWithFrame:CGRectZero];
    pg.tag = 7701;
    pg.userInteractionEnabled = NO;
    pg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pg.grad.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.20].CGColor,
                       (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor];
    pg.grad.startPoint = CGPointMake(0.2, 0);
    pg.grad.endPoint = CGPointMake(0.8, 1);
    pg.layer.cornerRadius = 21;
    pg.layer.cornerCurve = kCACornerCurveContinuous;
    pg.clipsToBounds = YES;
    [_pill addSubview:pg];
    [self addSubview:_pill];

    _items = [NSMutableArray array];
    NSArray *icons = @[@"sparkles", @"magnifyingglass", @"books.vertical"];
    NSArray *names = @[@"发现", @"搜索", @"书架"];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = i;
        [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *iv = [UIImageView new];
        iv.tag = 31;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.image = [UIImage systemImageNamed:icons[i]
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
        [b addSubview:iv];
        UILabel *l = [ADUtil label:nil size:10 color:UIColor.whiteColor];
        l.tag = 32;
        l.text = names[i];
        l.textAlignment = NSTextAlignmentCenter;
        [b addSubview:l];
        [self addSubview:b];
        [_items addObject:b];
    }
    [self paint:NO];
}

- (void)layoutIn:(UITabBarController *)tab {
    if (!tab) return;
    CGFloat W = tab.view.bounds.size.width;
    CGFloat H = tab.view.bounds.size.height;
    CGFloat sb = tab.view.safeAreaInsets.bottom;
    CGFloat h = 62, side = 26;
    CGFloat y = H - sb - 12 - h;
    self.frame = CGRectMake(side, y, W - side * 2, h);
    [ADLiquid corner:h / 2.0 on:self];

    CGFloat seg = (W - side * 2) / 3.0;
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        UIButton *b = _items[i];
        b.frame = CGRectMake(seg * i, 0, seg, h);
        [b viewWithTag:31].frame = CGRectMake((seg - 22) / 2, 11, 22, 22);
        [b viewWithTag:32].frame = CGRectMake(0, 35, seg, 13);
    }
    [self movePill:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *g = [_pill viewWithTag:7701];
    g.frame = _pill.bounds;
}

- (CGFloat)topY { return self.frame.origin.y; }

- (void)movePill:(BOOL)animated {
    CGFloat seg = self.bounds.size.width / 3.0;
    CGRect r = CGRectMake(seg * self.selectedIndex + (seg - 62) / 2, 9, 62, 44);
    if (!animated || CGRectIsEmpty(_pill.frame)) { _pill.frame = r; return; }
    CGFloat dist = fabs(r.origin.x - _pill.frame.origin.x);
    if (dist < 1) { _pill.frame = r; return; }
    // 第一段：向目标方向拉长（液滴被拖拽）；第二段：弹簧收回到目标宽度
    CGFloat minX = MIN(r.origin.x, _pill.frame.origin.x);
    CGRect stretch = CGRectMake(minX, 11, dist + 62, 40);
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        _pill.frame = stretch;
        _pill.alpha = 0.85;
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.7
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ _pill.frame = r; _pill.alpha = 1; } completion:nil];
    }];
}

- (void)paint:(BOOL)animated {
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        UIButton *b = _items[i];
        BOOL on = (i == self.selectedIndex);
        UIColor *c = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.55];
        UIImageView *iv = [b viewWithTag:31];
        UILabel *l = [b viewWithTag:32];
        iv.tintColor = c;
        l.textColor = c;
        [UIView animateWithDuration:0.2 animations:^{
            iv.transform = on ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
        }];
    }
    [self movePill:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self paint:YES];
}

- (void)tap:(UIButton *)b {
    [ADHaptic select];
    NSInteger idx = b.tag;
    if (idx == self.selectedIndex) {
        UITabBarController *tab = (UITabBarController *)self.window.rootViewController;
        UINavigationController *nav = [tab.selectedViewController isKindOfClass:UINavigationController.class]
            ? (UINavigationController *)tab.selectedViewController : nil;
        if (nav && nav.viewControllers.count > 1) [nav popToRootViewControllerAnimated:YES];
        return;
    }
    self.selectedIndex = idx;
    if (self.onSelect) self.onSelect(idx);
}

- (void)show:(BOOL)show animated:(BOOL)animated {
    _dockVisible = show;
    if (!animated) {
        self.alpha = show ? 1 : 0;
        self.transform = show ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 40);
        return;
    }
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.3
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.alpha = show ? 1 : 0;
        self.transform = show ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 40);
    } completion:nil];
}
@end

#pragma mark - 承载悬浮导航的 Tab 控制器

@implementation ADDockController

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    ADNavDock *dock = [ADNavDock shared];
    if (dock.superview != self.view) {
        [self.view addSubview:dock];
        dock.selectedIndex = self.selectedIndex;
    }
    [dock layoutIn:self];
    [self.view bringSubviewToFront:dock];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    NSInteger old = self.selectedIndex;
    [super setSelectedIndex:selectedIndex];
    if (old != (NSInteger)selectedIndex) [ADNavDock shared].selectedIndex = (NSInteger)selectedIndex;
}

@end

#pragma mark - 设计系统

@interface ADLiquid ()
+ (void)retint:(UIView *)v alpha:(CGFloat)alpha;
+ (void)onPress:(UILongPressGestureRecognizer *)g;
@end

@implementation ADLiquid

+ (void)canvas:(UIView *)v {
    if (!v) return;
    v.backgroundColor = [UIColor colorWithRed:0.024 green:0.024 blue:0.031 alpha:1];
    if ([v viewWithTag:kMarkTag]) return;
    UIView *mark = [UIView new];
    mark.tag = kMarkTag;
    mark.hidden = YES;
    mark.userInteractionEnabled = NO;
    [v addSubview:mark];

    // 主渐变：深蓝黑 → 近黑
    ADGradientView *base = [[ADGradientView alloc] initWithFrame:v.bounds];
    base.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    base.grad.colors = @[(id)[UIColor colorWithRed:0.078 green:0.078 blue:0.106 alpha:1].CGColor,
                         (id)[UIColor colorWithRed:0.024 green:0.024 blue:0.031 alpha:1].CGColor];
    base.grad.startPoint = CGPointMake(0.05, 0);
    base.grad.endPoint = CGPointMake(0.95, 1);
    base.userInteractionEnabled = NO;
    [v insertSubview:base atIndex:0];

    // 左上暖光
    ADGradientView *warm = [[ADGradientView alloc] initWithFrame:CGRectMake(-v.bounds.size.width * 0.35, -v.bounds.size.height * 0.12,
                                                                           v.bounds.size.width * 1.1, v.bounds.size.height * 0.62)];
    warm.grad.type = kCAGradientLayerRadial;
    warm.grad.colors = @[(id)[UIColor colorWithRed:1.0 green:0.46 blue:0.20 alpha:0.22].CGColor,
                         (id)[UIColor colorWithRed:1.0 green:0.46 blue:0.20 alpha:0.0].CGColor];
    warm.grad.startPoint = CGPointMake(0.42, 0.38);
    warm.grad.endPoint = CGPointMake(1, 1);
    warm.userInteractionEnabled = NO;
    [v insertSubview:warm aboveSubview:base];

    // 右侧冷光
    ADGradientView *cool = [[ADGradientView alloc] initWithFrame:CGRectMake(v.bounds.size.width * 0.42, v.bounds.size.height * 0.05,
                                                                           v.bounds.size.width * 0.9, v.bounds.size.height * 0.55)];
    cool.grad.type = kCAGradientLayerRadial;
    cool.grad.colors = @[(id)[UIColor colorWithRed:0.24 green:0.42 blue:1.0 alpha:0.13].CGColor,
                         (id)[UIColor colorWithRed:0.24 green:0.42 blue:1.0 alpha:0.0].CGColor];
    cool.grad.startPoint = CGPointMake(0.5, 0.35);
    cool.grad.endPoint = CGPointMake(1, 1);
    cool.userInteractionEnabled = NO;
    [v insertSubview:cool aboveSubview:warm];

    // 光斑缓慢漂移，制造“液态”感
    CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"position.y"];
    drift.fromValue = @(warm.layer.position.y - 16);
    drift.toValue = @(warm.layer.position.y + 16);
    drift.duration = 9.0;
    drift.autoreverses = YES;
    drift.repeatCount = HUGE_VALF;
    drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [warm.layer addAnimation:drift forKey:@"drift"];
}

+ (void)glass:(UIView *)v radius:(CGFloat)r {
    [self glass:v radius:r alpha:0.05];
}

+ (void)glass:(UIView *)v radius:(CGFloat)r alpha:(CGFloat)alpha {
    if (!v) return;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.cornerRadius = r;
    v.layer.borderWidth = 0.65;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;

    UIVisualEffectView *blur = (UIVisualEffectView *)[v viewWithTag:kBlurTag];
    if (!blur) {
        blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        blur.tag = kBlurTag;
        blur.userInteractionEnabled = NO;
        blur.clipsToBounds = YES;
        [v insertSubview:blur atIndex:0];

        UIView *tint = [UIView new];
        tint.tag = kTintTag;
        tint.userInteractionEnabled = NO;
        [blur.contentView addSubview:tint];

        // 顶部高光（斜向），模拟玻璃边缘的折射
        ADGradientView *spec = [[ADGradientView alloc] initWithFrame:CGRectZero];
        spec.tag = kSpecTag;
        spec.userInteractionEnabled = NO;
        spec.grad.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.20].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.02].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor];
        spec.grad.locations = @[@0, @0.42, @1];
        spec.grad.startPoint = CGPointMake(0.0, 0.0);
        spec.grad.endPoint = CGPointMake(0.35, 1.0);
        [blur.contentView addSubview:spec];
    }
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.layer.cornerRadius = r;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    [self corner:r on:v];
    [self retint:v alpha:alpha];
}

+ (void)retint:(UIView *)v alpha:(CGFloat)alpha {
    UIView *blur = [v viewWithTag:kBlurTag];
    UIView *tint = [blur viewWithTag:kTintTag];
    tint.backgroundColor = [UIColor colorWithWhite:1 alpha:alpha];
    tint.frame = blur.bounds;
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *spec = [blur viewWithTag:kSpecTag];
    if (spec) {
        spec.frame = blur.bounds;
        spec.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [blur bringSubviewToFront:spec];
    }
    [blur bringSubviewToFront:tint];
}

// 轻量玻璃：用渐变 + 描边模拟，零实时模糊。列表行、重复出现的卡片必须用这个，
// 否则每行一个 UIVisualEffectView，滚动会掉帧。
+ (void)glassLite:(UIView *)v radius:(CGFloat)r {
    if (!v) return;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.cornerRadius = r;
    v.layer.borderWidth = 0.65;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.13].CGColor;
    v.layer.masksToBounds = YES;

    ADGradientView *g = (ADGradientView *)[v viewWithTag:kLiteTag];
    if (!g) {
        g = [[ADGradientView alloc] initWithFrame:v.bounds];
        g.tag = kLiteTag;
        g.userInteractionEnabled = NO;
        g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        g.grad.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.115].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.045].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.07].CGColor];
        g.grad.locations = @[@0, @0.55, @1];
        g.grad.startPoint = CGPointMake(0.0, 0.0);
        g.grad.endPoint = CGPointMake(0.7, 1.0);
        [v insertSubview:g atIndex:0];
    }
    g.frame = v.bounds;
}

// 按钮专用：不用模糊子视图（会挡住 UIButton 自带的图标/标题）
+ (void)glassButton:(UIButton *)b radius:(CGFloat)r {
    if (!b) return;
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.cornerRadius = r;
    b.layer.borderWidth = 0.65;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.22;
    b.layer.shadowRadius = 12;
    b.layer.shadowOffset = CGSizeMake(0, 6);
    b.clipsToBounds = NO;
}

+ (void)corner:(CGFloat)r on:(UIView *)v {
    if (!v) return;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.cornerRadius = r;
    UIView *blur = [v viewWithTag:kBlurTag];
    blur.layer.cornerRadius = r;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
}

// 封面主色：缩到 1x1 取平均色，再提亮饱和度，作为页面光斑颜色
+ (UIColor *)tintFromImage:(UIImage *)img {
    if (!img || !img.CGImage) return nil;
    unsigned char px[4] = {0, 0, 0, 0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), img.CGImage);
    CGContextRelease(ctx);
    CGFloat r = px[0] / 255.0, g = px[1] / 255.0, b = px[2] / 255.0;
    UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:1];
    CGFloat h, sat, br, a;
    if ([c getHue:&h saturation:&sat brightness:&br alpha:&a]) {
        sat = MIN(1.0, sat * 1.35 + 0.08);
        br = MAX(0.55, MIN(0.95, br * 1.25));
        return [UIColor colorWithHue:h saturation:sat brightness:br alpha:1];
    }
    return c;
}

// 把页面的两团光斑换成封面色（有渐隐过渡）
+ (void)recolor:(UIView *)v with:(UIColor *)color {
    if (!v || !color) return;
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSInteger idx = 0;
    for (UIView *sub in v.subviews) {
        if (![sub isKindOfClass:ADGradientView.class]) continue;
        CAGradientLayer *l = [(ADGradientView *)sub grad];
        if (![l.type isEqualToString:kCAGradientLayerRadial]) continue;
        CGFloat strength = (idx == 0) ? 0.30 : 0.16;
        CGFloat rr = (idx == 0) ? r : MIN(1, b * 0.9 + 0.1);
        CGFloat gg = (idx == 0) ? g : MIN(1, r * 0.5 + 0.2);
        CGFloat bb = (idx == 0) ? b : MIN(1, g * 0.6 + 0.35);
        NSArray *to = @[(id)[UIColor colorWithRed:rr green:gg blue:bb alpha:strength].CGColor,
                        (id)[UIColor colorWithRed:rr green:gg blue:bb alpha:0].CGColor];
        CABasicAnimation *an = [CABasicAnimation animationWithKeyPath:@"colors"];
        an.fromValue = l.colors;
        an.toValue = to;
        an.duration = 0.8;
        an.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        l.colors = to;
        [l addAnimation:an forKey:@"recolor"];
        idx++;
    }
}

+ (void)float:(UIView *)v {
    if (!v) return;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.38;
    v.layer.shadowRadius = 22;
    v.layer.shadowOffset = CGSizeMake(0, 12);
}

+ (void)press:(UIView *)v {
    if (!v || [v viewWithTag:9831]) return;
    UIView *m = [UIView new];
    m.tag = 9831;
    m.hidden = YES;
    m.userInteractionEnabled = NO;
    [v addSubview:m];
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onPress:)];
    g.minimumPressDuration = 0;
    g.allowableMovement = 24;
    g.cancelsTouchesInView = NO;
    [v addGestureRecognizer:g];
}

+ (void)onPress:(UILongPressGestureRecognizer *)g {
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) {
        [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
            v.transform = CGAffineTransformMakeScale(0.962, 0.962);
        } completion:nil];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.58 initialSpringVelocity:0.7
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ v.transform = CGAffineTransformIdentity; } completion:nil];
    }
}

// 向下滚 → 悬浮导航略缩小变淡；向上滚/停下 → 恢复。给人“随手势呼吸”的感觉。
+ (void)followScroll:(UIScrollView *)sv lastY:(CGFloat *)lastY {
    if (!sv || !lastY) return;
    CGFloat y = sv.contentOffset.y;
    CGFloat dy = y - *lastY;
    *lastY = y;
    if (fabs(dy) < 3 || y < 20) return;
    ADNavDock *dock = [ADNavDock shared];
    if (!dock.dockVisible) return;
    BOOL down = dy > 0;
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.2
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        dock.transform = down ? CGAffineTransformConcat(CGAffineTransformMakeScale(0.94, 0.94), CGAffineTransformMakeTranslation(0, 8))
                              : CGAffineTransformIdentity;
        dock.alpha = down ? 0.78 : 1.0;
    } completion:nil];
}

// 播放中的封面轻轻呼吸（缩放 1.0 ↔ 1.018）+ 投影随之起伏；暂停时回正
+ (void)breathe:(UIView *)v on:(BOOL)on {
    if (!v) return;
    if (!on) {
        [v.layer removeAnimationForKey:@"breathe"];
        [v.layer removeAnimationForKey:@"breatheShadow"];
        return;
    }
    if ([v.layer animationForKey:@"breathe"]) return;
    CABasicAnimation *s = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    s.fromValue = @1.0; s.toValue = @1.018;
    s.duration = 3.2; s.autoreverses = YES; s.repeatCount = HUGE_VALF;
    s.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:s forKey:@"breathe"];
    CABasicAnimation *sh = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    sh.fromValue = @26; sh.toValue = @40;
    sh.duration = 3.2; sh.autoreverses = YES; sh.repeatCount = HUGE_VALF;
    sh.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:sh forKey:@"breatheShadow"];
}

+ (void)pulse:(UIView *)v {
    if (!v) return;
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    a.values = @[@1.0, @1.06, @0.99, @1.0];
    a.keyTimes = @[@0, @0.35, @0.7, @1];
    a.duration = 0.5;
    [v.layer addAnimation:a forKey:@"pulse"];
}

+ (void)rise:(UIView *)v delay:(NSTimeInterval)delay {
    if (!v) return;
    v.alpha = 0;
    v.transform = CGAffineTransformMakeTranslation(0, 16);
    [UIView animateWithDuration:0.5 delay:delay usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        v.alpha = 1;
        v.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
