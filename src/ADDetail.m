#import "AD.h"
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
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, assign) NSInteger jumpTarget;
@property (nonatomic, assign) BOOL hasMore;
@end

@implementation ADAlbumController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.title = @"专辑";
    self.tracks = [NSMutableArray array];
    self.page = 1;
    self.total = self.album.trackCount;

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
    self.table.refreshControl = [[UIRefreshControl alloc] init];
    self.table.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.table.refreshControl addTarget:self action:@selector(refreshAll) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.table];

    CGFloat w = self.view.bounds.size.width;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0)];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 110, 110)];
    self.cover.layer.cornerRadius = 10;
    self.cover.clipsToBounds = YES;
    self.titleLabel = [ADUtil label:@"PingFangSC-Semibold" size:17 color:UIColor.whiteColor];
    self.titleLabel.frame = CGRectMake(140, 16, w - 156, 46);
    self.meta = [ADUtil label:nil size:12 color:[ADUtil dim]];
    self.meta.frame = CGRectMake(140, 64, w - 156, 20);
    self.intro = [ADUtil label:nil size:12 color:[ADUtil dim]];
    self.intro.frame = CGRectMake(16, 170, w - 32, 0);
    self.dlBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dlBtn.frame = CGRectMake(140, 92, 130, 30);
    self.dlBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.dlBtn.layer.cornerRadius = 15;
    [self.dlBtn setTitle:@"缓存到本机" forState:UIControlStateNormal];
    [self.dlBtn setTitleColor:[ADUtil brand] forState:UIControlStateNormal];
    self.dlBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.dlBtn addTarget:self action:@selector(downloadAll) forControlEvents:UIControlEventTouchUpInside];
    [head addSubview:self.dlBtn];
    [head addSubview:self.cover];
    [head addSubview:self.titleLabel];
    [head addSubview:self.meta];
    [head addSubview:self.intro];
    self.table.tableHeaderView = head;

    self.selected = [NSMutableSet set];
    self.jumpTarget = -1;
    self.favBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleFav)];
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showAlbumMenu)];
    self.navigationItem.rightBarButtonItems = @[moreItem, self.favBtn];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fillHeader) name:@"ADDownloadChanged" object:nil];
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = NO;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
}

- (void)fillHeader {
    [ADUtil cover:self.cover url:self.album.cover];
    self.titleLabel.text = self.album.title;
    NSMutableArray *bits = [NSMutableArray array];
    if (self.album.anchor.length) [bits addObject:self.album.anchor];
    if (self.total) [bits addObject:[NSString stringWithFormat:@"%ld 集", (long)self.total]];
    if (self.album.playCount > 0) [bits addObject:[NSString stringWithFormat:@"%@播放", [ADUtil count:self.album.playCount]]];
    [bits addObject:self.album.provider.length ? self.album.provider : @"xm"];
    self.meta.text = [bits componentsJoinedByString:@" · "];

    CGFloat w = self.view.bounds.size.width;
    self.intro.text = self.album.intro.length > 200 ? [[self.album.intro substringToIndex:200] stringByAppendingString:@"…"] : self.album.intro;
    CGSize sz = [self.intro sizeThatFits:CGSizeMake(w - 32, 400)];
    self.intro.frame = CGRectMake(16, 170, w - 32, sz.height);
    UIView *head = self.table.tableHeaderView;
    CGFloat h = 170 + sz.height + 12;
    head.frame = CGRectMake(0, 0, w, h);
    self.table.tableHeaderView = head;

    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (task) {
        NSString *t2 = task.state == ADTaskStateDone ? @"已缓存"
                    : (task.state == ADTaskStatePaused ? [NSString stringWithFormat:@"已暂停 %ld/%ld", (long)task.done, (long)task.tracks.count]
                    : [NSString stringWithFormat:@"缓存中 %ld/%ld", (long)task.done, (long)task.tracks.count]);
        [self.dlBtn setTitle:t2 forState:UIControlStateNormal];
    } else {
        [self.dlBtn setTitle:@"缓存到本机" forState:UIControlStateNormal];
    }
    BOOL fav = [[ADStore shared] isFavorite:self.album.albumId];
    [self.favBtn setImage:[UIImage systemImageNamed:fav ? @"heart.fill" : @"heart"]];
    self.favBtn.tintColor = fav ? [ADUtil brand] : UIColor.whiteColor;
    [self buildRangeBar];
}

