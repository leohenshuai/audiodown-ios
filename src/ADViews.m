#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

// ───────────── 卡片：继续收听 ─────────────
@interface ADContinueCard : UIView
@property (nonatomic, strong) ADAlbum *album;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, copy) void (^onPlay)(void);
@property (nonatomic, copy) void (^onMore)(void);
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

- (void)tapPlay { if (self.onPlay) self.onPlay(); }
- (void)tapMore { if (self.onMore) self.onMore(); }
- (void)tapCard {
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
        self.album = a;
    }
    return self;
}
- (void)open {
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UINavigationController *nav = nil;
    UIViewController *vc = win.rootViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
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
    UIButton *_btn, *_back;
    UIView *_track, *_fill;
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
    self.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.96];
    self.layer.cornerRadius = 16;
    self.clipsToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(8, 8, 42, 42)];
    _cover.layer.cornerRadius = 8; _cover.clipsToBounds = YES;
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
    [self addSubview:_cover]; [self addSubview:_title]; [self addSubview:_sub];
    [self addSubview:_btn]; [self addSubview:_back]; [self addSubview:_track]; [self addSubview:_fill];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBar)]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerChanged" object:nil];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _cover.frame = CGRectMake(8, (h - 42) / 2, 42, 42);
    _btn.frame = CGRectMake(w - 46, (h - 36) / 2, 36, 36);
    _back.frame = CGRectMake(w - 82, (h - 36) / 2, 32, 36);
    _title.frame = CGRectMake(58, 10, w - 148, 18);
    _sub.frame = CGRectMake(58, 29, w - 148, 15);
    _track.frame = CGRectMake(0, h - 2, w, 2);
    _fill.frame = CGRectMake(0, h - 2, 0, 2);
}
- (void)refresh {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    self.hidden = (t == nil);
    if (!t) return;
    _title.text = t.title;
    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    _sub.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    [ADUtil cover:_cover url:p.album.cover];
    [_btn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    CGFloat full = self.bounds.size.width;
    _fill.frame = CGRectMake(0, self.bounds.size.height - 2, (dur > 0 && !isnan(dur)) ? full * cur / dur : 0, 2);
}
- (void)tapPlay { [ADPlayer.shared toggle]; [self refresh]; }
- (void)tapBack { [ADPlayer.shared seekBy:-15]; }
- (void)tapBar {
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────── 首页 ─────────────
@interface ADDiscoverController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@property (nonatomic, assign) BOOL needsSetup;
@property (nonatomic, strong) NSMutableArray<ADContinueCard *> *cards;
@end

@implementation ADDiscoverController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.035 blue:0.035 alpha:1];
    self.navigationController.navigationBar.hidden = YES;

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
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
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 64, self.view.bounds.size.width - 16, 58);
    if (!m.superview) [self.view addSubview:m];
    [self.view bringSubviewToFront:m];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.needsSetup) {
        self.needsSetup = NO;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[ADSettingsController new]];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
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
    logo.text = @"听见";
    [self.scroll addSubview:logo];
    UILabel *sub = [ADUtil label:nil size:16 color:[UIColor colorWithWhite:1 alpha:0.4]];
    sub.frame = CGRectMake(104, y + 18, 120, 20);
    sub.text = @"AudioDown";
    [self.scroll addSubview:sub];

    NSArray *icons = @[@"clock.arrow.circlepath", @"square.stack.fill"];
    NSArray *sels = @[@"openHistory", @"openDownloads"];
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(W - 16 - 44 - i * 56, y + 4, 44, 44);
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        b.layer.cornerRadius = 22;
        b.tintColor = (i == 1) ? [ADUtil brand] : UIColor.whiteColor;
        [b setImage:[UIImage systemImageNamed:icons[i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
        SEL sel = NSSelectorFromString(sels[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
    }
    y += 62;

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
            [hs addSubview:c];
            [self.cards addObject:c];
        }
        [self.scroll addSubview:hs];
        y += cardH + 22;
    }

    // 推荐内容面板
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0)];
    panel.backgroundColor = [UIColor colorWithRed:0.106 green:0.106 blue:0.118 alpha:1];
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

    ADMiniBar *m = [ADMiniBar shared];
    CGFloat bottom = self.view.safeAreaInsets.bottom + 6;
    m.frame = CGRectMake(8, self.view.bounds.size.height - bottom - 58, W - 16, 58);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}

