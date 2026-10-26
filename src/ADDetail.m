#import "AD.h"
#import <objc/runtime.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

// ───────────── 专辑详情 ─────────────
@interface ADAlbumController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *errText;
@property (nonatomic, assign) NSInteger retries;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *coverLabel;
@property (nonatomic, strong) UILabel *titleLabel, *meta, *intro, *tip;
@property (nonatomic, strong) UIButton *fav;
@property (nonatomic, strong) NSMutableArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger page, total;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) UIButton *dlBtn;
@property (nonatomic, strong) UIBarButtonItem *favBtn;
@property (nonatomic, assign) BOOL sortDesc, selecting;
@property (nonatomic, strong) NSMutableSet *selected;
@property (nonatomic, strong) UIScrollView *rangeBar;
@property (nonatomic, strong) UIScrollView *floatBar;
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, assign) NSInteger jumpTarget;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, assign) BOOL loadingAll;
// 目录分页：按页存 + 去重 + 逐页重试
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<ADTrack *> *> *pageMap;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *pageLoading;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *pageTries;
@property (nonatomic, assign) NSInteger failPage, lastPageCount;
@property (nonatomic, assign) BOOL pendingDownloadAll;
// 目录“到底了”只由事实决定：某页返回 0 条、或整页都是重复的。
// 不再拿服务端给的 total 当唯一依据——total 缺失或给错会把分页直接卡死。
@property (nonatomic, assign) BOOL endReached;
// 服务端是「按页去上游抓，抓不满就整段丢」，页宽太大容易失败 → 失败时换小页宽重抓
@property (nonatomic, assign) NSInteger pageSize;
@property (nonatomic, strong) NSArray<ADTrack *> *orderedCache;
// 详情页 UI
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIImageView *backdropImg;
@property (nonatomic, strong) UIView *chipRow, *catBar, *playBox;
@property (nonatomic, strong) UIButton *playBtn, *favCircle, *introBtn, *sortBtn, *selBtn;
@property (nonatomic, strong) UILabel *playTitle, *playSub, *catLabel;
@property (nonatomic, assign) BOOL introOpen;
@property (nonatomic, assign) NSInteger coverTries;
@property (nonatomic, copy) NSString *blurKey;
@end

// ───────────── 目录行 ─────────────
@interface ADTrackCell : UITableViewCell
@property (nonatomic, strong) UIView *hl;
@property (nonatomic, strong) UILabel *num, *name, *sub;
@property (nonatomic, strong) UIImageView *state;
@property (nonatomic, strong) UIView *barBg, *barFill;
@property (nonatomic, assign) CGFloat frac;
@end
@implementation ADTrackCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.hl = [UIView new];
        self.hl.layer.cornerRadius = 16;
        if (@available(iOS 13.0, *)) self.hl.layer.cornerCurve = kCACornerCurveContinuous;
        self.hl.layer.borderWidth = 0.6;
        [self.contentView addSubview:self.hl];
        self.num = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.38]];
        self.num.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        self.num.textAlignment = NSTextAlignmentCenter;
        self.name = [ADUtil label:nil size:15.5 color:UIColor.whiteColor];
        self.name.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightMedium];
        self.name.numberOfLines = 1;
        self.sub = [ADUtil label:nil size:12 color:[ADUtil dim]];
        self.sub.numberOfLines = 1;
        self.state = [UIImageView new];
        self.state.contentMode = UIViewContentModeCenter;
        self.barBg = [UIView new]; self.barBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
        self.barFill = [UIView new]; self.barFill.backgroundColor = [ADUtil brand];
        self.barBg.layer.cornerRadius = 1; self.barFill.layer.cornerRadius = 1;
        for (UIView *v in @[self.num, self.name, self.sub, self.state, self.barBg]) [self.contentView addSubview:v];
        [self.barBg addSubview:self.barFill];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    self.hl.frame = CGRectMake(10, 3, w - 20, h - 6);
    self.num.frame = CGRectMake(14, 0, 40, h);
    self.state.frame = CGRectMake(w - 52, 0, 36, h);
    self.name.frame = CGRectMake(60, 12, w - 60 - 56, 21);
    self.sub.frame = CGRectMake(60, 34, w - 60 - 56, 16);
    self.barBg.frame = CGRectMake(60, h - 11, w - 60 - 56, 2);
    self.barFill.frame = CGRectMake(0, 0, self.barBg.bounds.size.width * self.frac, 2);
}
- (void)setPlaying:(BOOL)on {
    self.hl.backgroundColor = on ? [[ADUtil brand] colorWithAlphaComponent:0.14] : UIColor.clearColor;
    self.hl.layer.borderColor = (on ? [[ADUtil brand] colorWithAlphaComponent:0.4] : UIColor.clearColor).CGColor;
    self.name.textColor = on ? [ADUtil brand] : UIColor.whiteColor;
    self.num.textColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.38];
}
@end

@implementation ADAlbumController

- (instancetype)init {
    if ((self = [super init])) { self.hidesBottomBarWhenPushed = YES; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.title = @"";
    self.tracks = [NSMutableArray array];
    self.total = self.album.trackCount;
    [self resetPaging];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 66;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 110, 0);
    self.table.refreshControl = [[UIRefreshControl alloc] init];
    self.table.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.table.refreshControl addTarget:self action:@selector(refreshAll) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.table];

    CGFloat w = self.view.bounds.size.width;
    // 背景：封面糊化后铺在顶部，向下渐隐（不用实时模糊，滚动不掉帧）
    self.backdrop = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 520)];
    self.backdrop.userInteractionEnabled = NO;
    self.backdropImg = [[UIImageView alloc] initWithFrame:self.backdrop.bounds];
    self.backdropImg.contentMode = UIViewContentModeScaleAspectFill;
    self.backdropImg.clipsToBounds = YES;
    self.backdropImg.alpha = 0;
    [self.backdrop addSubview:self.backdropImg];
    CAGradientLayer *mask = [CAGradientLayer layer];
    mask.frame = self.backdrop.bounds;
    mask.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.9].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor, (id)UIColor.clearColor.CGColor];
    mask.locations = @[@0, @0.55, @1];
    self.backdrop.layer.mask = mask;
    [self.view insertSubview:self.backdrop belowSubview:self.table];

    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0)];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectMake((w - 176) / 2, 10, 176, 176)];
    self.cover.layer.cornerRadius = 22;
    if (@available(iOS 13.0, *)) self.cover.layer.cornerCurve = kCACornerCurveContinuous;
    self.cover.clipsToBounds = YES;
    UIView *shadow = [[UIView alloc] initWithFrame:self.cover.frame];
    shadow.tag = 881;
    shadow.backgroundColor = UIColor.blackColor;
    shadow.layer.cornerRadius = 22;
    shadow.layer.shadowColor = UIColor.blackColor.CGColor;
    shadow.layer.shadowOpacity = 0.5; shadow.layer.shadowRadius = 26; shadow.layer.shadowOffset = CGSizeMake(0, 14);
    [head addSubview:shadow];

    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:23 color:UIColor.whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    self.meta = [ADUtil label:nil size:13.5 color:[UIColor colorWithWhite:1 alpha:0.62]];
    self.meta.textAlignment = NSTextAlignmentCenter;
    self.meta.numberOfLines = 1;
    self.chipRow = [UIView new];

    // 主按钮：继续播放 / 开始收听
    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playBtn.backgroundColor = [ADUtil brand];
    self.playBtn.layer.cornerRadius = 26;
    self.playBtn.layer.shadowColor = [ADUtil brand].CGColor;
    self.playBtn.layer.shadowOpacity = 0.4; self.playBtn.layer.shadowRadius = 14; self.playBtn.layer.shadowOffset = CGSizeMake(0, 6);
    [self.playBtn addTarget:self action:@selector(tapPrimary) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *pi = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold]]];
    pi.tintColor = UIColor.whiteColor; pi.tag = 11; pi.contentMode = UIViewContentModeCenter;
    self.playTitle = [ADUtil label:nil size:16 color:UIColor.whiteColor];
    self.playTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.playTitle.numberOfLines = 1; self.playTitle.userInteractionEnabled = NO;
    self.playSub = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.82]];
    self.playSub.numberOfLines = 1; self.playSub.userInteractionEnabled = NO;
    pi.userInteractionEnabled = NO;
    [self.playBtn addSubview:pi]; [self.playBtn addSubview:self.playTitle]; [self.playBtn addSubview:self.playSub];

    self.favCircle = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.favCircle radius:26];
    [self.favCircle addTarget:self action:@selector(toggleFav) forControlEvents:UIControlEventTouchUpInside];

    self.dlBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.dlBtn radius:26];
    self.dlBtn.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    self.dlBtn.titleLabel.numberOfLines = 2;
    self.dlBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.dlBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.dlBtn addTarget:self action:@selector(downloadAll) forControlEvents:UIControlEventTouchUpInside];

    self.intro = [ADUtil label:nil size:13.5 color:[UIColor colorWithWhite:1 alpha:0.62]];
    self.intro.numberOfLines = 3;
    self.intro.userInteractionEnabled = YES;
    [self.intro addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleIntro)]];
    self.introBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.introBtn.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    [self.introBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
    [self.introBtn addTarget:self action:@selector(toggleIntro) forControlEvents:UIControlEventTouchUpInside];

    // 目录工具行
    self.catBar = [UIView new];
    self.catLabel = [ADUtil label:@"PingFangSC-Semibold" size:18 color:UIColor.whiteColor];
    self.catLabel.numberOfLines = 1;
    self.sortBtn = [self catButton:@"arrow.up.arrow.down" title:@"正序" action:@selector(toggleSort)];
    self.selBtn = [self catButton:@"checkmark.circle" title:@"多选" action:@selector(beginSelecting)];
    [self.catBar addSubview:self.catLabel]; [self.catBar addSubview:self.sortBtn]; [self.catBar addSubview:self.selBtn];

    for (UIView *v in @[self.cover, self.titleLabel, self.meta, self.chipRow, self.playBtn, self.favCircle, self.dlBtn, self.intro, self.introBtn, self.catBar]) [head addSubview:v];
    self.table.tableHeaderView = head;

    self.selected = [NSMutableSet set];
    self.jumpTarget = -1;
    self.favBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleFav)];
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showAlbumMenu)];
    self.navigationItem.rightBarButtonItems = @[moreItem, self.favBtn];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fillHeader) name:@"ADDownloadChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:@"ADPlayerChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:@"ADDoneChanged" object:nil];
    [self fillHeader];
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] albumDetail:self.album.albumId done:^(ADAlbum *a, BOOL cached, NSString *err) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (a) {
            BOOL titleOK = a.title.length && ![a.title hasPrefix:@"album_"];
            BOOL coverOK = a.cover.length && [a.cover hasPrefix:@"http"];
            if (titleOK) self.album.title = a.title;
            if (coverOK) self.album.cover = a.cover;
            self.album.intro = a.intro.length ? a.intro : self.album.intro;
            self.album.anchor = a.anchor.length ? a.anchor : self.album.anchor;
            self.album.author = a.author.length ? a.author : self.album.author;
            self.album.provider = a.provider.length ? a.provider : self.album.provider;
            self.total = a.trackCount ?: self.total;
            [self fillHeader];
        }
        [self loadTracks];
    }];
}

