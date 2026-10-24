#import "AD.h"
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

// ───────────── 专辑卡片 ─────────────
@protocol ADAlbumTap <NSObject>
- (void)openAlbum:(ADAlbum *)a;
@end

@interface ADAlbumCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title, *sub;
- (void)fill:(ADAlbum *)a;
@end

@implementation ADAlbumCell
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        CGFloat w = f.size.width;
        _cover = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, w)];
        _cover.layer.cornerRadius = 10;
        _cover.clipsToBounds = YES;
        _title = [ADUtil label:@"PingFangSC-Medium" size:13 color:UIColor.whiteColor];
        _title.frame = CGRectMake(0, w + 6, w, 18);
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        _sub = [ADUtil label:nil size:11 color:[ADUtil dim]];
        _sub.frame = CGRectMake(0, w + 24, w, 15);
        [self.contentView addSubview:_cover];
        [self.contentView addSubview:_title];
        [self.contentView addSubview:_sub];
    }
    return self;
}
- (void)fill:(ADAlbum *)a {
    [ADUtil cover:_cover url:a.cover];
    _title.text = a.title;
    _sub.text = a.anchor.length ? a.anchor : (a.trackCount ? [NSString stringWithFormat:@"%ld 集", (long)a.trackCount] : @"");
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
    UIButton *_btn;
    UIProgressView *_bar;
}
+ (instancetype)shared {
    static ADMiniBar *m; static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [[ADMiniBar alloc] initWithFrame:CGRectMake(0, 0, 320, 62)];
        [m build];
    });
    return m;
}
- (void)build {
    self.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.98];
    self.layer.cornerRadius = 14;
    self.clipsToBounds = YES;
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(8, 8, 46, 46)];
    _cover.layer.cornerRadius = 8; _cover.clipsToBounds = YES;
    _title = [ADUtil label:@"PingFangSC-Semibold" size:13 color:UIColor.whiteColor];
    _sub = [ADUtil label:nil size:11 color:[ADUtil dim]];
    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn.tintColor = UIColor.whiteColor;
    [_btn addTarget:self action:@selector(tapPlay) forControlEvents:UIControlEventTouchUpInside];
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _bar.progressTintColor = [ADUtil brand];
    _bar.trackTintColor = [UIColor colorWithWhite:1 alpha:0.12];
    [self addSubview:_cover]; [self addSubview:_title]; [self addSubview:_sub]; [self addSubview:_btn]; [self addSubview:_bar];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBar)]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADPlayerChanged" object:nil];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _cover.frame = CGRectMake(8, (h - 46) / 2, 46, 46);
    _btn.frame = CGRectMake(w - 50, (h - 40) / 2, 40, 40);
    _title.frame = CGRectMake(62, 10, w - 120, 19);
    _sub.frame = CGRectMake(62, 30, w - 120, 15);
    _bar.frame = CGRectMake(0, h - 2, w, 2);
}
- (void)refresh {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    self.hidden = (t == nil);
    if (!t) return;
    _title.text = t.title;
    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    _sub.text = [NSString stringWithFormat:@"%@ · %@/%@", p.album.title ?: @"", [ADUtil time:cur], (dur > 0 && !isnan(dur)) ? [ADUtil time:dur] : @"--:--"];
    [ADUtil cover:_cover url:p.album.cover];
    [_btn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal];
    if (dur > 0 && !isnan(dur)) _bar.progress = cur / dur;
}
- (void)tapPlay { [ADPlayer.shared toggle]; [self refresh]; }
- (void)tapBar {
    UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────── 首页（发现） ─────────────
@interface ADDiscoverController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@end

@implementation ADDiscoverController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.title = @"发现";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.alwaysBounceVertical = YES;
    self.refresh = [UIRefreshControl new];
    [self.refresh addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10, *)) self.scroll.refreshControl = self.refresh;
    [self.view addSubview:self.scroll];

    self.hint = [ADUtil label:nil size:14 color:[ADUtil dim]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.text = @"";
    self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spin.color = UIColor.whiteColor;
    [self.view addSubview:self.hint];
    [self.view addSubview:self.spin];
    [self load];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.scroll.frame = self.view.bounds;
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 40, self.view.bounds.size.width - 60, 40);
    self.spin.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2 - 70);
    [self layoutSections];
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - 62 - 8 - self.view.safeAreaInsets.bottom, self.view.bounds.size.width - 16, 62);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}

- (void)load {
    if (!self.sections.count) [self.spin startAnimating];
    __weak typeof(self) w = self;
    [[ADApi shared] discover:^(NSArray<NSDictionary *> *sections, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        [self.spin stopAnimating];
        [self.refresh endRefreshing];
        if (err) { self.hint.text = err; return; }
        self.hint.text = sections.count ? @"" : @"没有内容";
        self.sections = sections;
        [self buildSections];
        [self layoutSections];
    }];
}