- (NSArray<ADTrack *> *)ordered {
    if (!self.sortDesc) return self.tracks;
    return [[self.tracks reverseObjectEnumerator] allObjects];
}

- (void)showAlbumMenu {
    [ADOptionSheet showIn:self title:self.album.title options:@[@"选择剧集下载", @"目录正序", @"目录倒序", @"缓存整本到本机", @"刷新目录"] destructive:-1 choose:^(NSInteger i) {
        if (i == 0) [self beginSelecting];
        else if (i == 1) { self.sortDesc = NO; [self.table reloadData]; }
        else if (i == 2) { self.sortDesc = YES; [self.table reloadData]; }
        else if (i == 3) [self downloadAll];
        else [self refreshAll];
    }];
}

- (void)buildRangeBar {
    if (!self.rangeBar) {
        self.rangeBar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        self.rangeBar.showsHorizontalScrollIndicator = NO;
        self.rangeBar.contentInset = UIEdgeInsetsMake(0, 16, 0, 16);
    }
    for (UIView *v in self.rangeBar.subviews) [v removeFromSuperview];
    NSInteger total = self.total > 0 ? self.total : self.tracks.count;
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
    if (self.rangeBar.superview != head) [head addSubview:self.rangeBar];
    self.rangeBar.frame = CGRectMake(0, head.bounds.size.height - 44, self.view.bounds.size.width, 44);
}

- (void)tapRange:(UIButton *)b {
    NSInteger start = b.tag - 2000;
    for (UIView *v in self.rangeBar.subviews) {
        v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    }
    b.backgroundColor = [UIColor whiteColor];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self jumpTo:start];
}

- (void)jumpTo:(NSInteger)idx {
    if (idx < (NSInteger)self.tracks.count) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
        [self.table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
        return;
    }
    if (!self.hasMore) return;
    self.jumpTarget = idx;
    [self loadTracks];
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
    self.actionBar.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.98];
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
    [[ADDownloader shared] addTracks:self.album tracks:@[t]];
    [self fillHeader];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

- (void)refreshAll {
    self.page = 1;
    self.hasMore = YES;
    [self.tracks removeAllObjects];
    [self.table reloadData];
    [self loadTracks];
    [self.table.refreshControl endRefreshing];
}

- (void)downloadAll {
    ADTask *task = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (task && task.state == ADTaskStateRunning) { [[ADDownloader shared] pauseTask:task]; [self fillHeader]; return; }
    if (task && task.state == ADTaskStatePaused) { [[ADDownloader shared] resumeTask:task]; [self fillHeader]; return; }
    if (!self.tracks.count) return;
    [[ADDownloader shared] addAlbum:self.album tracks:self.tracks];
    [self fillHeader];
}

- (void)toggleFav {
    [[ADStore shared] toggleFavorite:self.album];
    [self fillHeader];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

- (void)loadTracks {
    if (self.loading) return;
    self.loading = YES;
    __weak typeof(self) weakSelf = self;
    [[ADApi shared] tracksOf:self.album.albumId page:self.page done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.loading = NO;
        BOOL empty = (list.count == 0 && self.page == 1);
        if (err || empty) {
            if (self.retries < 2) {
                self.retries += 1;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self loadTracks];
                });
            } else {
                self.errText = err.length ? err : @"播放目录没取到";
            }
            [self.table reloadData];
            [self updateFooter];
            return;
        }
        self.retries = 0;
        self.errText = nil;
        [self updateFooter];
        if (total > 0) self.total = total;
        if (list.count) [self.tracks addObjectsFromArray:list];
        if (list.count) self.page += 1;
        self.hasMore = list.count > 0 && (NSInteger)self.tracks.count < MAX(self.total, 1);
        [self.table reloadData];
        [self fillHeader];
        if (self.jumpTarget >= 0 && (NSInteger)self.tracks.count > self.jumpTarget) {
            NSIndexPath *ip = [NSIndexPath indexPathForRow:self.jumpTarget inSection:0];
            self.jumpTarget = -1;
            [self.table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:YES];
        }
        // 自动恢复上次进度
        if (self.tracks.count && !ADPlayer.shared.album) {
            ADPlayer.shared.album = self.album;
            ADPlayer.shared.tracks = self.tracks;
        }
    }];
}