- (void)openHistory {
    [self.navigationController pushViewController:[ADHistoryController new] animated:YES];
}

- (void)openDownloads {
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

- (void)moreCard:(ADAlbum *)a {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:a.title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从头播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADApi shared] tracksOf:a.albumId page:1 done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
            if (list.count) [ADPlayer.shared playAlbum:a tracks:list at:0];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[[ADStore shared] isFavorite:a.albumId] ? @"取消收藏" : @"加入书架" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADStore shared] toggleFavorite:a];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
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
@end

@implementation ADSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.035 blue:0.035 alpha:1];
    self.navigationController.navigationBar.hidden = YES;
    self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    self.bar.placeholder = @"书名 / 作者 / 主播";
    self.bar.searchBarStyle = UISearchBarStyleMinimal;
    self.bar.delegate = self;
    self.bar.tintColor = [ADUtil brand];
    [self.view addSubview:self.bar];
    [self layoutChrome];
    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(w, w + 40);
    lo.minimumInteritemSpacing = 12;
    lo.minimumLineSpacing = 16;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 108, self.view.bounds.size.width, self.view.bounds.size.height - 108) collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(8, 16, 120, 16);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"c"];
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
    self.seg.frame = CGRectMake(16, 0, 150, 32);
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
}

- (void)switchMode {
    self.localMode = (self.seg.selectedSegmentIndex == 1);
    [self layoutChrome];
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
    if (!self.localMode) return;
    [self.cv reloadData];
    self.hint.text = [self visible].count ? @"" : (t.length ? @"本机没有匹配的内容" : @"本机还没有内容，先在专辑页「缓存到本机」或收藏");
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
    NSArray *map = @[@[], @[@"小说", @"传", @"故事", @"全集", @"演义", @"仙", @"医", @"明星", @"帝", @"都市", @"剑", @"记"],
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
    self.catIndex = b.tag - 100;
    [self paintChips];
    [self.cv reloadData];
    if (self.catIndex != 0 && self.list.count && [self visible].count < 6 && self.more) {
        self.autoPages = 0;
        [self loadPage];
    }
}

- (BOOL)catMatch:(ADAlbum *)a {
    if (self.catIndex == 0) return YES;
    NSArray *words = [self catWords:self.catIndex];
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", a.title ?: @"", a.anchor ?: @"", a.author ?: @"", a.intro ?: @""];
    for (NSString *w in words) if ([hay rangeOfString:w].location != NSNotFound) return YES;
    return NO;
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
    for (ADAlbum *a in self.list) if ([self catMatch:a]) [arr addObject:a];
    return arr;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.navigationController.navigationBar.hidden = YES; [self layoutChrome]; }
- (void)layoutChrome {
    CGFloat top = MAX(self.view.safeAreaInsets.top, 47);
    self.bar.frame = CGRectMake(0, top - 6, self.view.bounds.size.width, 52);
    self.seg.frame = CGRectMake(16, top + 46, 150, 32);
    self.cats.frame = CGRectMake(0, top + 82, self.view.bounds.size.width, 40);
    self.cats.hidden = self.localMode;
    CGFloat gridTop = self.localMode ? top + 82 : top + 122;
    self.cv.frame = CGRectMake(0, gridTop, self.view.bounds.size.width, self.view.bounds.size.height - gridTop);
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2, self.view.bounds.size.width - 60, 40);
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 64, self.view.bounds.size.width - 16, 58);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)b {
    [b resignFirstResponder];
    if (self.localMode) { [self.cv reloadData]; return; }
    NSString *q = [b.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!q.length) return;
    self.keyword = q; self.page = 1; self.more = YES; self.autoPages = 0;
    self.list = [NSMutableArray array];
    if (self.catIndex != 0) { self.catIndex = 0; [self paintChips]; }
    [self.list removeAllObjects]; [self.cv reloadData];
    self.hint.text = @"搜索中…";
    [self loadPage];
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
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return [self visible].count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    ADAlbum *a = [self visible][ip.item];
    CGFloat w = cell.contentView.bounds.size.width;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, w)];
    iv.layer.cornerRadius = 12; iv.clipsToBounds = YES;
    [ADUtil cover:iv url:a.cover];
    UILabel *t = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.85]];
    t.frame = CGRectMake(0, w + 6, w, 32);
    t.numberOfLines = 2;
    t.text = a.title;
    [cell.contentView addSubview:iv]; [cell.contentView addSubview:t];
    if ([[ADStore shared] isAlbumDone:a.albumId]) {
        UILabel *badge = [ADUtil label:nil size:10 color:UIColor.whiteColor];
        badge.text = @"已听完";
        badge.textAlignment = NSTextAlignmentCenter;
        badge.backgroundColor = [ADUtil brand];
        badge.layer.cornerRadius = 9;
        badge.clipsToBounds = YES;
        badge.frame = CGRectMake(w - 52, 6, 46, 18);
        [cell.contentView addSubview:badge];
    }
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = [self visible][ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end

// ───────────── 书架 ─────────────
@interface ADShelfController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UILabel *hint;
@end

@implementation ADShelfController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.035 blue:0.035 alpha:1];
    self.navigationController.navigationBar.hidden = YES;
    UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:34 color:UIColor.whiteColor];
    t.frame = CGRectMake(16, MAX(self.view.safeAreaInsets.top, 47), 200, 40);
    t.text = @"书架";
    t.tag = 99;
    [self.view addSubview:t];
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.frame = CGRectMake(self.view.bounds.size.width - 60, MAX(self.view.safeAreaInsets.top, 47) + 4, 44, 44);
    gear.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    gear.layer.cornerRadius = 22;
    gear.tintColor = UIColor.whiteColor;
    [gear setImage:[UIImage systemImageNamed:@"gearshape" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [gear addTarget:self action:@selector(goSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:gear];

    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(w, w + 40);
    lo.minimumInteritemSpacing = 12; lo.minimumLineSpacing = 16;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 108, self.view.bounds.size.width, self.view.bounds.size.height - 108) collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(8, 16, 120, 16);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"c"];
    self.cv.refreshControl = [[UIRefreshControl alloc] init];
    self.cv.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.cv.refreshControl addTarget:self action:@selector(refreshSearch) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.cv];
    self.hint = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.text = @"还没有收藏和收听记录\n在专辑页点右上角收藏";
    [self.view addSubview:self.hint];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = YES;
    NSMutableArray *arr = [NSMutableArray array];
    for (ADAlbum *a in [ADStore shared].favorites) [arr addObject:a];
    for (ADAlbum *a in [ADStore shared].history) {
        BOOL dup = NO;
        for (ADAlbum *b in arr) if ([b.albumId isEqualToString:a.albumId]) { dup = YES; break; }
        if (!dup) [arr addObject:a];
    }
    self.items = arr;
    self.hint.hidden = arr.count > 0;
    [self.cv reloadData];
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.cv.frame = CGRectMake(0, 108, self.view.bounds.size.width, self.view.bounds.size.height - 108);
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 40, self.view.bounds.size.width - 60, 60);
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 64, self.view.bounds.size.width - 16, 58);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    CGFloat top = MAX(self.view.safeAreaInsets.top, 47);
    UILabel *t = [self.view viewWithTag:99];
    t.frame = CGRectMake(16, top, 200, 40);
    UIButton *g = nil;
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:UIButton.class]) g = (UIButton *)v;
    g.frame = CGRectMake(self.view.bounds.size.width - 60, top + 4, 44, 44);
    self.cv.frame = CGRectMake(0, top + 52, self.view.bounds.size.width, self.view.bounds.size.height - top - 52);
}

- (void)pullRefresh {
    [self.cv.refreshControl endRefreshing];
    [self viewWillAppear:NO];
}

- (void)goSettings {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[ADSettingsController new]];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    ADAlbum *a = self.items[ip.item];
    CGFloat w = cell.contentView.bounds.size.width;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, w)];
    iv.layer.cornerRadius = 12; iv.clipsToBounds = YES;
    [ADUtil cover:iv url:a.cover];
    UILabel *t = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.85]];
    t.frame = CGRectMake(0, w + 6, w, 32);
    t.numberOfLines = 2;
    t.text = a.title;
    [cell.contentView addSubview:iv]; [cell.contentView addSubview:t];
    if ([[ADStore shared] isAlbumDone:a.albumId]) {
        UILabel *badge = [ADUtil label:nil size:10 color:UIColor.whiteColor];
        badge.text = @"已听完";
        badge.textAlignment = NSTextAlignmentCenter;
        badge.backgroundColor = [ADUtil brand];
        badge.layer.cornerRadius = 9;
        badge.clipsToBounds = YES;
        badge.frame = CGRectMake(w - 52, 6, 46, 18);
        [cell.contentView addSubview:badge];
    }
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.items[ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
