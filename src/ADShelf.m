#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "ADInternal.h"

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
        [b setTitleColor:(on ? [ADUtil onBrand] : [UIColor colorWithWhite:1 alpha:0.75]) forState:UIControlStateNormal];
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
