#import "AD.h"

@interface ADSheetView : UIView
@property (nonatomic, copy) void (^onChoose)(NSInteger index);
@property (nonatomic, strong) UIView *box;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray *options;
@property (nonatomic, assign) NSInteger destructiveIndex;
@end

static ADSheetView *gSheet;

@implementation ADSheetView

- (instancetype)initWithFrame:(CGRect)f title:(NSString *)title options:(NSArray *)opts destructive:(NSInteger)di {
    if ((self = [super initWithFrame:f])) {
        _title = title; _options = opts; _destructiveIndex = di;
        self.backgroundColor = UIColor.clearColor;

        _dim = [[UIView alloc] initWithFrame:f];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _dim.alpha = 0;
        [self addSubview:_dim];

        UIButton *bg = [UIButton buttonWithType:UIButtonTypeCustom];
        bg.frame = f;
        [bg addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:bg];

        CGFloat W = f.size.width;
        CGFloat rowH = 52, th = title.length ? 38 : 6;
        CGFloat height = th + opts.count * rowH + 8 + 54 + 10;
        CGFloat y0 = f.size.height - height;   // 可见位置，靠 transform 动画滑入
        _box = [[UIView alloc] initWithFrame:CGRectMake(8, y0, W - 16, height)];
        [self addSubview:_box];

        UIView *list = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W - 16, th + opts.count * rowH)];
        [ADGlass applyTo:list radius:22 tint:0.03];
        list.clipsToBounds = YES;
        [_box addSubview:list];

        if (title.length) {
            UILabel *t = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.5]];
            t.text = title;
            t.textAlignment = NSTextAlignmentCenter;
            t.frame = CGRectMake(0, 8, W - 16, 26);
            [list addSubview:t];
        }
        for (NSInteger i = 0; i < (NSInteger)opts.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(0, th + i * rowH, W - 16, rowH);
            b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
            [b setTitle:opts[i] forState:UIControlStateNormal];
            [b setTitleColor:(i == di ? [UIColor systemRedColor] : UIColor.whiteColor) forState:UIControlStateNormal];
            b.tag = i;
            [b addTarget:self action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];
            [list addSubview:b];
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(16, th + i * rowH, W - 48, 0.5)];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
            [list addSubview:line];
        }

        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.frame = CGRectMake(0, CGRectGetMaxY(list.frame) + 8, W - 16, 54);
        [ADGlass applyTo:cancel radius:20 tint:0.03];
        cancel.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [cancel setTitle:@"取消" forState:UIControlStateNormal];
        [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [cancel addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [_box addSubview:cancel];
    }
    return self;
}

- (void)present {
    self.box.transform = CGAffineTransformMakeTranslation(0, self.box.bounds.size.height + 40);
    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.dim.alpha = 1;
        self.box.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tapRow:(UIButton *)b {
    NSInteger i = b.tag;
    [ADHaptic select];
    void (^cb)(NSInteger) = self.onChoose;
    [self close];
    if (cb) cb(i);
}

- (void)close {
    [UIView animateWithDuration:0.22 animations:^{
        self.dim.alpha = 0;
        self.box.transform = CGAffineTransformMakeTranslation(0, self.box.bounds.size.height + 40);
    } completion:^(BOOL ok) {
        [self removeFromSuperview];
        gSheet = nil;
    }];
}
@end

@implementation ADOptionSheet

+ (void)showIn:(UIViewController *)vc
         title:(NSString *)title
       options:(NSArray<NSString *> *)options
   destructive:(NSInteger)destructiveIndex
        choose:(void (^)(NSInteger index))choose {
    [gSheet removeFromSuperview];
    UIWindow *win = vc.view.window ?: UIApplication.sharedApplication.keyWindow;
    ADSheetView *s = [[ADSheetView alloc] initWithFrame:win.bounds title:title options:options destructive:destructiveIndex];
    s.onChoose = choose;
    [win addSubview:s];
    gSheet = s;
    [s present];
}

@end