- (void)playerChanged {
    if (!self.isViewLoaded || !self.view.window) return;
    [self fillHeader];
    for (NSIndexPath *ip in self.table.indexPathsForVisibleRows) {
        ADTrackCell *c = (ADTrackCell *)[self.table cellForRowAtIndexPath:ip];
        if (![c isKindOfClass:ADTrackCell.class]) continue;
        ADTrack *tr = [self ordered][ip.row];
        ADTrack *cur = ADPlayer.shared.current;
        BOOL playing = cur && [cur.trackId isEqualToString:tr.trackId] && ADPlayer.shared.album && [ADPlayer.shared.album.albumId isEqualToString:self.album.albumId];
        [c setPlaying:playing];
    }
    [self.table reloadRowsAtIndexPaths:self.table.indexPathsForVisibleRows withRowAnimation:UITableViewRowAnimationNone];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self fillHeader];
    [self.table reloadData];
    self.navigationController.navigationBar.hidden = NO;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
}

- (UIButton *)catButton:(NSString *)icon title:(NSString *)t action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:b radius:16];
    b.tintColor = UIColor.whiteColor;
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [b setTitle:[@" " stringByAppendingString:t] forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UILabel *)chip:(NSString *)t hot:(BOOL)hot {
    UILabel *l = [ADUtil label:nil size:11.5 color:hot ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.78]];
    l.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    l.text = t; l.numberOfLines = 1; l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = hot ? [[ADUtil brand] colorWithAlphaComponent:0.16] : [UIColor colorWithWhite:1 alpha:0.1];
    l.layer.cornerRadius = 11; l.clipsToBounds = YES;
    [l sizeToFit];
    l.frame = CGRectMake(0, 0, l.bounds.size.width + 18, 22);
    return l;
}

// 上次听到哪：优先看播放器当前队列，其次本地记录
- (NSDictionary *)resumeInfo {
    return [[ADStore shared] lastInfoOf:self.album.albumId];
}

- (void)updateBackdrop {
    UIImage *img = self.cover.image;
    if (!img) {
        if (self.coverTries++ < 10) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self updateBackdrop]; });
        return;
    }
    UIColor *c = [ADLiquid tintFromImage:img];
    if (c) [ADLiquid recolor:self.view with:c];
    if ([self.blurKey isEqualToString:self.album.cover ?: @""]) return;
    self.blurKey = self.album.cover ?: @"";
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
    UIImage *small = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [img drawInRect:CGRectMake(0, 0, 40, 40)]; }];
    CIImage *ci = [CIImage imageWithCGImage:small.CGImage];
    CIFilter *sat = [CIFilter filterWithName:@"CIColorControls"];
    [sat setValue:ci forKey:kCIInputImageKey]; [sat setValue:@1.5 forKey:kCIInputSaturationKey]; [sat setValue:@-0.05 forKey:kCIInputBrightnessKey];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[sat.outputImage imageByClampingToExtent] forKey:kCIInputImageKey]; [blur setValue:@3 forKey:kCIInputRadiusKey];
    CIImage *out = [blur.outputImage imageByCroppingToRect:ci.extent];
    CIContext *cx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [cx createCGImage:out fromRect:ci.extent];
    if (cg) {
        UIImage *res = [UIImage imageWithCGImage:cg]; CGImageRelease(cg);
        self.backdropImg.image = res;
        [UIView animateWithDuration:0.5 animations:^{ self.backdropImg.alpha = 0.85; }];
    }
}

- (void)toggleIntro {
    [ADHaptic select];
    self.introOpen = !self.introOpen;
    [UIView animateWithDuration:0.28 animations:^{ [self fillHeader]; }];
}

