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
    _pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    _pill.layer.cornerRadius = 21;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.userInteractionEnabled = NO;
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

- (CGFloat)topY { return self.frame.origin.y; }

- (void)movePill:(BOOL)animated {
    CGFloat seg = self.bounds.size.width / 3.0;
    CGRect r = CGRectMake(seg * self.selectedIndex + (seg - 62) / 2, 9, 62, 44);
    if (animated) {
        [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ _pill.frame = r; } completion:nil];
    } else {
        _pill.frame = r;
    }
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

+ (void)corner:(CGFloat)r on:(UIView *)v {
    if (!v) return;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.cornerRadius = r;
    UIView *blur = [v viewWithTag:kBlurTag];
    blur.layer.cornerRadius = r;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
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
