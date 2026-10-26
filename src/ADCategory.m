#import "AD.h"

// 分类页:服务端没有“按分类取专辑”的接口(categories/{id}/albums 等都是 404,discover 忽略 categoryId),
// 所以每个分类用 2~3 个代表关键词并行搜索,合并去重后按关键词轮流穿插展示,触底再翻页。

@interface ADCatCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title, *sub;
@end
@implementation ADCatCell
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _cover = [UIImageView new];
        _cover.layer.cornerRadius = 12; _cover.clipsToBounds = YES;
        _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        [self.contentView addSubview:_cover];
        _title = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.9]];
        _title.numberOfLines = 2;
        [self.contentView addSubview:_title];
        _sub = [ADUtil label:nil size:11 color:[UIColor colorWithWhite:1 alpha:0.45]];
        [self.contentView addSubview:_sub];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _cover.frame = CGRectMake(0, 0, w, w);
    CGSize ts = [_title sizeThatFits:CGSizeMake(w, 40)];
    _title.frame = CGRectMake(0, w + 6, w, MIN(ts.height, 36));
    _sub.frame = CGRectMake(0, CGRectGetMaxY(_title.frame) + 2, w, 14);
}
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:0.18 animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.95, 0.95) : CGAffineTransformIdentity; }];
}
@end

@interface ADCategoryController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIButton *back;
@property (nonatomic, strong) UILabel *head, *sub, *hint;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@property (nonatomic, strong) NSMutableArray<ADAlbum *> *list;
@property (nonatomic, strong) NSMutableSet<NSString *> *seen;
@property (nonatomic, assign) NSInteger page, pending;
@property (nonatomic, assign) BOOL loading, more;
@end

@implementation ADCategoryController

+ (NSDictionary *)table {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 标题: @[图标, 色值, 关键词...]
        t = @{
            @"有声书":   @[@"book.fill", @0xF28C38, @"小说", @"有声书", @"长篇"],
            @"有声图书": @[@"books.vertical.fill", @0xE0A13A, @"名著", @"文学", @"经典"],
            @"儿童":     @[@"teddybear.fill", @0xFFB547, @"儿童", @"童话", @"儿歌"],
            @"相声评书": @[@"mic.fill", @0xE2574C, @"相声", @"评书", @"郭德纲"],
            @"音乐":     @[@"music.note", @0x5AA9E6, @"轻音乐", @"钢琴", @"歌曲"],
            @"历史":     @[@"building.columns.fill", @0xB08954, @"历史", @"三国", @"通史"],
            @"娱乐":     @[@"sparkles", @0xE36BAE, @"娱乐", @"脱口秀", @"综艺"],
            @"外语":     @[@"globe", @0x4FB6A8, @"英语", @"日语", @"口语"],
            @"个人成长": @[@"leaf.fill", @0x7CC16B, @"成长", @"心理", @"自律"],
            @"商业财经": @[@"chart.line.uptrend.xyaxis", @0x3E9BD6, @"财经", @"商业", @"投资"],
            @"广播剧":   @[@"theatermasks.fill", @0x9B7BE0, @"广播剧", @"多人有声剧"],
            @"人文国学": @[@"scroll.fill", @0xC59A5B, @"国学", @"论语", @"诗词"],
            @"热点":     @[@"flame.fill", @0xF0603A, @"热点", @"新闻", @"头条"],
            @"生活":     @[@"cup.and.saucer.fill", @0xD9A066, @"生活", @"美食", @"旅行"],
            @"新红色频道": @[@"star.fill", @0xD9443A, @"红色", @"党史", @"革命"],
            @"悬疑":     @[@"eye.fill", @0x6C7BD9, @"悬疑", @"推理", @"盗墓"],
            @"健康":     @[@"heart.fill", @0xE05A6E, @"健康", @"养生", @"中医"],
            @"汽车":     @[@"car.fill", @0x7A8C9E, @"汽车", @"驾驶", @"车"],
        };
    });
    return t;
}
+ (NSArray<NSString *> *)keywordsFor:(NSString *)title {
    NSArray *row = [self table][title];
    if (row.count > 2) return [row subarrayWithRange:NSMakeRange(2, row.count - 2)];
    return title.length ? @[title] : @[];
}
+ (NSString *)iconFor:(NSString *)title { return [self table][title][0] ?: @"square.grid.2x2.fill"; }
+ (UIColor *)colorFor:(NSString *)title {
    NSNumber *n = [self table][title][1];
    NSUInteger v = n ? n.unsignedIntegerValue : 0x8E8E93;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    if (!self.keywords.count) self.keywords = [ADCategoryController keywordsFor:self.catTitle];
    self.list = [NSMutableArray array];
    self.seen = [NSMutableSet set];
    self.page = 0; self.more = YES;
    for (ADAlbum *a in self.seed) {
        if (!a.albumId.length || [self.seen containsObject:a.albumId]) continue;
        [self.seen addObject:a.albumId]; [self.list addObject:a];
    }

    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.minimumInteritemSpacing = 12; fl.minimumLineSpacing = 18;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:fl];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self; self.cv.delegate = self;
    self.cv.contentInset = UIEdgeInsetsMake(6, 16, 120, 16);
    [self.cv registerClass:ADCatCell.class forCellWithReuseIdentifier:@"c"];
    [self.view addSubview:self.cv];

    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    [self.back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.back];

    self.head = [ADUtil label:@"PingFangSC-Semibold" size:30 color:UIColor.whiteColor];
    self.head.text = self.catTitle;
    [self.view addSubview:self.head];
    self.sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.sub.text = self.seed.count
        ? [NSString stringWithFormat:@"精选 %lu 部 · 往下滑按热搜词继续加载", (unsigned long)self.seed.count]
        : [NSString stringWithFormat:@"按「%@」整理", [self.keywords componentsJoinedByString:@"」「"]];
    [self.view addSubview:self.sub];

    self.hint = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.45]];
    self.hint.textAlignment = NSTextAlignmentCenter; self.hint.numberOfLines = 0;
    [self.view addSubview:self.hint];
    self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spin.color = UIColor.whiteColor;
    [self.view addSubview:self.spin];
    if (self.list.count) [self.cv reloadData];
    else [self loadMore];
}

- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.navigationController.viewControllers.count > 1; }
- (void)goBack { [ADHaptic tap]; [self.navigationController popViewControllerAnimated:YES]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = MAX(self.view.safeAreaInsets.top, 47);
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    self.head.frame = CGRectMake(72, top + 6, W - 88, 38);
    self.sub.frame = CGRectMake(20, top + 54, W - 40, 18);
    self.cv.frame = CGRectMake(0, top + 78, W, H - top - 78);
    self.hint.frame = CGRectMake(30, H / 2 - 30, W - 60, 60);
    self.spin.center = CGPointMake(W / 2, H / 2 - 60);
}

// 每页:所有关键词并行各搜一页,全部回来后按关键词轮流穿插加入
- (void)loadMore {
    if (self.loading || !self.more || !self.keywords.count) return;
    self.loading = YES;
    if (!self.list.count) { [self.spin startAnimating]; self.hint.text = @""; }
    NSInteger pg = self.page + 1;
    NSInteger n = self.keywords.count;
    NSMutableArray *bucket = [NSMutableArray array];
    for (NSInteger i = 0; i < n; i++) [bucket addObject:[NSNull null]];
    __block NSInteger left = n, anyMore = 0;
    __block NSString *lastErr = nil;
    __weak typeof(self) w = self;
    for (NSInteger i = 0; i < n; i++) {
        __block BOOL got = NO;
        [[ADApi shared] search:self.keywords[i] page:pg done:^(NSArray<ADAlbum *> *list, BOOL more, BOOL cached, NSString *err) {
            // cachedGET 可能先回缓存再回网络:只要第一次有数据的结果
            if (got) return;
            if (cached && !list.count) return;
            got = YES;
            bucket[i] = list ?: @[];
            if (more) anyMore = 1;
            if (err) lastErr = err;
            if (--left == 0) [w merge:bucket page:pg more:anyMore err:lastErr];
        }];
    }
}

- (void)merge:(NSArray *)bucket page:(NSInteger)pg more:(BOOL)more err:(NSString *)err {
    self.loading = NO;
    [self.spin stopAnimating];
    self.page = pg;
    self.more = more && pg < 20;
    NSInteger before = self.list.count;
    NSUInteger maxLen = 0;
    for (id b in bucket) if ([b isKindOfClass:NSArray.class]) maxLen = MAX(maxLen, [b count]);
    for (NSUInteger k = 0; k < maxLen; k++) {
        for (id b in bucket) {
            if (![b isKindOfClass:NSArray.class] || k >= [b count]) continue;
            ADAlbum *a = b[k];
            if (!a.albumId.length || [self.seen containsObject:a.albumId]) continue;
            [self.seen addObject:a.albumId];
            [self.list addObject:a];
        }
    }
    NSInteger added = self.list.count - before;
    if (added > 0) {
        NSMutableArray *ips = [NSMutableArray array];
        for (NSInteger i = before; i < (NSInteger)self.list.count; i++) [ips addObject:[NSIndexPath indexPathForItem:i inSection:0]];
        if (before == 0) [self.cv reloadData];
        else [self.cv insertItemsAtIndexPaths:ips];
    } else if (self.more && self.list.count < 12) {
        // 整页都重复就再翻一页
        dispatch_async(dispatch_get_main_queue(), ^{ [self loadMore]; });
        return;
    }
    if (!self.list.count) {
        self.hint.text = err ? [NSString stringWithFormat:@"加载失败:%@\n下拉或返回后重试", err] : @"这个分类暂时没有内容";
    } else self.hint.text = @"";
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.list.count; }
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat W = cv.bounds.size.width - 32;
    CGFloat w = floor((W - 24) / 3);
    return CGSizeMake(w, w + 58);
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADCatCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    ADAlbum *a = self.list[ip.item];
    c.title.text = a.title;
    c.sub.text = a.anchor.length ? a.anchor : (a.author ?: @"");
    [ADUtil cover:c.cover url:a.cover];
    if (ip.item >= (NSInteger)self.list.count - 9) [self loadMore];
    return c;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic tap];
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.list[ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