- (void)fillHeader {
    [ADUtil cover:self.cover url:self.album.cover];
    [self updateBackdrop];
    CGFloat w = self.view.bounds.size.width, m = 20;
    UIView *head = self.table.tableHeaderView;
    UIView *sh = [head viewWithTag:881];
    self.cover.frame = CGRectMake((w - 176) / 2, 10, 176, 176);
    sh.frame = self.cover.frame;
    CGFloat y = 204;

    self.titleLabel.text = self.album.title;
    CGSize ts = [self.titleLabel sizeThatFits:CGSizeMake(w - 2 * m, 80)];
    self.titleLabel.frame = CGRectMake(m, y, w - 2 * m, ts.height);
    y += ts.height + 6;

    NSMutableArray *who = [NSMutableArray array];
    if (self.album.anchor.length) [who addObject:self.album.anchor];
    if (self.album.author.length && ![self.album.author isEqualToString:self.album.anchor]) [who addObject:[@"作者 " stringByAppendingString:self.album.author]];
    if (self.album.reader.length && ![self.album.reader isEqualToString:self.album.anchor]) [who addObject:[@"演播 " stringByAppendingString:self.album.reader]];
    self.meta.text = who.count ? [who componentsJoinedByString:@" · "] : @" ";
    self.meta.frame = CGRectMake(m, y, w - 2 * m, 20);
    y += 28;

    // 标签
    for (UIView *v in [self.chipRow.subviews copy]) [v removeFromSuperview];
    NSMutableArray<UILabel *> *chips = [NSMutableArray array];
    if (self.total) [chips addObject:[self chip:[NSString stringWithFormat:@"%ld 集", (long)self.total] hot:NO]];
    if (self.album.playCount > 0) [chips addObject:[self chip:[NSString stringWithFormat:@"%@播放", [ADUtil count:self.album.playCount]] hot:NO]];
    [chips addObject:[self chip:(self.album.isFinished ? @"已完结" : @"连载中") hot:NO]];
    if (self.album.isPaid) [chips addObject:[self chip:@"VIP" hot:YES]];
    CGFloat cx = 0;
    for (UILabel *c in chips) { c.frame = CGRectMake(cx, 0, c.bounds.size.width, 22); [self.chipRow addSubview:c]; cx += c.bounds.size.width + 8; }
    cx = MAX(0, cx - 8);
    self.chipRow.frame = CGRectMake((w - cx) / 2, y, cx, 22);
    y += 22 + 18;

    // 主按钮行
    CGFloat side = 52, gap = 10;
    CGFloat pw = w - 2 * m - 2 * (side + gap);
    self.playBtn.frame = CGRectMake(m, y, pw, side);
    self.favCircle.frame = CGRectMake(m + pw + gap, y, side, side);
    self.dlBtn.frame = CGRectMake(m + pw + gap + side + gap, y, side, side);
    [ADLiquid corner:26 on:self.favCircle]; [ADLiquid corner:26 on:self.dlBtn];

    NSDictionary *info = [self resumeInfo];
    UIImageView *pi = [self.playBtn viewWithTag:11];
    pi.frame = CGRectMake(14, 0, 36, side);
    BOOL isCur = ADPlayer.shared.album && [ADPlayer.shared.album.albumId isEqualToString:self.album.albumId];
    if (isCur && ADPlayer.shared.isPlaying) {
        self.playTitle.text = @"正在播放";
        self.playSub.text = ADPlayer.shared.current.title ?: @"";
        pi.image = [UIImage systemImageNamed:@"waveform" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold]];
    } else if (info[@"trackId"]) {
        NSInteger n = [info[@"index"] integerValue] + 1;
        self.playTitle.text = @"继续播放";
        self.playSub.text = [NSString stringWithFormat:@"第 %ld 集 · 听到 %@", (long)n, [ADUtil time:[info[@"seconds"] doubleValue]]];
        pi.image = [UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold]];
    } else {
        self.playTitle.text = @"开始收听";
        self.playSub.text = self.total ? [NSString stringWithFormat:@"从第 1 集开始 · 共 %ld 集", (long)self.total] : @"从第 1 集开始";
        pi.image = [UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold]];
    }
    self.playTitle.frame = CGRectMake(54, 8, pw - 54 - 14, 21);
    self.playSub.frame = CGRectMake(54, 29, pw - 54 - 14, 16);
    y += side + 18;

    // 简介
    NSString *txt = self.album.intro.length ? self.album.intro : @"";
    self.intro.text = txt;
    self.intro.numberOfLines = self.introOpen ? 0 : 3;
    if (txt.length) {
        CGFloat full = [self.intro sizeThatFits:CGSizeMake(w - 2 * m, 2000)].height;
        CGFloat three = ceil(self.intro.font.lineHeight * 3) + 2;
        BOOL more = full > three + 1;
        CGFloat ih = self.introOpen ? full : MIN(full, three);
        self.intro.frame = CGRectMake(m, y, w - 2 * m, ih);
        y += ih;
        self.introBtn.hidden = !more;
        [self.introBtn setTitle:self.introOpen ? @"收起 ⌃" : @"展开 ⌄" forState:UIControlStateNormal];
        self.introBtn.frame = CGRectMake(w - m - 70, y, 70, 28);
        if (more) y += 28;
        y += 10;
    } else {
        self.intro.frame = CGRectMake(m, y, w - 2 * m, 0);
        self.introBtn.hidden = YES;
        y += 4;
    }

    // 目录工具行
    NSInteger shown = MAX(self.total, (NSInteger)self.tracks.count);
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"目录"];
    if (shown) [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  共 %ld 集", (long)shown]
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.5]}]];
    self.catLabel.attributedText = as;
    self.catBar.frame = CGRectMake(0, y, w, 40);
    self.catLabel.frame = CGRectMake(m, 6, w - 2 * m - 170, 28);
    self.selBtn.frame = CGRectMake(w - m - 74, 4, 74, 32);
    self.sortBtn.frame = CGRectMake(w - m - 74 - 8 - 74, 4, 74, 32);
    [self.sortBtn setTitle:self.sortDesc ? @" 倒序" : @" 正序" forState:UIControlStateNormal];
    y += 40;

    CGFloat h = y + 44;     // 44 给分段条
    head.frame = CGRectMake(0, 0, w, h);
    self.table.tableHeaderView = head;

    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    NSString *t2; UIColor *tc = UIColor.whiteColor;
    if (self.pendingDownloadAll) t2 = [NSString stringWithFormat:@"取目录\n%ld/%ld", (long)self.tracks.count, (long)MAX(self.total, (NSInteger)self.tracks.count)];
    else if (task) {
        if (task.state == ADTaskStateDone) { t2 = @"已缓存"; tc = [ADUtil brand]; }
        else if (task.state == ADTaskStatePaused) t2 = [NSString stringWithFormat:@"暂停\n%ld/%ld", (long)task.done, (long)task.tracks.count];
        else t2 = [NSString stringWithFormat:@"缓存中\n%ld/%ld", (long)task.done, (long)task.tracks.count];
    } else t2 = @"";
    if (t2.length) {
        [self.dlBtn setImage:nil forState:UIControlStateNormal];
        [self.dlBtn setTitle:t2 forState:UIControlStateNormal];
        [self.dlBtn setTitleColor:tc forState:UIControlStateNormal];
    } else {
        [self.dlBtn setTitle:@"" forState:UIControlStateNormal];
        [self.dlBtn setImage:[UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
        self.dlBtn.tintColor = UIColor.whiteColor;
    }
    BOOL fav = [[ADStore shared] isFavorite:self.album.albumId];
    [self.favCircle setImage:[UIImage systemImageNamed:fav ? @"heart.fill" : @"heart" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    self.favCircle.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    [self.favBtn setImage:[UIImage systemImageNamed:fav ? @"heart.fill" : @"heart"]];
    self.favBtn.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    [self buildRangeBar];
}

// 主按钮：续播 / 开始
- (void)tapPrimary {
    [ADHaptic tap];
    ADPlayer *p = ADPlayer.shared;
    BOOL isCur = p.album && [p.album.albumId isEqualToString:self.album.albumId] && p.tracks.count;
    if (isCur) {
        if (!p.isPlaying) [p toggle];
        [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
        return;
    }
    NSDictionary *info = [self resumeInfo];
    NSString *tid = info[@"trackId"];
    NSInteger found = -1;
    if (tid.length) for (NSInteger i = 0; i < (NSInteger)self.tracks.count; i++) if ([self.tracks[i].trackId isEqualToString:tid]) { found = i; break; }
    if (found >= 0) { [p playAlbum:self.album tracks:self.tracks at:found]; }
    else if (tid.length) { [p openAlbum:self.album trackId:tid index:[info[@"index"] integerValue] seconds:[info[@"seconds"] doubleValue] autoPlay:YES]; }
    else if (self.tracks.count) { [p playAlbum:self.album tracks:self.tracks at:0]; }
    else return;
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}

- (void)setSortDescending:(BOOL)desc {
    if (desc == self.sortDesc) return;
    self.sortDesc = desc;
    self.orderedCache = nil;
    [self.table reloadData];
    if (desc) {
        self.endReached = NO;        // 倒序必须拿到真正的最后一集，不能信 total
        self.hasMore = YES;
        self.loadingAll = YES;
        self.errText = nil;
        [self loadTracks];
    }
    [self fillHeader];
}
- (void)toggleSort { [ADHaptic select]; [self setSortDescending:!self.sortDesc]; }

- (NSArray<ADTrack *> *)ordered {
    if (!self.sortDesc) return self.tracks;
    if (!self.orderedCache || self.orderedCache.count != self.tracks.count)
        self.orderedCache = [[self.tracks reverseObjectEnumerator] allObjects];
    return self.orderedCache;
}

- (void)showAlbumMenu {
    [ADHaptic tap];
    [ADOptionSheet showIn:self title:self.album.title options:@[@"选择剧集下载", @"目录正序", @"目录倒序", @"缓存整本到本机", @"刷新目录", @"目录诊断"] destructive:-1 choose:^(NSInteger i) {
        if (i == 0) [self beginSelecting];
        else if (i == 1) [self setSortDescending:NO];
        else if (i == 2) [self setSortDescending:YES];
        else if (i == 3) [self downloadAll];
        else if (i == 4) [self refreshAll];
        else [self runProbe];
    }];
}

- (void)buildRangeBar {
    if (!self.rangeBar) {
        self.rangeBar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        self.rangeBar.showsHorizontalScrollIndicator = NO;
        self.rangeBar.contentInset = UIEdgeInsetsMake(0, 16, 0, 16);
    }
    for (UIView *v in self.rangeBar.subviews) [v removeFromSuperview];
    NSInteger total = self.total > 0 ? self.total : MAX((NSInteger)self.tracks.count, (NSInteger)60);
    if (self.hasMore) total = MAX(total, (NSInteger)self.tracks.count + 60);   // 总数未知时多一段
    NSInteger step = 60;
    NSInteger n = (total + step - 1) / step;
    CGFloat x = 16;
    for (NSInteger i = 0; i < n && i < 60; i++) {
        NSInteger s0 = i * step + 1, s1 = MIN((i + 1) * step, total);
        NSString *t = [NSString stringWithFormat:@"%ld–%ld", (long)s0, (long)s1];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        CGSize sz = [t sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}];
        CGFloat w = sz.width + 26;
        b.frame = CGRectMake(x, 4, w, 32);
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        b.layer.cornerRadius = 16;
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
        [b setTitle:t forState:UIControlStateNormal];
        b.tag = 2000 + i * step;
        [b addTarget:self action:@selector(tapRange:) forControlEvents:UIControlEventTouchUpInside];
        [self.rangeBar addSubview:b];
        x += w + 8;
    }
    self.rangeBar.contentSize = CGSizeMake(x + 8, 44);
    UIView *head = self.table.tableHeaderView;
    if (!self.floatBar) {
        self.floatBar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        self.floatBar.showsHorizontalScrollIndicator = NO;
        self.floatBar.contentInset = UIEdgeInsetsMake(0, 16, 0, 16);
        [ADLiquid glass:self.floatBar radius:18 alpha:0.05];
        self.floatBar.hidden = YES;
        [self.view addSubview:self.floatBar];
    }
    for (UIView *v in self.floatBar.subviews) [v removeFromSuperview];
    for (UIView *src in self.rangeBar.subviews) {
        if (![src isKindOfClass:UIButton.class]) continue;
        UIButton *b = (UIButton *)src;
        UIButton *copy = [UIButton buttonWithType:UIButtonTypeCustom];
        copy.frame = b.frame;
        copy.tag = b.tag;
        copy.titleLabel.font = b.titleLabel.font;
        copy.layer.cornerRadius = b.layer.cornerRadius;
        copy.backgroundColor = b.backgroundColor;
        [copy setTitle:[b titleForState:UIControlStateNormal] forState:UIControlStateNormal];
        [copy setTitleColor:[b titleColorForState:UIControlStateNormal] forState:UIControlStateNormal];
        [copy addTarget:self action:@selector(tapRange:) forControlEvents:UIControlEventTouchUpInside];
        [self.floatBar addSubview:copy];
    }
    self.floatBar.contentSize = self.rangeBar.contentSize;
    if (self.rangeBar.superview != head) [head addSubview:self.rangeBar];
    self.rangeBar.frame = CGRectMake(0, head.bounds.size.height - 44, self.view.bounds.size.width, 44);
}

- (void)tapRange:(UIButton *)b {
    [ADHaptic select];
    NSInteger start = b.tag - 2000;
    for (UIScrollView *bar in @[self.rangeBar, self.floatBar]) {
        for (UIView *v in bar.subviews) {
            if (![v isKindOfClass:UIButton.class]) continue;
            UIButton *btn = (UIButton *)v;
            btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
            [btn setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
        }
    }
    for (UIScrollView *bar in @[self.rangeBar, self.floatBar]) {
        for (UIView *v in bar.subviews) {
            if ([v isKindOfClass:UIButton.class] && v.tag == b.tag) {
                UIButton *btn = (UIButton *)v;
                btn.backgroundColor = UIColor.whiteColor;
                [btn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
            }
        }
    }
    [self jumpTo:start];
}

- (NSInteger)rowForIndex:(NSInteger)idx {
    NSInteger n = self.tracks.count;
    if (n <= 0) return 0;
    if (idx >= n) idx = n - 1;
    return self.sortDesc ? (n - 1 - idx) : idx;
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (sv != self.table) return;
    UIView *head = self.table.tableHeaderView;
    CGFloat off = sv.contentOffset.y + sv.adjustedContentInset.top;
    self.backdrop.transform = CGAffineTransformMakeTranslation(0, -off);
    self.cover.transform = off < 0 ? CGAffineTransformMakeScale(1 + MIN(0.25, -off / 600), 1 + MIN(0.25, -off / 600)) : CGAffineTransformIdentity;
    [head viewWithTag:881].transform = self.cover.transform;
    NSString *want = off > 150 ? (self.album.title ?: @"") : @"";
    if (![self.title isEqualToString:want]) self.title = want;
    CGFloat barTop = head.bounds.size.height - 44 - self.table.contentOffset.y;
    CGFloat safe = MAX(self.view.safeAreaInsets.top, 44) + 44;
    self.floatBar.hidden = !(barTop < safe);
    self.floatBar.frame = CGRectMake(0, safe - 44, self.view.bounds.size.width, 44);
}

- (void)jumpTo:(NSInteger)idx {
    if (idx < (NSInteger)self.tracks.count) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:[self rowForIndex:idx] inSection:0];
        [self.table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
        return;
    }
    self.errText = nil;
    self.jumpTarget = idx;
    self.endReached = NO;            // 用户明确要跳到这一段，先把“到底了”解开
    self.hasMore = YES;
    self.loadingAll = NO;
    [self loadNextPage];
}

// 把一批候选请求一次打完，结果写到 Documents/probe_<专辑>.txt
- (void)runProbe {
    NSString *aid = self.album.albumId;
    NSArray<NSString *> *paths = @[
        [NSString stringWithFormat:@"/open-api/v1/albums/%@", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=50", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?pageSize=500", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=260", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=50&targetChapterIndex=1", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=50&full=1", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=50&mode=full", aid],
        [NSString stringWithFormat:@"/open-api/v1/albums/%@/tracks?page=1&pageSize=50&provider=xm", aid],
    ];
    NSMutableString *out = [NSMutableString stringWithFormat:@"albumId=%@\nprovider=%@\ntrackCount=%ld\n\n",
                            aid, self.album.provider, (long)self.album.trackCount];
    UIAlertController *busy = [UIAlertController alertControllerWithTitle:@"目录诊断" message:@"正在逐个请求…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:busy animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t next = nil;
    __block NSUInteger idx = 0;
    __block dispatch_block_t step = nil;
    step = ^{
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (idx >= paths.count) {
            NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *f = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"probe_%@.txt", aid]];
            [out writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [busy dismissViewControllerAnimated:YES completion:^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"诊断完成"
                    message:[NSString stringWithFormat:@"已写入 probe_%@.txt\n文件 App → 我的 iPhone → 听书 里可以取到。", aid]
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }];
            return;
        }
        NSString *p = paths[idx++];
        [[ADApi shared] rawGET:p timeout:20 done:^(NSInteger code, NSString *body, NSString *err) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            NSString *b = body.length > 700 ? [[body substringToIndex:700] stringByAppendingString:@"…"] : body;
            [out appendFormat:@"### %@\nHTTP %ld%@\n%@\n\n", p, (long)code,
                err.length ? [NSString stringWithFormat:@" err=%@", err] : @"", b];
            step();
        }];
    };
    (void)next;
    if ([[ADApi shared] hasAccount]) {
        [[ADApi shared] panelLogin:^(BOOL ok, NSString *err) {
            [out appendFormat:@"### 网页登录 %@ %@\n\n", ok ? @"成功" : @"失败", err ?: @""];
            step();
        }];
    } else {
        [out appendString:@"### 未填网页账号（只能在 token 接口下试）\n\n"];
        step();
    }
}

- (void)beginSelecting {
    self.selecting = YES;
    [self.selected removeAllObjects];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(endSelecting)];
    self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithTitle:@"全选" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)]];
    [self showActionBar];
    [self.table reloadData];
}

- (void)selectAll {
    for (ADTrack *t in self.ordered) [self.selected addObject:t.trackId];
    [self updateActionBar];
    [self.table reloadData];
}

- (void)endSelecting {
    self.selecting = NO;
    [self.selected removeAllObjects];
    self.navigationItem.leftBarButtonItem = nil;
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showAlbumMenu)];
    self.navigationItem.rightBarButtonItems = @[moreItem, self.favBtn];
    [self.actionBar removeFromSuperview];
    self.actionBar = nil;
    [self.table reloadData];
}

- (void)showActionBar {
    if (self.actionBar) return;
    CGFloat h = 56;
    self.actionBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - h, self.view.bounds.size.width, h)];
    [ADLiquid glass:self.actionBar radius:0 alpha:0.05];
    self.actionLabel = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.7]];
    self.actionLabel.frame = CGRectMake(16, 18, 160, 20);
    [self.actionBar addSubview:self.actionLabel];
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    go.frame = CGRectMake(self.view.bounds.size.width - 132, 10, 120, 36);
    go.backgroundColor = [ADUtil brand];
    go.layer.cornerRadius = 18;
    go.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [go setTitle:@"缓存所选" forState:UIControlStateNormal];
    [go setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [go addTarget:self action:@selector(downloadSelected) forControlEvents:UIControlEventTouchUpInside];
    [self.actionBar addSubview:go];
    [self.view addSubview:self.actionBar];
    [self updateActionBar];
}

- (void)updateActionBar {
    self.actionLabel.text = [NSString stringWithFormat:@"已选 %ld 集", (long)self.selected.count];
}

- (void)downloadSelected {
    if (!self.selected.count) return;
    NSMutableArray *arr = [NSMutableArray array];
    for (ADTrack *t in self.tracks) if ([self.selected containsObject:t.trackId]) [arr addObject:t];
    [ADHaptic success];
    [[ADDownloader shared] addTracks:self.album tracks:arr];
    NSUInteger n = arr.count;
    [self endSelecting];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    [self fillHeader];
    UIAlertController *c = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"已加入下载队列 %ld 集", (long)n] preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:c animated:YES completion:nil];
}

