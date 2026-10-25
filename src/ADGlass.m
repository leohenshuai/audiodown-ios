#import "AD.h"

// iOS 26 风格的近似实现：深色渐变背景 + 超薄材质模糊 + 高光描边 + 柔和投影
@implementation ADGlass

+ (void)applyTo:(UIView *)v radius:(CGFloat)r {
    [self applyTo:v radius:r tint:0.05];
}

+ (void)applyTo:(UIView *)v radius:(CGFloat)r tint:(CGFloat)alpha {
    if (!v) return;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.cornerRadius = r;
    v.layer.borderWidth = 0.6;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    v.clipsToBounds = NO;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.32;
    v.layer.shadowRadius = 18;
    v.layer.shadowOffset = CGSizeMake(0, 9);

    UIView *old = [v viewWithTag:9911];
    [old removeFromSuperview];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.tag = 9911;
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.layer.cornerRadius = r;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    blur.userInteractionEnabled = NO;
    if (alpha > 0) {
        UIView *tint = [[UIView alloc] initWithFrame:blur.bounds];
        tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tint.backgroundColor = [UIColor colorWithWhite:1 alpha:alpha];
        [blur.contentView addSubview:tint];
    }
    [v insertSubview:blur atIndex:0];

    UIView *hi = [[UIView alloc] initWithFrame:CGRectMake(0, 0, v.bounds.size.width, 1)];
    hi.tag = 9912;
    hi.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hi.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    hi.userInteractionEnabled = NO;
    [v addSubview:hi];
}

+ (void)setRadius:(CGFloat)r on:(UIView *)v {
    if (!v) return;
    v.layer.cornerRadius = r;
    UIView *blur = [v viewWithTag:9911];
    blur.layer.cornerRadius = r;
}

+ (void)glassButton:(UIButton *)b {
    if (!b) return;
    [self applyTo:b radius:b.bounds.size.height / 2.0 tint:0.07];
    b.layer.shadowOpacity = 0.18;
    b.layer.shadowRadius = 10;
    b.layer.shadowOffset = CGSizeMake(0, 4);
}

// 卡片按下去轻微回弹
+ (void)press:(UIView *)v {
    if (!v || [v viewWithTag:9913]) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
    g.minimumPressDuration = 0;
    g.cancelsTouchesInView = NO;
    g.allowableMovement = 22;
    [v addGestureRecognizer:g];
    UILabel *m = [UILabel new];
    m.tag = 9913;
    m.hidden = YES;
    [v addSubview:m];
}

+ (void)handlePress:(UILongPressGestureRecognizer *)g {
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) {
        [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            v.transform = CGAffineTransformMakeScale(0.965, 0.965);
        } completion:nil];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.6 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            v.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

// 深色渐变底 + 左上角一圈很淡的暖光
+ (void)background:(UIView *)v {
    if (!v) return;
    v.backgroundColor = [UIColor colorWithRed:0.035 green:0.032 blue:0.04 alpha:1];
    if ([v viewWithTag:9920]) return;
    UIView *mark = [[UIView alloc] initWithFrame:CGRectZero];
    mark.tag = 9920;
    mark.hidden = YES;
    [v addSubview:mark];

    CAGradientLayer *base = [CAGradientLayer layer];
    base.frame = v.bounds;
    base.colors = @[(id)[UIColor colorWithRed:0.075 green:0.068 blue:0.085 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.022 green:0.021 blue:0.028 alpha:1].CGColor];
    base.startPoint = CGPointMake(0.1, 0);
    base.endPoint = CGPointMake(0.9, 1);
    base.name = @"adbg.base";
    [v.layer insertSublayer:base atIndex:0];

    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.frame = CGRectMake(-v.bounds.size.width * 0.3, -v.bounds.size.height * 0.15,
                            v.bounds.size.width * 1.2, v.bounds.size.height * 0.7);
    glow.type = kCAGradientLayerRadial;
    glow.colors = @[(id)[UIColor colorWithRed:1.0 green:0.45 blue:0.22 alpha:0.16].CGColor,
                    (id)[UIColor colorWithRed:1.0 green:0.45 blue:0.22 alpha:0.0].CGColor];
    glow.startPoint = CGPointMake(0.5, 0.5);
    glow.endPoint = CGPointMake(1, 1);
    glow.name = @"adbg.glow";
    [v.layer insertSublayer:glow above:base];
}

@end
