#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "ADInternal.h"

// ───────────────────────── 小说/书籍解析辅助 ─────────────────────────
// 不依赖具体接口形状：在 JSON 里找第一个「像是书」的数组
NSArray<ADBook *> *ADBooksFromJSON(id json, NSString *listPath) {
    id arr = nil;
    if (listPath.length) {
        arr = [ADAPI valueAt:listPath in:json];
    } else {
        for (NSString *k in @[@"data.list", @"data.items", @"data.books", @"data.results", @"data",
                              @"items", @"books", @"results", @"list", @"rows"]) {
            id v = [ADAPI valueAt:k in:json];
            if ([v isKindOfClass:[NSArray class]]) { arr = v; break; }
        }
        if (!arr && [json isKindOfClass:[NSArray class]]) arr = json;
    }
    NSMutableArray *out = [NSMutableArray array];
    if ([arr isKindOfClass:[NSArray class]]) {
        for (id o in (NSArray *)arr) {
            ADBook *b = [ADBook fromJSON:o];
            if (b && b.title.length) [out addObject:b];
        }
    }
    return out;
}

// 书籍详情可能被包在 data 里
NSDictionary *ADUnwrapBook(id json) {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *k in @[@"data", @"book", @"result", @"item"]) {
        id v = [ADAPI valueAt:k in:json];
        if ([v isKindOfClass:[NSDictionary class]] && ([ADAPI valueAt:@"chapters" in:v] || [ADAPI valueAt:@"tracks" in:v] || [ADAPI valueAt:@"id" in:v])) return v;
    }
    return json;
}

// ───────────────────────── 迷你播放条 ─────────────────────────
@interface ADMiniPlayer : UIView
+ (instancetype)shared;
- (void)refresh;
@end

@implementation ADMiniPlayer {
    UIImageView *_cover; UILabel *_title; UILabel *_sub; UIButton *_play;
}
+ (instancetype)shared {
    static ADMiniPlayer *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[ADMiniPlayer alloc] initWithFrame:CGRectMake(0, 0, 0, 64)]; [m build]; });
    return m;
}
- (void)build {
    self.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.98];
    self.layer.cornerRadius = 14; self.clipsToBounds = YES;
    _cover = [UIImageView new]; _cover.frame = CGRectMake(8, 8, 48, 48);
    _cover.layer.cornerRadius = 8; _cover.clipsToBounds = YES;
    _title = [ADUtil label:@"PingFangSC-Semibold" size:14 color:UIColor.whiteColor];
    _sub = [ADUtil label:nil size:11 color:[ADUtil dim]];
    _play = [UIButton buttonWithType:UIButtonTypeSystem];
    _play.tintColor = UIColor.whiteColor;
    [_play addTarget:self action:@selector(tapPlay) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_cover]; [self addSubview:_title]; [self addSubview:_sub]; [self addSubview:_play];
    UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBar)];
    [self addGestureRecognizer:t];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"ADPlayerTick" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"ADPlayerChanged" object:nil];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _cover.frame = CGRectMake(8, (h - 48) / 2, 48, 48);
    _play.frame = CGRectMake(w - 52, (h - 44) / 2, 44, 44);
    _title.frame = CGRectMake(64, 12, w - 128, 20);
    _sub.frame = CGRectMake(64, 32, w - 128, 16);
}
- (void)refresh {
    ADPlayer *p = [ADPlayer shared];
    ADChapter *ch = [p currentChapter];
    if (!ch) { self.hidden = YES; return; }
    self.hidden = NO;
    _title.text = ch.title;
    _sub.text = [NSString stringWithFormat:@"%@ · %@", p.book.title ?: @"", [ADUtil timeString:CMTimeGetSeconds(p.player.currentTime)]];
    [ADUtil coverInto:_cover url:p.book.cover];
    NSString *icon = p.player.rate > 0 ? @"pause.fill" : @"play.fill";
    [_play setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
}
- (void)tapPlay { [[ADPlayer shared] toggle]; [self refresh]; }
- (void)tapBar {
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    UIViewController *top = root;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────────────────── 书架 ─────────────────────────
@interface ADShelfController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSMutableArray<ADBook *> *books;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *empty;
@end

@implementation ADShelfController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"听书";
    self.view.backgroundColor = [ADUtil bg];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(reload)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];

    UISearchBar *search = [UISearchBar new];
    search.delegate = self;
    search.placeholder = @"搜索书名 / 作者";
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.tintColor = [ADUtil brand];

    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    CGFloat w = (UIScreen.mainScreen.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    lo.itemSize = CGSizeMake(w, w * 1.42 + 40);
    lo.minimumInteritemSpacing = 12; lo.minimumLineSpacing = 18;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"c"];
    self.cv.contentInset = UIEdgeInsetsMake(8, 16, 100, 16);
    self.refresh = [UIRefreshControl new];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10, *)) self.cv.refreshControl = self.refresh;
    [self.view addSubview:search]; [self.view addSubview:self.cv];

    self.empty = [ADUtil label:nil size:15 color:[ADUtil dim]];
    self.empty.textAlignment = NSTextAlignmentCenter;
    self.empty.text = @"正在加载…";
    [self.view addSubview:self.empty];

    self.books = [NSMutableArray array];
    [self layout];
    [self reload];
}
- (void)layout {
    CGFloat y = 8, sb = 56, mp = 84;
    self.cv.frame = CGRectMake(0, sb, self.view.bounds.size.width, self.view.bounds.size.height - sb - mp);
    self.empty.frame = CGRectMake(40, self.view.bounds.size.height / 2 - 40, self.view.bounds.size.width - 80, 60);
    ADMiniPlayer *m = [ADMiniPlayer shared];
    m.frame = CGRectMake(8, self.view.bounds.size.height - mp + 8, self.view.bounds.size.width - 16, 64);
    if (!m.superview) [self.view addSubview:m];
    [m refresh];
}
- (void)viewWillLayoutSubviews { [super viewWillLayoutSubviews]; [self layout]; }