- (void)downloadOne:(ADTrack *)t {
    [ADHaptic tap];
    [[ADDownloader shared] addTracks:self.album tracks:@[t]];
    [self fillHeader];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

- (void)refreshAll {
    self.loadingAll = NO;
    self.pendingDownloadAll = NO;
    self.jumpTarget = -1;
    [self resetPaging];
    [self updateFooter];
    [self.table reloadData];
    [self loadPage:1];
    [self.table.refreshControl endRefreshing];
}

- (void)downloadAll {
    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (task && task.state == ADTaskStateRunning) { [[ADDownloader shared] pauseTask:task]; [self fillHeader]; return; }
    if (task && task.state == ADTaskStatePaused) { [[ADDownloader shared] resumeTask:task]; [self fillHeader]; return; }
    if (!self.tracks.count) return;
    // 目录没拉全时先拉全，否则「缓存整本」只会缓存已经看到的这几十集
    if (self.hasMore) {
        self.pendingDownloadAll = YES;
        self.loadingAll = YES;
        self.errText = nil;
        [self fillHeader];
        [self loadNextPage];
        return;
    }
    [[ADDownloader shared] addAlbum:self.album tracks:self.tracks];
    [self fillHeader];
}

- (void)toggleFav {
    [ADHaptic tap];
    [[ADStore shared] toggleFavorite:self.album];
    [self fillHeader];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

// ── 目录分页 ────────────────────────────────────────────
// 以前是「回调里直接 addObjectsFromArray + page++」，而网络层是“先给缓存再给网络”，
// 同一页会回调两次 → 列表重复、page 跳号、中间几页永远拉不到。
// 现在按页存 pageMap，网络结果覆盖缓存结果，重建时按页号排序并按 trackId 去重。
- (void)resetPaging {
    self.page = 1;
    self.pageMap = [NSMutableDictionary dictionary];
    self.pageLoading = [NSMutableSet set];
    self.pageTries = [NSMutableDictionary dictionary];
    self.failPage = 0;
    self.lastPageCount = 0;
    self.errText = nil;
    self.endReached = NO;
    self.orderedCache = nil;
    self.pageSize = 50;
    self.hasMore = YES;
    self.loading = NO;
    [self.tracks removeAllObjects];
}

- (void)rebuildTracks {
    NSArray<NSNumber *> *keys = [[self.pageMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<ADTrack *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSInteger lastCount = 0;
    for (NSNumber *k in keys) {
        NSArray<ADTrack *> *arr = self.pageMap[k];
        lastCount = (NSInteger)arr.count;
        for (ADTrack *t in arr) {
            if (t.trackId.length) {
                if ([seen containsObject:t.trackId]) continue;
                [seen addObject:t.trackId];
            }
            [out addObject:t];
        }
    }
    self.lastPageCount = lastCount;
    self.tracks = out;
    self.orderedCache = nil;
    self.hasMore = !self.endReached;
}

- (void)loadTracks {
    if (!self.pageMap.count) { [self loadPage:1]; return; }
    if (self.hasMore) [self loadNextPage];
}

- (void)loadNextPage {
    if (!self.hasMore) return;
    if (self.pageLoading.count >= 2) return;   // 同时最多拉两页，避免列表滚动时一口气发一堆请求
    NSInteger p = 1;
    while (([self.pageMap objectForKey:@(p)] || [self.pageLoading containsObject:@(p)]) && p < 400) p++;
    if (p >= 400) { self.endReached = YES; self.hasMore = NO; return; }
    [self loadPage:p];
}

// 页宽逐个试：先小（上游常常一次给不满）再大（可能一次给全）
- (BOOL)shrinkPageSize {
    static const NSInteger sizes[] = {50, 20, 10, 5, 100, 260};
    for (int i = 0; i < 6; i++) {
        if (sizes[i] == self.pageSize && i + 1 < 6) { self.pageSize = sizes[i + 1]; return YES; }
    }
    return NO;
}

- (void)loadPage:(NSInteger)p {
    if (p < 1 || [self.pageLoading containsObject:@(p)]) return;
    [self.pageLoading addObject:@(p)];
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] tracksOf:self.album.albumId page:p pageSize:self.pageSize done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (total > 0) self.total = total;
        // 缓存：先铺一层，网络结果随后覆盖同一页
        if (cached && !err.length) {
            if (![self.pageMap objectForKey:@(p)] && list.count) {
                self.pageMap[@(p)] = list;
                [self rebuildTracks];
                [self.table reloadData];
                [self fillHeader];
            }
            return;
        }
        [self.pageLoading removeObject:@(p)];
        BOOL netEmptyFirst = (!cached && list.count == 0 && p == 1);
        if (err.length || netEmptyFirst) {
            NSInteger tries = [self.pageTries[@(p)] integerValue];
            if (tries < (p == 1 ? 1 : 2)) {     // 第 1 页抓不到多半是页宽问题，少重试、赶紧换页宽
                self.pageTries[@(p)] = @(tries + 1);
                __weak typeof(self) w2 = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * (tries + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(w2) s = w2; if (!s) return;
                    [s loadPage:p];
                });
            } else if (p == 1 && [self shrinkPageSize]) {
                // 第 1 页就抓不到：换小页宽让服务端重新去上游抓
                self.pageTries = [NSMutableDictionary dictionary];
                self.pageMap = [NSMutableDictionary dictionary];
                self.orderedCache = nil;
                self.errText = nil;
                [self.table reloadData];
                [self fillHeader];
                [self loadPage:1];
                return;
            } else {
                self.failPage = p;
                self.errText = err.length ? err : @"这一页目录没取到";
                self.loadingAll = NO;
                self.pendingDownloadAll = NO;
                [self.table reloadData];
                [self updateFooter];
                [self fillHeader];
            }
            return;
        }
        // 空页：先当作“可能只是抖动”，补一次；还是空才算真的到底
        if (!cached && list.count == 0 && p > 1) {
            if ([self.pageTries[@(p)] integerValue] < 1) {
                self.pageTries[@(p)] = @1;
                __weak typeof(self) w3 = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(w3) s3 = w3; if (!s3) return;
                    [s3 loadPage:p];
                });
                return;
            }
            [self.pageTries removeObjectForKey:@(p)];
            self.endReached = YES;
            self.hasMore = NO;
            self.loadingAll = NO;
            [self.table reloadData];
            [self fillHeader];
            [self updateFooter];
            if (self.sortDesc && self.tracks.count) {   // 拉全后把真正的最后一集顶到首位
                [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                                    atScrollPosition:UITableViewScrollPositionTop animated:NO];
            }
            if (self.jumpTarget >= 0) {   // 想跳的那段超出了实际集数，至少落到最后一行
                NSInteger last = MAX(0, (NSInteger)self.tracks.count - 1);
                self.jumpTarget = -1;
                [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[self rowForIndex:last] inSection:0]
                                    atScrollPosition:UITableViewScrollPositionBottom animated:YES];
            }
            if (self.pendingDownloadAll) { self.pendingDownloadAll = NO; [self downloadAll]; }
            return;
        }
        [self.pageTries removeObjectForKey:@(p)];
        self.errText = nil;
        self.failPage = 0;
        NSInteger before = (NSInteger)self.tracks.count;
        BOOL shortPage = list.count > 0 && list.count < 50;
        self.pageMap[@(p)] = list ?: @[];
        [self rebuildTracks];
        NSInteger added = (NSInteger)self.tracks.count - before;
        if (list.count > 0 && added <= 0) self.endReached = YES;         // 整页都是重复的：服务端没有更多了
        if (shortPage && self.total > 0 && (NSInteger)self.tracks.count >= self.total) self.endReached = YES;
        if (self.total > 0 && (NSInteger)self.tracks.count > self.total) self.total = 0;   // total 给少了，弃用
        self.hasMore = !self.endReached;
        if (self.tracks.count && !ADPlayer.shared.album) {
            ADPlayer.shared.album = self.album;
            ADPlayer.shared.tracks = self.tracks;
        } else if (ADPlayer.shared.album && [ADPlayer.shared.album.albumId isEqualToString:self.album.albumId]
                   && self.tracks.count > ADPlayer.shared.tracks.count) {
            ADPlayer.shared.tracks = self.tracks;   // 目录补全后同步播放队列（只增不减）
        }
        [self.table reloadData];
        [self fillHeader];
        [self updateFooter];
        if (self.jumpTarget >= 0) {
            if ((NSInteger)self.tracks.count > self.jumpTarget) {
                NSIndexPath *ip = [NSIndexPath indexPathForRow:[self rowForIndex:self.jumpTarget] inSection:0];
                self.jumpTarget = -1;
                [self.table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
            } else if (self.hasMore) {
                [self loadNextPage];
            } else {
                self.jumpTarget = -1;
            }
            return;
        }
        if (self.loadingAll) {
            if (self.hasMore) {
                [self loadNextPage];
            } else {
                self.loadingAll = NO;
                [self.table reloadData];
                if (self.sortDesc && self.tracks.count) {   // 拉全后把真正的最后一集顶到首位
                    [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                                        atScrollPosition:UITableViewScrollPositionTop animated:NO];
                }
                if (self.pendingDownloadAll) { self.pendingDownloadAll = NO; [self downloadAll]; }
            }
        }
    }];
}

- (void)updateFooter {
    if (!self.errText.length) {
        if (!self.tracks.count && (self.loading || self.pageLoading.count)) {
            UIView *f = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 90)];
            UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            sp.color = [UIColor colorWithWhite:1 alpha:0.6];
            sp.center = CGPointMake(f.bounds.size.width / 2, 40);
            [sp startAnimating]; [f addSubview:sp];
            UILabel *l = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.45]];
            l.text = @"正在获取目录…"; l.textAlignment = NSTextAlignmentCenter;
            l.frame = CGRectMake(0, 56, f.bounds.size.width, 18);
            [f addSubview:l];
            self.table.tableFooterView = f;
        } else self.table.tableFooterView = [UIView new];
        return;
    }
    CGFloat w = self.view.bounds.size.width;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0, 0, w, self.tracks.count ? 84 : 120);
    b.titleLabel.numberOfLines = 0;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.titleLabel.font = [UIFont systemFontOfSize:13];
    NSString *head = self.tracks.count
        ? [NSString stringWithFormat:@"第 %ld 段目录没取到（%@）", (long)self.failPage, self.errText]
        : self.errText;
    [b setTitle:[NSString stringWithFormat:@"%@\n已加载 %ld 集 · 点这里重试", head, (long)self.tracks.count]
       forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.55] forState:UIControlStateNormal];
    [b addTarget:self action:@selector(retryTracks) forControlEvents:UIControlEventTouchUpInside];
    self.table.tableFooterView = b;
}

- (void)retryTracks {
    NSInteger p = self.failPage > 0 ? self.failPage : (self.page > 0 ? self.page : 1);
    self.errText = nil;
    self.failPage = 0;
    [self.pageTries removeAllObjects];
    [self updateFooter];
    [self.table reloadData];
    [self loadPage:p];
}

- (void)playFrom:(NSInteger)index {
    [ADHaptic tap];
    ADPlayer *p = ADPlayer.shared;
    NSArray *order = [self ordered];
    ADTrack *target = order[index];
    NSInteger idx = 0;
    if (self.sortDesc) {
        // 倒序展示时，播放列表仍按正序，定位到对应集
        for (NSInteger i = 0; i < (NSInteger)self.tracks.count; i++) if ([self.tracks[i].trackId isEqualToString:target.trackId]) { idx = i; break; }
        [p playAlbum:self.album tracks:self.tracks at:idx];
    } else {
        [p playAlbum:self.album tracks:self.tracks at:index];
    }
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return nil;
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)v;
    h.textLabel.textColor = [ADUtil dim];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.tracks.count; }