- (void)buildSections {
    for (UIView *v in self.scroll.subviews) [v removeFromSuperview];
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 8;
    for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++) {
        NSDictionary *sec = self.sections[i];
        NSArray *items = sec[@"items"];
        if (![items isKindOfClass:NSArray.class] || !items.count) continue;
        UILabel *title = [ADUtil label:@"PingFangSC-Semibold" size:17 color:UIColor.whiteColor];
        title.frame = CGRectMake(16, y, w - 100, 22);
        title.text = sec[@"title"] ?: @"推荐";
        [self.scroll addSubview:title];
        y += 30;

        CGFloat cw = floor((w - 16 * 2 - 12 * 2) / 2.6);
        UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
        lo.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        lo.itemSize = CGSizeMake(cw, cw + 40);
        lo.minimumLineSpacing = 12;
        lo.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
        UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, y, w, cw + 40) collectionViewLayout:lo];
        cv.backgroundColor = UIColor.clearColor;
        cv.showsHorizontalScrollIndicator = NO;
        cv.tag = 1000 + i;
        cv.dataSource = self;
        cv.delegate = self;
        [cv registerClass:ADAlbumCell.class forCellWithReuseIdentifier:@"a"];
        [self.scroll addSubview:cv];
        y += cw + 40 + 14;
    }
    self.scroll.contentSize = CGSizeMake(w, y + 120);
}

- (void)layoutSections { /* 尺寸变化时重建 */ 
    static CGFloat lastW = 0;
    if (fabs(lastW - self.view.bounds.size.width) > 1 && self.sections.count) {
        lastW = self.view.bounds.size.width;
        [self buildSections];
    }
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    NSArray *items = self.sections[cv.tag - 1000][@"items"];
    return items.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"a" forIndexPath:ip];
    NSArray *items = self.sections[cv.tag - 1000][@"items"];
    [c fill:[ADAlbum fromJSON:items[ip.item]]];
    return c;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSArray *items = self.sections[cv.tag - 1000][@"items"];
    ADAlbum *a = [ADAlbum fromJSON:items[ip.item]];
    if (!a) return;
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = a;
    [self.navigationController pushViewController:vc animated:YES];
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
@end

@implementation ADSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.title = @"搜索";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;

    self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    self.bar.placeholder = @"书名 / 作者 / 主播";
    self.bar.searchBarStyle = UISearchBarStyleMinimal;
    self.bar.delegate = self;
    self.bar.tintColor = [ADUtil brand];
    [self.view addSubview:self.bar];

    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(w, w + 40);
    lo.minimumInteritemSpacing = 12;
    lo.minimumLineSpacing = 16;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 52, self.view.bounds.size.width, self.view.bounds.size.height - 52) collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(8, 16, 100, 16);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:ADAlbumCell.class forCellWithReuseIdentifier:@"a"];
    [self.view addSubview:self.cv];

    self.hint = [ADUtil label:nil size:14 color:[ADUtil dim]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hint];
    self.list = [NSMutableArray array];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2, self.view.bounds.size.width - 60, 40);
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - 62 - 8 - self.view.safeAreaInsets.bottom, self.view.bounds.size.width - 16, 62);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)b {
    [b resignFirstResponder];
    NSString *q = [b.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!q.length) return;
    self.keyword = q;
    self.page = 1;
    self.more = YES;
    [self.list removeAllObjects];
    [self.cv reloadData];
    self.hint.text = @"搜索中…";
    [self loadPage];
}

- (void)loadPage {
    if (self.loading || !self.more) return;
    self.loading = YES;
    __weak typeof(self) w = self;
    [[ADApi shared] search:self.keyword page:self.page done:^(NSArray<ADAlbum *> *list, BOOL more, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.loading = NO;
        if (err) { self.hint.text = err; return; }
        self.more = list.count > 0;
        [self.list addObjectsFromArray:list];
        self.page += 1;
        self.hint.text = self.list.count ? @"" : @"没有找到";
        [self.cv reloadData];
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)s {
    if (s.contentOffset.y + s.bounds.size.height > s.contentSize.height - 300) [self loadPage];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.list.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"a" forIndexPath:ip];
    [c fill:self.list[ip.item]];
    return c;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.list[ip.item];
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
    self.view.backgroundColor = [ADUtil bg];
    self.title = @"书架";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(goSettings)];

    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(w, w + 40);
    lo.minimumInteritemSpacing = 12; lo.minimumLineSpacing = 16;
    lo.headerReferenceSize = CGSizeMake(self.view.bounds.size.width, 44);
    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(0, 16, 100, 16);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:ADAlbumCell.class forCellWithReuseIdentifier:@"a"];
    [self.cv registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"h"];
    [self.view addSubview:self.cv];

    self.hint = [ADUtil label:nil size:14 color:[ADUtil dim]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.text = @"还没有收藏和收听记录\n在专辑页点右上角收藏";
    [self.view addSubview:self.hint];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray *arr = [NSMutableArray array];
    [arr addObjectsFromArray:[ADStore shared].history];
    for (ADAlbum *a in [ADStore shared].favorites) {
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
    self.cv.frame = self.view.bounds;
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 60, self.view.bounds.size.width - 60, 60);
    ADMiniBar *m = [ADMiniBar shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - 62 - 8 - self.view.safeAreaInsets.bottom, self.view.bounds.size.width - 16, 62);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}
- (void)goSettings {
    [self.navigationController pushViewController:[ADSettingsController new] animated:YES];
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"a" forIndexPath:ip];
    [c fill:self.items[ip.item]];
    return c;
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip {
    UICollectionReusableView *h = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"h" forIndexPath:ip];
    [h.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    UILabel *l = [ADUtil label:@"PingFangSC-Semibold" size:15 color:[ADUtil dim]];
    l.frame = CGRectMake(0, 18, 200, 20);
    l.text = @"继续收听";
    [h addSubview:l];
    return h;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.items[ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