- (void)updateFooter {
    if (self.errText.length && self.tracks.count == 0) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(0, 0, self.view.bounds.size.width, 120);
        b.titleLabel.numberOfLines = 0;
        b.titleLabel.textAlignment = NSTextAlignmentCenter;
        b.titleLabel.font = [UIFont systemFontOfSize:14];
        [b setTitle:[NSString stringWithFormat:@"%@\n点这里重试", self.errText] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.55] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(retryTracks) forControlEvents:UIControlEventTouchUpInside];
        self.table.tableFooterView = b;
    } else {
        self.table.tableFooterView = [UIView new];
    }
}

- (void)retryTracks {
    self.retries = 0;
    self.errText = nil;
    [self.table reloadData];
    [self loadTracks];
}

- (void)playFrom:(NSInteger)index {
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
    return self.tracks.count ? [NSString stringWithFormat:@"共 %ld 集", (long)MAX(self.total, (NSInteger)self.tracks.count)] : @"";
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)v;
    h.textLabel.textColor = [ADUtil dim];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.tracks.count; }
- (NSArray<UITableViewRowAction *> *)legacyActions { return nil; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"tr";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    ADTrack *tr = [self ordered][ip.row];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [ADUtil dim];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.textLabel.text = tr.title;
    double pos = [[ADStore shared] positionFor:tr.trackId];
    if ([[ADDownloader shared] hasLocal:tr.trackId]) {
        c.detailTextLabel.text = @"已缓存 · 离线可听";
        c.detailTextLabel.textColor = [ADUtil brand];
    } else
    c.detailTextLabel.text = pos > 0
        ? [NSString stringWithFormat:@"听到 %@ / %@", [ADUtil time:pos], [ADUtil time:tr.duration]]
        : (tr.duration > 0 ? [ADUtil time:tr.duration] : @"");
    ADTrack *cur = ADPlayer.shared.current;
    BOOL playing = cur && [cur.trackId isEqualToString:tr.trackId];
    c.textLabel.textColor = playing ? [ADUtil brand] : UIColor.whiteColor;
    // 触底加载
    if (!self.selecting && ip.row == (NSInteger)self.tracks.count - 3 && self.tracks.count < self.total) [self loadTracks];
    if (self.selecting) {
        BOOL on = [self.selected containsObject:tr.trackId];
        c.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        c.tintColor = [ADUtil brand];
    } else {
        c.accessoryType = UITableViewCellAccessoryNone;
    }
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

    self.routeView = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 44, 36)];
    self.routeView.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    self.routeView.activeTintColor = [ADUtil brand];
    self.routeView.prioritizesVideoDevices = NO;
    [self.view addSubview:self.routeView];

    self.queue = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
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
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    b.layer.cornerRadius = 22;
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

    UIButton *rate = (UIButton *)[self.view viewWithTag:301];
    rate.frame = CGRectMake(W / 2 - 150, y + 2, 58, 36);
    [self.view viewWithTag:302].frame = CGRectMake(W / 2 - 62, y + 2, 44, 36);
    self.routeView.frame = CGRectMake(W / 2 + 18, y + 2, 44, 36);
    self.queueDim.frame = self.view.bounds;
    [self.view viewWithTag:304].frame = CGRectMake(W / 2 + 106, y + 2, 44, 36);

    if (self.showQueue) {
        self.queue.frame = CGRectMake(16, H - 320, W - 32, 300);
    } else {
        self.queue.frame = CGRectMake(16, H, W - 32, 300);
    }
}