- (NSArray<UITableViewRowAction *> *)legacyActions { return nil; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"tr";
    ADTrackCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[ADTrackCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    ADTrack *tr = [self ordered][ip.row];
    NSInteger n = self.tracks.count;
    c.num.text = [NSString stringWithFormat:@"%ld", (long)(self.sortDesc ? n - ip.row : ip.row + 1)];
    c.name.text = tr.title;
    double pos = [[ADStore shared] positionFor:tr.trackId];
    BOOL listened = [[ADStore shared] isDone:tr.trackId];
    BOOL local = [[ADDownloader shared] hasLocal:tr.trackId];
    NSMutableArray *bits = [NSMutableArray array];
    if (tr.duration > 0) [bits addObject:[ADUtil time:tr.duration]];
    if (listened) [bits addObject:@"已听完"];
    else if (pos > 5) [bits addObject:[NSString stringWithFormat:@"听到 %@", [ADUtil time:pos]]];
    if (local) [bits addObject:@"离线可听"];
    c.sub.text = [bits componentsJoinedByString:@" · "];
    c.sub.textColor = (local && !listened) ? [ADUtil brand] : [ADUtil dim];
    c.frac = (!listened && pos > 5 && tr.duration > 0) ? MIN(1, pos / tr.duration) : 0;
    c.barBg.hidden = c.frac <= 0;
    ADTrack *cur = ADPlayer.shared.current;
    BOOL playing = cur && [cur.trackId isEqualToString:tr.trackId] && ADPlayer.shared.album && [ADPlayer.shared.album.albumId isEqualToString:self.album.albumId];
    [c setPlaying:playing];
    UIImageSymbolConfiguration *sc = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    if (self.selecting) {
        BOOL on = [self.selected containsObject:tr.trackId];
        c.state.image = [UIImage systemImageNamed:on ? @"checkmark.circle.fill" : @"circle" withConfiguration:sc];
        c.state.tintColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.35];
    } else if (playing) {
        c.state.image = [UIImage systemImageNamed:(ADPlayer.shared.isPlaying ? @"waveform" : @"pause.fill") withConfiguration:sc];
        c.state.tintColor = [ADUtil brand];
    } else if (listened) {
        c.state.image = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:sc];
        c.state.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
    } else if (local) {
        c.state.image = [UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:sc];
        c.state.tintColor = [[ADUtil brand] colorWithAlphaComponent:0.85];
    } else {
        c.state.image = nil;
    }
    c.accessoryType = UITableViewCellAccessoryNone;
    [c setNeedsLayout];
    // 触底加载
    if (!self.selecting && self.hasMore && self.jumpTarget < 0 && ip.row >= (NSInteger)self.tracks.count - 6) [self loadNextPage];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    ADTrack *tr = [self ordered][ip.row];
    if (self.selecting) {
        if ([self.selected containsObject:tr.trackId]) [self.selected removeObject:tr.trackId];
        else [self.selected addObject:tr.trackId];
        [self updateActionBar];
        [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    [self playFrom:ip.row];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    ADTrack *tr = [self ordered][ip.row];
    BOOL local = [[ADDownloader shared] hasLocal:tr.trackId];
    UIContextualAction *act = [UIContextualAction contextualActionWithStyle:(local ? UIContextualActionStyleDestructive : UIContextualActionStyleNormal)
                                                                     title:(local ? @"删除缓存" : @"下载本集")
                                                                   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        if (local) {
            [[ADDownloader shared] removeLocal:tr.trackId];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ADDownloadChanged" object:nil];
        } else {
            [self downloadOne:tr];
        }
        [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        done(YES);
    }];
    act.backgroundColor = local ? [UIColor systemRedColor] : [ADUtil brand];
    return [UISwipeActionsConfiguration configurationWithActions:@[act]];
}
@end

// ───────────── 播放器 ─────────────
@interface ADPlayerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *coverLabel;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *mid, *duration, *status;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *playBtn, *starBtn, *moreBtn;
@property (nonatomic, strong) AVRoutePickerView *routeView;
@property (nonatomic, strong) UIButton *rateBtn, *sleepBtn;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) UITableView *queue;
@property (nonatomic, strong) UIView *queueDim;
@property (nonatomic, assign) BOOL showQueue;
@property (nonatomic, assign) BOOL queueDesc, queueSelecting;
@property (nonatomic, strong) NSMutableSet *queueSel;
@property (nonatomic, strong) UIView *queueBar;
@property (nonatomic, strong) UIButton *sortBtn, *pickBtn, *selBtn, *dlBtn;
@end

@implementation ADPlayerController

- (instancetype)init {
    if ((self = [super init])) {
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
        } else {
            self.modalPresentationStyle = UIModalPresentationFullScreen;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.16 green:0.15 blue:0.15 alpha:1];

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 28;
        }
    }

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    bg.frame = self.view.bounds;
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bg];

    self.cover = [UIImageView new];
    self.cover.layer.cornerRadius = 20;
    self.cover.clipsToBounds = YES;
    self.cover.contentMode = UIViewContentModeScaleAspectFill;
    self.cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:26 color:UIColor.whiteColor];
    self.titleLabel.numberOfLines = 2;
    self.subLabel = [ADUtil label:nil size:17 color:[UIColor colorWithWhite:1 alpha:0.62]];

    self.starBtn = [self circleButton:@"star" action:@selector(toggleFav)];
    self.moreBtn = [self circleButton:@"ellipsis" action:@selector(showMore)];
    UIButton *more = self.moreBtn;

    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.95];
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    [self.slider setThumbImage:[self dot:16] forState:UIControlStateNormal];
    [self.slider addTarget:self action:@selector(sliderBegin) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(sliderMoving) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    self.elapsed = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.75]];
    self.mid = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.55]];
    self.duration = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.55]];
    self.status = [ADUtil label:nil size:12 color:[ADUtil brand]];
    self.status.textAlignment = NSTextAlignmentCenter;

    self.playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playBtn.tintColor = UIColor.whiteColor;
    [self.playBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[self.cover, self.titleLabel, self.subLabel, self.starBtn, more, self.slider,
                        self.elapsed, self.mid, self.duration, self.status, self.playBtn]) {
        [self.view addSubview:v];
    }

    // 控制行
    UIButton *prev = [self iconButton:@"backward.end.fill" size:21 action:@selector(prev)];
    UIButton *back = [self iconButton:@"gobackward.15" size:25 action:@selector(back15)];
    UIButton *fwd = [self iconButton:@"goforward.15" size:25 action:@selector(fwd15)];
    UIButton *next = [self iconButton:@"forward.end.fill" size:21 action:@selector(next)];
    prev.tag = 201; back.tag = 202; fwd.tag = 203; next.tag = 204;
    for (UIButton *b in @[prev, back, fwd, next]) [self.view addSubview:b];

    // 底部工具行
    self.rateBtn = [self textButton:@"1x" action:@selector(showRateMenu)];
    self.sleepBtn = [self iconButton:@"moon.zzz.fill" size:22 action:@selector(showSleepMenu)];
    UIButton *list = [self iconButton:@"list.bullet" size:22 action:@selector(showQueueList)];
    self.rateBtn.tag = 301; self.sleepBtn.tag = 302; list.tag = 304;
    [self.view addSubview:self.rateBtn];
    [self.view addSubview:self.sleepBtn];
    [self.view addSubview:list];

    UIView *toolPill = [[UIView alloc] initWithFrame:CGRectZero];
    toolPill.tag = 900;
    toolPill.userInteractionEnabled = NO;
    [ADLiquid glass:toolPill radius:24 alpha:0.05];
    [ADLiquid float:toolPill];
    toolPill.layer.shadowOpacity = 0.22;
    [self.view addSubview:toolPill];
    [self.view insertSubview:toolPill belowSubview:self.rateBtn];

    self.routeView = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 44, 36)];
    self.routeView.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    self.routeView.activeTintColor = [ADUtil brand];
    self.routeView.prioritizesVideoDevices = NO;
    [self.view addSubview:self.routeView];

    self.queue = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    [ADLiquid glass:self.queue radius:20 alpha:0.035];
    self.queue.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    self.queue.dataSource = self;
    self.queue.delegate = self;
    self.queue.hidden = YES;
    self.queue.layer.cornerRadius = 18;
    self.queue.clipsToBounds = YES;
    self.queueDim = [[UIView alloc] initWithFrame:self.view.bounds];
    self.queueDim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    self.queueDim.hidden = YES;
    [self.queueDim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeQueue)]];
    [self.view addSubview:self.queueDim];
    [self.view addSubview:self.queue];

    self.queueSel = [NSMutableSet set];
    self.queueBar = [[UIView alloc] initWithFrame:CGRectZero];
    [ADLiquid glass:self.queueBar radius:16 alpha:0.05];
    self.queueBar.hidden = YES;
    [self.view addSubview:self.queueBar];
    self.sortBtn = [self barButton:@"正序" action:@selector(toggleQueueSort)];
    self.pickBtn = [self barButton:@"选集" action:@selector(showQueuePicker)];
    self.selBtn  = [self barButton:@"多选" action:@selector(toggleQueueSelect)];
    self.dlBtn   = [self barButton:@"缓存整本" action:@selector(queueDownload)];
    for (UIButton *b in @[self.sortBtn, self.pickBtn, self.selBtn, self.dlBtn]) [self.queueBar addSubview:b];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerTick" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:@"ADPlayerChanged" object:nil];
    [self sync];
}

- (UIImage *)dot:(CGFloat)d {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.whiteColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
    }];
}