- (void)reload {
    [[ADAPI shared] fetchList:nil completion:^(id json, NSError *err, NSInteger code) {
        [self.refresh endRefreshing];
        NSArray *list = ADBooksFromJSON(json, [ADConfig shared].listPath);
        if (!list.count) {
            self.empty.text = code == 200
                ? @"接口通了，但没解析到书单。\n去设置页确认「书单字段路径」，或点「查看原始返回」"
                : [NSString stringWithFormat:@"加载失败(HTTP %ld)\n%@", (long)code, err.localizedDescription ?: @""];
        } else {
            self.empty.text = @"";
        }
        self.books = [list mutableCopy];
        [self.cv reloadData];
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)sb {
    [sb resignFirstResponder];
    if (!sb.text.length) { [self reload]; return; }
    [[ADAPI shared] request:[[ADConfig shared].pathSearch stringByReplacingOccurrencesOfString:@"{q}" withString:[sb.text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]
                    method:@"GET" body:nil completion:^(id json, NSError *err, NSInteger code) {
        self.books = [ADBooksFromJSON(json, [ADConfig shared].listPath) mutableCopy];
        self.empty.text = self.books.count ? @"" : @"没搜到";
        [self.cv reloadData];
    }];
}

- (void)openSettings {
    [self.navigationController pushViewController:[ADSettingsController new] animated:YES];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.books.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    ADBook *b = self.books[ip.item];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, cell.contentView.bounds.size.width * 1.42)];
    iv.layer.cornerRadius = 10; iv.clipsToBounds = YES;
    [ADUtil coverInto:iv url:b.cover];
    UILabel *t = [ADUtil label:@"PingFangSC-Medium" size:13 color:UIColor.whiteColor];
    t.frame = CGRectMake(0, cell.contentView.bounds.size.width * 1.42 + 6, cell.contentView.bounds.size.width, 18);
    t.text = b.title; t.lineBreakMode = NSLineBreakByTruncatingTail;
    UILabel *a = [ADUtil label:nil size:11 color:[ADUtil dim]];
    a.frame = CGRectMake(0, cell.contentView.bounds.size.width * 1.42 + 24, cell.contentView.bounds.size.width, 16);
    a.text = b.author.length ? b.author : b.narrator;
    [cell.contentView addSubview:iv]; [cell.contentView addSubview:t]; [cell.contentView addSubview:a];
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    ADBook *b = self.books[ip.item];
    ADBookController *vc = [ADBookController new];
    vc.book = b;
    [self.navigationController pushViewController:vc animated:YES];
}
@end