- (void)sync {
    ADPlayer *p = ADPlayer.shared;
    ADTrack *t = p.current;
    if (!t) return;
    self.titleLabel.text = t.title;
    self.subLabel.text = p.album.anchor.length ? p.album.anchor : (p.album.title ?: @"");
    self.status.text = p.statusText ?: @"";
    [ADUtil cover:self.cover url:p.album.cover];
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
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = [NSString stringWithFormat:@"%@ · 本集播完停", self.mid.text ?: @""];
    } else if (p.sleepDeadline > 0) {
        double left = p.sleepDeadline - [NSDate date].timeIntervalSince1970;
        [sleepBtn setImage:[UIImage systemImageNamed:@"moon.zzz.fill"] forState:UIControlStateNormal];
        sleepBtn.tintColor = [ADUtil brand];
        self.mid.text = [NSString stringWithFormat:@"%@ · %@后停", self.mid.text ?: @"", [ADUtil time:left]];
    } else {
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
    ADPlayer *p = ADPlayer.shared;
    if (!p.album) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:p.album.title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"从头播放" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [p playAt:0];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"缓存整本到本机" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[ADDownloader shared] addAlbum:p.album tracks:p.tracks];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showRateMenu {
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
    NSMutableArray *opts = [NSMutableArray arrayWithObjects:@"15 分钟", @"30 分钟", @"45 分钟", @"60 分钟", @"90 分钟", @"自定义时长…", nil];
    NSInteger n = opts.count;
    if (ADPlayer.shared.sleepDeadline > 0) [opts addObject:@"取消定时关闭"];
    double now = [NSDate date].timeIntervalSince1970;
    NSArray *mins = @[@15, @30, @45, @60, @90];
    [ADOptionSheet showIn:self title:@"定时关闭" options:opts
              destructive:(ADPlayer.shared.sleepDeadline > 0 ? n : -1)
                   choose:^(NSInteger i) {
        if (i < 5) {
            ADPlayer.shared.sleepDeadline = now + [mins[i] doubleValue] * 60;
            [self sync];
        } else if (i == 5) {
            [self askCustomSleep];
        } else {
            ADPlayer.shared.sleepDeadline = 0;
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
- (void)sliderEnd { self.dragging = NO; [ADPlayer.shared seekTo:self.slider.value]; }
- (void)toggle { [ADPlayer.shared toggle]; [self sync]; }
- (void)prev { [ADPlayer.shared prev]; [self sync]; }
- (void)next { [ADPlayer.shared next]; [self sync]; }
- (void)back15 { [ADPlayer.shared seekBy:-15]; }
- (void)fwd15 { [ADPlayer.shared seekBy:15]; }

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

- (void)closeQueue {
    if (!self.showQueue) return;
    self.showQueue = NO;
    self.queueDim.hidden = YES;
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        self.queue.frame = CGRectMake(16, H, W - 32, 300);
    } completion:^(BOOL ok) { self.queue.hidden = YES; }];
}

- (void)openQueue {
    self.showQueue = !self.showQueue;
    self.queue.hidden = !self.showQueue;
    self.queueDim.hidden = !self.showQueue;
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
        self.queue.frame = self.showQueue ? CGRectMake(16, H - 320, W - 32, 300) : CGRectMake(16, H, W - 32, 300);
    }];
    [self.queue reloadData];
    if (self.showQueue) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:ADPlayer.shared.index inSection:0];
        if (ip.row < (NSInteger)ADPlayer.shared.tracks.count)
            [self.queue scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return ADPlayer.shared.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"q";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    ADTrack *tr = ADPlayer.shared.tracks[ip.row];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    c.textLabel.text = tr.title;
    c.textLabel.textColor = (ip.row == ADPlayer.shared.index) ? [ADUtil brand] : UIColor.whiteColor;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [ADPlayer.shared playAt:ip.row];
    [self openQueue];
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
    self.view.backgroundColor = [UIColor colorWithRed:0.075 green:0.075 blue:0.082 alpha:1];
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

- (void)save {
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"服务";
    if (s == 2) return @"播放与预加载";
    return @"本机下载";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return self.status.text ?: @"点 Token 那一行可以粘贴或修改";
    if (![ADDownloader shared].tasks.count)
        return @"在专辑页点「缓存到本机」，音频会存进手机，离线也能听";
    return @"左滑删除或暂停，点击行可暂停/继续；本机下载不占用服务器";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 3;
    if (s == 2) return 4;
    return MAX(1, (NSInteger)[ADDownloader shared].tasks.count) + 1;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.selectionStyle = UITableViewCellSelectionStyleNone;

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