- (UIButton *)circleButton:(NSString *)icon action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:b radius:22];
    b.tintColor = UIColor.whiteColor;
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)iconButton:(NSString *)icon size:(CGFloat)size action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)textButton:(NSString *)text action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    // 各块固定高度：标题 70 / 进度 28 / 时间 30 / 控制 80 / 底部 40
    CGFloat top = safeTop + 16;
    CGFloat bottomPad = safeBottom + 16;
    CGFloat blockH = 70 + 28 + 30 + 80 + 40;
    CGFloat lastGap = 18;                 // 控制行与底部工具行固定贴近
    CGFloat coverMax = MIN(W - 24, H * 0.52);
    CGFloat leftover = H - top - bottomPad - blockH - coverMax - lastGap;
    CGFloat coverH = coverMax;
    if (leftover < 0) { coverH = MAX(140, coverMax + leftover); leftover = 0; }
    CGFloat gap = MIN(22.0, MAX(6.0, leftover / 4.0));
    CGFloat extra = MAX(0, leftover - gap * 4.0);
    top += extra * 0.55;                  // 多出来的空间主要给顶部（封面与标题之间）
    bottomPad += extra * 0.45;

    CGFloat y = top;
    self.cover.frame = CGRectMake((W - coverH) / 2, y, coverH, coverH);
    self.coverLabel.frame = self.cover.bounds;
    y = CGRectGetMaxY(self.cover.frame) + gap;

    self.titleLabel.frame = CGRectMake(24, y, W - 24 - 130, 34);
    self.subLabel.frame = CGRectMake(24, y + 38, W - 24 - 130, 24);
    self.starBtn.frame = CGRectMake(W - 24 - 96, y - 4, 44, 44);
    self.moreBtn.frame = CGRectMake(W - 24 - 44, y - 4, 44, 44);
    self.status.frame = CGRectMake(24, y + 64, W - 48, 14);
    y += 70 + gap;

    self.slider.frame = CGRectMake(24, y + 4, W - 48, 28);
    y += 28 + gap;

    self.elapsed.frame = CGRectMake(24, y, 90, 18);
    self.mid.frame = CGRectMake(W / 2 - 60, y, 120, 18);
    self.mid.textAlignment = NSTextAlignmentCenter;
    self.duration.frame = CGRectMake(W - 114, y, 90, 18);
    self.duration.textAlignment = NSTextAlignmentRight;
    y += 30 + gap;

    self.playBtn.frame = CGRectMake(W / 2 - 32, y + 14, 64, 64);
    [self.view viewWithTag:201].frame = CGRectMake(28, y + 26, 34, 34);
    [self.view viewWithTag:202].frame = CGRectMake(W / 2 - 104, y + 24, 38, 38);
    [self.view viewWithTag:203].frame = CGRectMake(W / 2 + 66, y + 24, 38, 38);
    [self.view viewWithTag:204].frame = CGRectMake(W - 62, y + 26, 34, 34);
    y += 80 + lastGap;

    UIView *toolPill = [self.view viewWithTag:900];
    toolPill.frame = CGRectMake(W / 2 - 156, y - 4, 312, 46);
    UIButton *rate = (UIButton *)[self.view viewWithTag:301];
    rate.frame = CGRectMake(W / 2 - 150, y + 2, 58, 36);
    [self.view viewWithTag:302].frame = CGRectMake(W / 2 - 62, y + 2, 44, 36);
    self.routeView.frame = CGRectMake(W / 2 + 18, y + 2, 44, 36);
    self.queueDim.frame = self.view.bounds;
    [self.view viewWithTag:304].frame = CGRectMake(W / 2 + 106, y + 2, 44, 36);

    CGRect qf = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
    self.queue.frame = qf;
    self.queueBar.frame = CGRectMake(16, qf.origin.y - 44, W - 32, 40);
    self.queueBar.hidden = !self.showQueue;
    CGFloat bw = (W - 32) / 4.0;
    CGFloat bx = 0;
    for (UIButton *b in @[self.sortBtn, self.pickBtn, self.selBtn, self.dlBtn]) {
        b.frame = CGRectMake(bx, 0, bw, 40);
        bx += bw;
    }
}

- (void)tintFromCover {
    UIImage *img = self.cover.image;
    if (!img) return;
    NSString *key = [NSString stringWithFormat:@"%p", img];
    if ([objc_getAssociatedObject(self, "tintKey") isEqual:key]) return;
    objc_setAssociatedObject(self, "tintKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIColor *c = [ADLiquid tintFromImage:img];
    if (c) [ADLiquid recolor:self.view with:c];
}

- (void)sync {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t) return;
    self.titleLabel.text = t.title;
    self.subLabel.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    self.status.text = p.statusText ?: @"";
    [ADUtil cover:self.cover url:p.album.cover];
    // 封面保持裁圆角；投影放在它后面单独一层，避免 clipsToBounds 吃掉阴影
    self.cover.layer.cornerCurve = kCACornerCurveContinuous;
    self.cover.layer.cornerRadius = 26;
    self.cover.clipsToBounds = YES;
    UIView *shadow = [self.view viewWithTag:8802];
    if (!shadow) {
        shadow = [UIView new];
        shadow.tag = 8802;
        shadow.userInteractionEnabled = NO;
        shadow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
        shadow.layer.cornerCurve = kCACornerCurveContinuous;
        shadow.layer.cornerRadius = 26;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        shadow.layer.shadowOpacity = 0.6;
        shadow.layer.shadowRadius = 30;
        shadow.layer.shadowOffset = CGSizeMake(0, 18);
        [self.view insertSubview:shadow belowSubview:self.cover];
    }
    shadow.frame = self.cover.frame;
    [ADLiquid breathe:shadow on:p.isPlaying];
    [ADLiquid breathe:self.cover on:p.isPlaying];
    [self tintFromCover];
    if (!self.coverLabel) {
        self.coverLabel = [ADUtil label:@"PingFangSC-Semibold" size:44 color:[UIColor colorWithWhite:1 alpha:0.28]];
        self.coverLabel.textAlignment = NSTextAlignmentCenter;
        self.coverLabel.tag = 8801;
        [self.cover addSubview:self.coverLabel];
    }
    self.coverLabel.text = p.album.title.length ? [p.album.title substringToIndex:1] : @"听";

    double cur = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    double dur = p.player.currentItem ? CMTimeGetSeconds(p.player.currentItem.duration) : 0;
    if (!self.dragging && dur > 0 && !isnan(dur)) {
        self.slider.maximumValue = dur;
        self.slider.value = cur;
    }
    self.elapsed.text = [ADUtil time:cur];
    self.duration.text = (dur > 0 && !isnan(dur)) ? [NSString stringWithFormat:@"-%@", [ADUtil time:dur - cur]] : @"--:--";

    // 中间：码率 / 状态
    NSString *mid = nil;
    if ([[ADDownloader shared] hasLocal:t.trackId]) mid = @"本地缓存";
    if (!mid && p.player.currentItem) {
        AVPlayerItemAccessLog *log = p.player.currentItem.accessLog;
        AVPlayerItemAccessLogEvent *ev = log.events.lastObject;
        if (ev.observedBitrate > 0) mid = [NSString stringWithFormat:@"%.0f kbps", ev.observedBitrate / 1000.0];
    }
    self.mid.text = mid ?: @"在线播放";

    [self.playBtn setImage:[UIImage systemImageNamed:(p.isPlaying ? @"pause.fill" : @"play.fill")
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightMedium]]
                   forState:UIControlStateNormal];
    UIButton *rateBtn = (UIButton *)[self.view viewWithTag:301];
    [rateBtn setTitle:[NSString stringWithFormat:@"%.2gx", p.rate] forState:UIControlStateNormal];
    UIButton *sleepBtn = (UIButton *)[self.view viewWithTag:302];
    if (p.stopAfterChapter) {
        [sleepBtn setTitle:@"" forState:UIControlStateNormal];
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = [NSString stringWithFormat:@"%@ · 本集播完停", self.mid.text ?: @""];
    } else if (p.sleepDeadline > 0) {
        double left = p.sleepDeadline - [NSDate date].timeIntervalSince1970;
        // 开了定时就把按钮直接换成剩余时间（和听见有声一致）
        [sleepBtn setImage:nil forState:UIControlStateNormal];
        [sleepBtn setTitle:[ADUtil time:MAX(0, left)] forState:UIControlStateNormal];
        sleepBtn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        [sleepBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = [NSString stringWithFormat:@"%@ · %@后停", self.mid.text ?: @"", [ADUtil time:left]];
    } else {
        [sleepBtn setTitle:@"" forState:UIControlStateNormal];
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = UIColor.whiteColor;
    }
    BOOL fav = [[ADStore shared] isFavorite:p.album.albumId];
    [self.starBtn setImage:[UIImage systemImageNamed:(fav ? @"star.fill" : @"star") withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    self.starBtn.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    if (self.showQueue) [self.queue reloadData];
}

- (void)toggleFav {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    [[ADStore shared] toggleFavorite:p.album];
    [self sync];
}

- (void)showMore {
    [ADHaptic tap];
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    NSArray *modes = @[@"顺序播放", @"单集循环", @"整本循环"];
    NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:@"ad_playmode"];
    if (mode < 0 || mode > 2) mode = 0;
    NSArray *opts = @[@"从头播放", @"缓存整本到本机", @"打开专辑（排序 / 选集 / 下载）", @"在此处添加书签", @"书签列表",
                      [NSString stringWithFormat:@"播放模式：%@", modes[mode]]];
    [ADOptionSheet showIn:self title:p.album.title options:opts destructive:-1 choose:^(NSInteger i) {
        if (i == 0) { [p playAt:0]; return; }
        if (i == 1) { [[ADDownloader shared] addAlbum:p.album tracks:p.tracks]; return; }
        if (i == 3) { [self addBookmark]; return; }
        if (i == 4) {
            ADBookmarksController *bc = [ADBookmarksController new];
            UINavigationController *bn = [[UINavigationController alloc] initWithRootViewController:bc];
            bn.modalPresentationStyle = UIModalPresentationPageSheet;
            [self presentViewController:bn animated:YES completion:nil];
            return;
        }
        if (i == 5) { [self pickPlayMode]; return; }
        ADAlbum *album = p.album;
        [self dismissViewControllerAnimated:YES completion:^{
            UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
            UINavigationController *nav = nil;
            if ([root isKindOfClass:ADDockController.class]) {
                UIViewController *sel = ((ADDockController *)root).selectedViewController;
                if ([sel isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)sel;
            } else if ([root isKindOfClass:UINavigationController.class]) {
                nav = (UINavigationController *)root;
            }
            if (!nav) return;
            ADAlbumController *vc = [ADAlbumController new];
            vc.album = album;
            [nav pushViewController:vc animated:YES];
        }];
    }];
}

- (void)pickPlayMode {
    NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:@"ad_playmode"];
    NSArray *names = @[@"顺序播放", @"单集循环", @"整本循环"];
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger k = 0; k < 3; k++) [opts addObject:[NSString stringWithFormat:@"%@%@", k == mode ? @"✓ " : @"", names[k]]];
    [ADOptionSheet showIn:self title:@"播放模式" options:opts destructive:-1 choose:^(NSInteger i) {
        [NSUserDefaults.standardUserDefaults setInteger:i forKey:@"ad_playmode"];
        [ADHaptic success];
    }];
}

- (void)addBookmark {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t || !p.album) return;
    double sec = p.player ? CMTimeGetSeconds(p.player.currentTime) : 0;
    if (isnan(sec) || sec < 0) sec = 0;
    NSString *msg = [NSString stringWithFormat:@"%@ · %@", t.title ?: @"", [ADUtil time:sec]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加书签" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"备注（可不填）"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADStore shared] addBookmark:@{
            @"albumId": p.album.albumId ?: @"", @"albumTitle": p.album.title ?: @"",
            @"cover": p.album.cover ?: @"", @"provider": p.album.provider ?: @"", @"anchor": p.album.anchor ?: @"",
            @"trackId": t.trackId ?: @"", @"trackTitle": t.title ?: @"",
            @"index": @(p.index), @"seconds": @(sec),
            @"note": [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
            @"ts": @([NSDate date].timeIntervalSince1970)}];
        [ADHaptic success];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // 播放页收起后让迷你条立刻回来
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADPlayerChanged" object:nil];
}

- (void)showRateMenu {
    [ADHaptic tap];
    NSArray *rates = @[@0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    NSMutableArray *opts = [NSMutableArray array];
    NSInteger cur = 0;
    for (NSInteger i = 0; i < (NSInteger)rates.count; i++) {
        double v = [rates[i] doubleValue];
        [opts addObject:[NSString stringWithFormat:@"%@%@", v == 1.0 ? @"正常 1x" : [NSString stringWithFormat:@"%gx", v],
                         fabs(v - ADPlayer.shared.rate) < 0.001 ? @"  ✓" : @""]];
        if (fabs(v - ADPlayer.shared.rate) < 0.001) cur = i;
    }
    [ADOptionSheet showIn:self title:@"播放速度" options:opts destructive:-1 choose:^(NSInteger i) {
        ADPlayer.shared.rate = [rates[i] doubleValue];
        [self sync];
    }];
}

- (void)showSleepMenu {
    [ADHaptic tap];
    ADPlayer *pl = ADPlayer.shared;
    BOOL active = (pl.sleepDeadline > 0 || pl.stopAfterChapter);
    NSMutableArray *opts = [NSMutableArray arrayWithObjects:@"15 分钟", @"30 分钟", @"45 分钟", @"60 分钟", @"90 分钟", @"自定义时长…",
                            pl.stopAfterChapter ? @"✓ 播完本集后停止" : @"播完本集后停止", nil];
    NSInteger n = opts.count;
    if (active) [opts addObject:@"取消定时关闭"];
    double now = [NSDate date].timeIntervalSince1970;
    NSArray *mins = @[@15, @30, @45, @60, @90];
    [ADOptionSheet showIn:self title:@"定时关闭" options:opts
              destructive:(active ? n : -1)
                   choose:^(NSInteger i) {
        if (i < 5) {
            ADPlayer.shared.stopAfterChapter = NO;
            ADPlayer.shared.sleepDeadline = now + [mins[i] doubleValue] * 60;
            [self sync];
        } else if (i == 5) {
            [self askCustomSleep];
        } else if (i == 6) {
            ADPlayer.shared.sleepDeadline = 0;
            ADPlayer.shared.stopAfterChapter = !ADPlayer.shared.stopAfterChapter;
            [self sync];
        } else {
            ADPlayer.shared.sleepDeadline = 0;
            ADPlayer.shared.stopAfterChapter = NO;
            [self sync];
        }
    }];
}

- (void)askCustomSleep {
    UIAlertController *c = [UIAlertController alertControllerWithTitle:@"自定义定时" message:@"输入分钟数，也可写 1h30m、90s" preferredStyle:UIAlertControllerStyleAlert];
    [c addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDefault;
        tf.placeholder = @"例如 20";
    }];
    [c addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *y) {
        double sec = [ADUtil parseDuration:c.textFields.firstObject.text];
        if (sec <= 0) return;
        ADPlayer.shared.sleepDeadline = [NSDate date].timeIntervalSince1970 + sec;
        [self sync];
    }]];
    [c addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:c animated:YES completion:nil];
}

- (void)showQueueList {
    ADPlayer *p = ADPlayer.shared;
    if (!p.tracks.count) return;
    [self openQueue];
}

- (void)sliderBegin { self.dragging = YES; }
- (void)sliderMoving { self.elapsed.text = [ADUtil time:self.slider.value]; }
- (void)sliderEnd { self.dragging = NO; [ADHaptic soft]; [ADPlayer.shared seekTo:self.slider.value]; }
- (void)toggle { [ADHaptic tap]; [ADPlayer.shared toggle]; [self sync]; }
- (void)prev { [ADHaptic tap]; [ADPlayer.shared prev]; [self sync]; }
- (void)next { [ADHaptic tap]; [ADPlayer.shared next]; [self sync]; }
- (void)back15 { [ADHaptic tap]; [ADPlayer.shared seekBy:-15]; }
- (void)fwd15 { [ADHaptic tap]; [ADPlayer.shared seekBy:15]; }

- (void)cycleRateUnused {
    NSArray *rates = @[@0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    float cur = ADPlayer.shared.rate;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"播放速度" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in rates) {
        BOOL on = fabs([n floatValue] - cur) < 0.001;
        NSString *t = [NSString stringWithFormat:@"%@%@x", on ? @"✓ " : @"", n];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.rate = [n floatValue];
            [self sync];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = [self.view viewWithTag:301];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cycleSleepUnused {
    NSArray *mins = @[@0, @15, @30, @45, @60, @90];
    double now = [NSDate date].timeIntervalSince1970;
    double left = ADPlayer.shared.sleepDeadline > 0 ? (ADPlayer.shared.sleepDeadline - now) / 60.0 : 0;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"睡眠定时" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (ADPlayer.shared.stopAfterChapter) {
        [a addAction:[UIAlertAction actionWithTitle:@"✓ 本集播完停止" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = NO;
            [self sync];
        }]];
    } else {
        [a addAction:[UIAlertAction actionWithTitle:@"本集播完停止" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = YES;
            ADPlayer.shared.sleepDeadline = 0;
            [self sync];
        }]];
    }
    for (NSNumber *n in mins) {
        double m = [n doubleValue];
        BOOL on = (m == 0) ? (ADPlayer.shared.sleepDeadline <= 0 && !ADPlayer.shared.stopAfterChapter) : (fabs(left - m) < 1.5);
        NSString *t = m == 0 ? [NSString stringWithFormat:@"%@关闭定时", on ? @"✓ " : @""]
                             : [NSString stringWithFormat:@"%@%ld 分钟", on ? @"✓ " : @"", (long)m];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            ADPlayer.shared.stopAfterChapter = NO;
            ADPlayer.shared.sleepDeadline = m > 0 ? [NSDate date].timeIntervalSince1970 + m * 60 : 0;
            [self sync];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.sleepBtn;
    [self presentViewController:a animated:YES completion:nil];
}

- (UIButton *)barButton:(NSString *)t action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.9] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (NSInteger)queueRowForIndex:(NSInteger)idx {
    NSInteger n = ADPlayer.shared.tracks.count;
    if (n <= 0) return 0;
    if (idx >= n) idx = n - 1;
    return self.queueDesc ? (n - 1 - idx) : idx;
}

- (NSInteger)queueIndexForRow:(NSInteger)row {
    NSInteger n = ADPlayer.shared.tracks.count;
    if (n <= 0) return 0;
    return self.queueDesc ? (n - 1 - row) : row;
}

- (void)toggleQueueSort {
    self.queueDesc = !self.queueDesc;
    [self.sortBtn setTitle:(self.queueDesc ? @"倒序" : @"正序") forState:UIControlStateNormal];
    [self.queue reloadData];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:[self queueRowForIndex:ADPlayer.shared.index] inSection:0];
    if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
        [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (void)showQueuePicker {
    NSInteger total = ADPlayer.shared.tracks.count;
    if (!total) return;
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger start = 0; start < total; start += 60) {
        NSInteger end = MIN(start + 60, total);
        [opts addObject:[NSString stringWithFormat:@"%ld–%ld", (long)start + 1, (long)end]];
    }
    [ADOptionSheet showIn:self title:@"快速选集" options:opts destructive:-1 choose:^(NSInteger i) {
        NSInteger target = MIN(i * 60, MAX(0, (NSInteger)ADPlayer.shared.tracks.count - 1));
        NSIndexPath *ip = [NSIndexPath indexPathForRow:[self queueRowForIndex:target] inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
            [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }];
}

- (void)toggleQueueSelect {
    self.queueSelecting = !self.queueSelecting;
    if (!self.queueSelecting) [self.queueSel removeAllObjects];
    [self.selBtn setTitle:(self.queueSelecting ? @"取消多选" : @"多选") forState:UIControlStateNormal];
    [self updateQueueDl];
    [self.queue reloadData];
}

- (void)updateQueueDl {
    if (self.queueSelecting) {
        [self.dlBtn setTitle:[NSString stringWithFormat:@"缓存所选(%ld)", (long)self.queueSel.count] forState:UIControlStateNormal];
    } else {
        [self.dlBtn setTitle:@"缓存整本" forState:UIControlStateNormal];
    }
}

- (void)queueDownload {
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    if (self.queueSelecting) {
        if (!self.queueSel.count) return;
        NSMutableArray *arr = [NSMutableArray array];
        for (ADTrack *t in p.tracks) if ([self.queueSel containsObject:t.trackId]) [arr addObject:t];
        [[ADDownloader shared] addTracks:p.album tracks:arr];
        self.queueSelecting = NO;
        [self.queueSel removeAllObjects];
        [self.selBtn setTitle:@"多选" forState:UIControlStateNormal];
        [self updateQueueDl];
        [self.queue reloadData];
        UIImpactFeedbackGenerator *g = [UIImpactFeedbackGenerator new];
        [g impactOccurred];
        return;
    }
    [[ADDownloader shared] addAlbum:p.album tracks:p.tracks];
    UIImpactFeedbackGenerator *g = [UIImpactFeedbackGenerator new];
    [g impactOccurred];
}

- (void)closeQueue {
    if (!self.showQueue) return;
    self.showQueue = NO;
    self.queueDim.hidden = YES;
    [UIView animateWithDuration:0.22 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        self.queue.frame = CGRectMake(16, H, W - 32, 300);
        self.queueBar.frame = CGRectMake(16, H, W - 32, 40);
        self.queueBar.alpha = 0;
    } completion:^(BOOL ok) {
        self.queue.hidden = YES;
        self.queueBar.hidden = YES;
        self.queueBar.alpha = 1;
    }];
}

- (void)openQueue {
    self.showQueue = !self.showQueue;
    self.queue.hidden = !self.showQueue;
    self.queueDim.hidden = !self.showQueue;
    self.queueBar.hidden = !self.showQueue;
    if (self.showQueue) { self.queueSelecting = NO; [self.queueSel removeAllObjects]; [self.selBtn setTitle:@"多选" forState:UIControlStateNormal]; [self updateQueueDl]; }
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        CGRect qf = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
        self.queue.frame = qf;
        self.queueBar.frame = CGRectMake(16, qf.origin.y - 44, W - 32, 40);
    }];
    [self.queue reloadData];
    if (self.showQueue) {
        [ADPlayer.shared ensureFullQueue];      // 打开队列时顺手把后面的目录补齐
        NSIndexPath *ip = [NSIndexPath indexPathForRow:[self queueRowForIndex:ADPlayer.shared.index] inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
            [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return ADPlayer.shared.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"q";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    NSInteger idx = [self queueIndexForRow:ip.row];
    ADTrack *tr = ADPlayer.shared.tracks[idx];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    BOOL done = [[ADStore shared] isDone:tr.trackId];
    c.textLabel.text = done ? [NSString stringWithFormat:@"✓ %@", tr.title] : tr.title;
    c.textLabel.textColor = (idx == ADPlayer.shared.index) ? [ADUtil brand]
                          : (done ? [UIColor colorWithWhite:1 alpha:0.55] : UIColor.whiteColor);
    if (self.queueSelecting) {
        c.accessoryType = [self.queueSel containsObject:tr.trackId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        c.tintColor = [ADUtil brand];
    } else {
        c.accessoryType = UITableViewCellAccessoryNone;
    }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger idx = [self queueIndexForRow:ip.row];
    if (self.queueSelecting) {
        ADTrack *tr = ADPlayer.shared.tracks[idx];
        if ([self.queueSel containsObject:tr.trackId]) [self.queueSel removeObject:tr.trackId];
        else [self.queueSel addObject:tr.trackId];
        [self updateQueueDl];
        [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    [ADPlayer.shared playAt:idx];
    [self closeQueue];
    [self sync];
}
@end

// ───────────── 设置 ─────────────
@interface ADSettingsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL tokenShown;
@end

@implementation ADSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.title = @"设置";
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.token = [ADConfig shared].token ?: @"";

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    self.baseField = [self field:[ADConfig shared].baseURL placeholder:@"https://服务器地址:端口" keyboard:UIKeyboardTypeURL];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeSelf)];

    self.status = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADDownloadChanged" object:nil];
}

- (void)closeSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)prefetchSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_prefetch"];
    if (sw.on) [ADPlayer.shared prefetchAhead];
}

- (void)prefetchWifi:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_prefetch_wifi"];
}

- (void)hapticSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_haptic"];
    if (sw.on) [ADHaptic tap];
}

- (void)soundSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_sound"];
    if (sw.on) [ADHaptic tap];
}

- (void)prefetchStepper:(UIStepper *)st {
    [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)st.value forKey:@"ad_prefetch_count"];
    [self.table reloadData];
}

- (void)refresh { [self.table reloadData]; }

- (UITextField *)field:(NSString *)text placeholder:(NSString *)ph keyboard:(UIKeyboardType)kb {
    UITextField *f = [UITextField new];
    f.text = text;
    f.placeholder = ph;
    f.textColor = UIColor.whiteColor;
    f.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.keyboardType = kb;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.textAlignment = NSTextAlignmentRight;
    f.delegate = self;
    return f;
}

// token 显示：默认只露出前后各 3 位，其余用圆点
- (NSString *)tokenDisplay {
    if (!self.token.length) return @"未填写";
    if (self.tokenShown) return self.token;
    if (self.token.length <= 10) return @"••••••••";
    return [NSString stringWithFormat:@"%@••••••%@", [self.token substringToIndex:5], [self.token substringFromIndex:self.token.length - 4]];
}

- (void)toggleToken {
    self.tokenShown = !self.tokenShown;
    [self.table reloadData];
}

- (void)editToken {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Token" message:@"粘贴服务端给你的 token" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.token;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        tf.placeholder = @"xmd_…";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.token = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [self save];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"从剪贴板粘贴" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *p = UIPasteboard.generalPasteboard.string;
        if (p.length) { self.token = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; [self save]; }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editAccount {
    ADConfig *cfg = [ADConfig shared];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"网页账号"
                                                               message:@"填服务端网页后台的账号密码。VIP/付费专辑的目录只有登录态才取得到。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cfg.username;
        tf.placeholder = @"用户名";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cfg.password;
        tf.placeholder = @"密码";
        tf.secureTextEntry = YES;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存并登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        cfg.username = [a.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        cfg.password = a.textFields[1].text ?: @"";
        [cfg save];
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] removeCookiesSinceDate:[NSDate dateWithTimeIntervalSince1970:0]];
        [[ADApi shared] panelLogin:^(BOOL ok, NSString *err) {
            UIAlertController *r = [UIAlertController alertControllerWithTitle:(ok ? @"登录成功" : @"登录失败")
                                                                      message:(ok ? @"现在可以读取 VIP 专辑的目录了" : (err ?: @"请检查账号密码"))
                                                               preferredStyle:UIAlertControllerStyleAlert];
            [r addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:r animated:YES completion:nil];
            [self.table reloadData];
        }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)save {
    [ADHaptic success];
    [ADConfig shared].baseURL = self.baseField.text ?: @"";
    [ADConfig shared].token = self.token ?: @"";
    [[ADConfig shared] save];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    [self.table reloadData];
    [self test];
}

- (void)test {
    self.status.text = @"正在测试连接…";
    [self.table reloadData];
    __weak typeof(self) w = self;
    [[ADApi shared] albumDetail:@"XMID59325711" done:^(ADAlbum *a, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.status.text = err ? [@"连接失败：" stringByAppendingString:err] : @"连接正常，可以搜索和播放";
        [self.table reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"服务";
    if (s == 2) return @"播放与预加载";
    if (s == 3) return @"数据";
    return @"本机下载";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return self.status.text ?: @"点 Token 那一行可以粘贴或修改";
    if (s == 3) return @"备份文件在「文件」App → 听书 → backups，重装前先备份";
    if (![ADDownloader shared].tasks.count)
        return @"在专辑页点「缓存到本机」，音频会存进手机，离线也能听";
    return @"左滑删除或暂停，点击行可暂停/继续；本机下载不占用服务器";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == 2) return 6;
    if (s == 3) return 3;
    return MAX(1, (NSInteger)[ADDownloader shared].tasks.count) + 1;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.selectionStyle = UITableViewCellSelectionStyleNone;

    if (ip.section == 3) {
        NSArray *t1 = @[@"书签", @"离线存储管理", @"备份与恢复"];
        NSArray *t2 = @[@"收藏的听书位置", @"查看占用、清理缓存、重试失败下载", @"导出 / 导入收藏、进度、听完标记"];
        c.textLabel.text = t1[ip.row]; c.detailTextLabel.text = t2[ip.row];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        return c;
    }
    if (ip.section == 2) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        if (ip.row == 0) {
            c.textLabel.text = @"智能预缓存";
            c.detailTextLabel.text = @"提前准备后续音频，弱网和地铁里更顺";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [ud boolForKey:@"ad_prefetch"];
            sw.onTintColor = [ADUtil brand];
            [sw addTarget:self action:@selector(prefetchSwitch:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else if (ip.row == 1) {
            c.textLabel.text = @"仅 Wi-Fi 预加载";
            c.detailTextLabel.text = @"关掉后用蜂窝网络也会预取，会走流量";
            UISwitch *wifiSw = [[UISwitch alloc] init];
            wifiSw.on = [ud boolForKey:@"ad_prefetch_wifi"];
            wifiSw.onTintColor = [ADUtil brand];
            [wifiSw addTarget:self action:@selector(prefetchWifi:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = wifiSw;
        } else if (ip.row == 2) {
            c.textLabel.text = @"额外预加载后续集数";
            NSInteger n = [ud integerForKey:@"ad_prefetch_count"];
            if (n <= 0) n = 2;
            c.detailTextLabel.text = [NSString stringWithFormat:@"当前 %ld 集（1–5），越大越占流量", (long)n];
            UIStepper *st = [[UIStepper alloc] init];
            st.minimumValue = 1; st.maximumValue = 5; st.stepValue = 1;
            st.value = n;
            st.tintColor = [ADUtil brand];
            [st addTarget:self action:@selector(prefetchStepper:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = st;
        } else if (ip.row == 4) {
            c.textLabel.text = @"触控反馈";
            c.detailTextLabel.text = @"按钮、卡片、长按都有轻微震动";
            UISwitch *sw = [[UISwitch alloc] init];
            id hv = [ud objectForKey:@"ad_haptic"];
            sw.on = hv ? [ud boolForKey:@"ad_haptic"] : YES;
            sw.onTintColor = [ADUtil brand];
            [sw addTarget:self action:@selector(hapticSwitch:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else if (ip.row == 5) {
            c.textLabel.text = @"提示音";
            c.detailTextLabel.text = @"点按和选择时播放系统提示音";
            UISwitch *sw = [[UISwitch alloc] init];
            id sv = [ud objectForKey:@"ad_sound"];
            sw.on = sv ? [ud boolForKey:@"ad_sound"] : YES;
            sw.onTintColor = [ADUtil brand];
            [sw addTarget:self action:@selector(soundSwitch:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else if (ip.row == 3) {
            NSInteger days = [ud integerForKey:@"ad_prefetch_days"];
            if (days < 0) days = 3;
            c.textLabel.text = @"自动清理预缓存";
            c.detailTextLabel.text = days == 0 ? @"不自动清理" : [NSString stringWithFormat:@"超过 %ld 天的临时音频自动删除", (long)days];
            c.textLabel.textColor = UIColor.whiteColor;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return c;
    }

    if (ip.section == 0) {
        if (ip.row == 0) {
            UILabel *name = [ADUtil label:nil size:15 color:UIColor.whiteColor];
            name.text = @"服务地址";
            name.frame = CGRectMake(16, 12, 76, 20);
            [c.contentView addSubview:name];
            CGFloat cw = c.contentView.bounds.size.width > 0 ? c.contentView.bounds.size.width : (t.bounds.size.width - 40);
            self.baseField.frame = CGRectMake(86, 6, MAX(80, cw - 86 - 34), 32);
            self.baseField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [c.contentView addSubview:self.baseField];
        } else if (ip.row == 1) {
            UILabel *name = [ADUtil label:nil size:15 color:UIColor.whiteColor];
            name.text = @"Token";
            name.frame = CGRectMake(16, 12, 60, 20);
            [c.contentView addSubview:name];

            UILabel *v = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.85]];
            v.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            v.textAlignment = NSTextAlignmentRight;
            v.lineBreakMode = NSLineBreakByTruncatingMiddle;
            v.text = [self tokenDisplay];
            v.frame = CGRectMake(80, 0, c.contentView.bounds.size.width - 80 - 44, 44);
            v.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [c.contentView addSubview:v];

            UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
            eye.frame = CGRectMake(c.contentView.bounds.size.width - 40, 2, 34, 40);
            eye.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            eye.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
            [eye setImage:[UIImage systemImageNamed:self.tokenShown ? @"eye" : @"eye.slash"] forState:UIControlStateNormal];
            [eye addTarget:self action:@selector(toggleToken) forControlEvents:UIControlEventTouchUpInside];
            [c.contentView addSubview:eye];
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (ip.row == 2) {
            c.textLabel.text = @"网页账号";
            ADConfig *cfg = [ADConfig shared];
            if (cfg.username.length) {
                c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 用于读取 VIP 专辑目录", cfg.username];
                c.textLabel.textColor = UIColor.whiteColor;
            } else {
                c.detailTextLabel.text = @"可选：填了才能取 VIP/付费专辑的目录";
                c.textLabel.textColor = UIColor.whiteColor;
            }
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            c.textLabel.text = @"测试连接";
            c.textLabel.textColor = [ADUtil brand];
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return c;
    }

    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.row == 0) {
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        c.textLabel.text = anyRunning ? @"全部暂停" : @"全部继续";
        c.textLabel.textColor = [ADUtil brand];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (!tasks.count) {
        c.textLabel.text = @"暂无本机下载";
        c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    } else {
        ADTask *task = tasks[ip.row - 1];
        c.textLabel.text = task.title.length ? task.title : task.albumId;
        NSString *st = task.state == ADTaskStateRunning ? @"下载中"
                     : (task.state == ADTaskStatePaused ? @"已暂停"
                     : (task.state == ADTaskStateDone ? @"已完成"
                     : (task.state == ADTaskStateFailed ? @"有失败" : @"排队中")));
        NSString *bytes = task.bytes > 0 ? [NSString stringWithFormat:@" · %.1fMB", task.bytes / 1048576.0] : @"";
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld/%ld%@", st, (long)task.done, (long)task.tracks.count, bytes];
    }
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 3) {
        UIViewController *vc = ip.row == 0 ? [ADBookmarksController new] : (ip.row == 1 ? [ADStorageController new] : [ADBackupController new]);
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if (ip.section == 2) {
        if (ip.row == 3) {
            [ADOptionSheet showIn:self title:@"自动清理预缓存" options:@[@"不清理", @"3 天", @"7 天", @"30 天"] destructive:-1 choose:^(NSInteger i2) {
                NSArray *v = @[@0, @3, @7, @30];
                [NSUserDefaults.standardUserDefaults setInteger:[v[i2] integerValue] forKey:@"ad_prefetch_days"];
                [ADPlayer.shared cleanPrefetch];
                [self.table reloadData];
            }];
        }
        return;
    }
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        if (ip.row == 0) [self.baseField becomeFirstResponder];
        else if (ip.row == 1) [self editToken];
        else if (ip.row == 2) [self editAccount];
        else [self save];
        return;
    }
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.row == 0) {
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        if (anyRunning) [[ADDownloader shared] pauseAll]; else [[ADDownloader shared] resumeAll];
        [t reloadData];
        return;
    }
    if (tasks.count) {
        ADTask *task = tasks[ip.row - 1];
        if (task.state == ADTaskStateRunning || task.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:task];
        else [[ADDownloader shared] resumeTask:task];
        [t reloadData];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1 || ip.row == 0) return nil;
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if ((NSInteger)ip.row - 1 >= (NSInteger)tasks.count) return nil;
    ADTask *task = tasks[ip.row - 1];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        UIAlertController *q = [UIAlertController alertControllerWithTitle:@"删除下载" message:@"音频文件会一起删掉" preferredStyle:UIAlertControllerStyleAlert];
        [q addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
        [q addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [[ADDownloader shared] deleteTask:task];
            [t reloadData];
            done(YES);
        }]];
        [self presentViewController:q animated:YES completion:nil];
    }];
    UIContextualAction *pause = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:(task.state == ADTaskStateRunning ? @"暂停" : @"继续") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        if (task.state == ADTaskStateRunning || task.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:task];
        else [[ADDownloader shared] resumeTask:task];
        [t reloadData];
        done(YES);
    }];
    pause.backgroundColor = [ADUtil brand];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, pause]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self save]; return YES; }
@end
