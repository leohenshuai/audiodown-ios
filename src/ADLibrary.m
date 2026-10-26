#import "AD.h"

// ───────────── 收听历史 ─────────────
@interface ADHistCell : UITableViewCell
@property (nonatomic, strong) UIView *card, *barBg, *barFill;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title, *sub, *meta;
@property (nonatomic, strong) UIButton *play;
@property (nonatomic, assign) CGFloat frac;
@property (nonatomic, copy) void (^onPlay)(void);
@end
@implementation ADHistCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [UIView new];
        [ADLiquid glassLite:self.card radius:20];
        [self.contentView addSubview:self.card];
        self.cover = [UIImageView new];
        self.cover.layer.cornerRadius = 12; self.cover.clipsToBounds = YES;
        self.title = [ADUtil label:nil size:16 color:UIColor.whiteColor];
        self.title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; self.title.numberOfLines = 1;
        self.sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.7]]; self.sub.numberOfLines = 1;
        self.meta = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.45]]; self.meta.numberOfLines = 1;
        self.barBg = [UIView new]; self.barBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1]; self.barBg.layer.cornerRadius = 1;
        self.barFill = [UIView new]; self.barFill.backgroundColor = [ADUtil brand]; self.barFill.layer.cornerRadius = 1;
        [self.barBg addSubview:self.barFill];
        self.play = [UIButton buttonWithType:UIButtonTypeSystem];
        self.play.backgroundColor = [[ADUtil brand] colorWithAlphaComponent:0.18];
        self.play.layer.cornerRadius = 20;
        self.play.tintColor = [ADUtil brand];
        [self.play setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        [self.play addTarget:self action:@selector(tapPlay) forControlEvents:UIControlEventTouchUpInside];
        for (UIView *v in @[self.cover, self.title, self.sub, self.meta, self.barBg, self.play]) [self.card addSubview:v];
    }
    return self;
}
- (void)tapPlay { [ADHaptic tap]; if (self.onPlay) self.onPlay(); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    self.card.frame = CGRectMake(16, 5, W - 32, H - 10);
    CGFloat cw = self.card.bounds.size.width, ch = self.card.bounds.size.height;
    self.cover.frame = CGRectMake(12, (ch - 58) / 2, 58, 58);
    CGFloat x = 84, tw = cw - x - 62;
    self.title.frame = CGRectMake(x, 12, tw, 20);
    self.sub.frame = CGRectMake(x, 34, tw, 16);
    self.meta.frame = CGRectMake(x, 52, tw, 15);
    self.barBg.frame = CGRectMake(x, ch - 11, tw, 2);
    self.barFill.frame = CGRectMake(0, 0, tw * self.frac, 2);
    self.play.frame = CGRectMake(cw - 52, (ch - 40) / 2, 40, 40);
}
@end

@interface ADHistoryController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIButton *back, *clear;
@property (nonatomic, strong) UILabel *head, *count, *empty;
@end

@implementation ADHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = 92;
    self.table.contentInset = UIEdgeInsetsMake(6, 0, 100, 0);
    [self.view addSubview:self.table];

    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    [self.back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    self.clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.clear radius:18];
    [self.clear setTitle:@"清空" forState:UIControlStateNormal];
    [self.clear setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
    self.clear.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.clear addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
    self.head = [ADUtil label:@"PingFangSC-Semibold" size:30 color:UIColor.whiteColor];
    self.head.text = @"收听历史"; self.head.numberOfLines = 1;
    self.count = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.5]]; self.count.numberOfLines = 1;
    self.empty = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.45]];
    self.empty.textAlignment = NSTextAlignmentCenter; self.empty.text = @"还没有收听记录\n听过的书会出现在这里";
    for (UIView *v in @[self.back, self.clear, self.head, self.count, self.empty]) [self.view addSubview:v];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:@"ADContinueChanged" object:nil];
}
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
    [self reload];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.navigationController.viewControllers.count > 1; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, top = MAX(self.view.safeAreaInsets.top, 47);
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    self.clear.frame = CGRectMake(W - 16 - 64, top + 6, 64, 36);
    self.head.frame = CGRectMake(72, top + 6, W - 72 - 90, 38);
    self.count.frame = CGRectMake(20, top + 54, W - 40, 18);
    self.table.frame = CGRectMake(0, top + 78, W, self.view.bounds.size.height - top - 78);
    self.empty.frame = CGRectMake(30, self.view.bounds.size.height / 2 - 50, W - 60, 60);
}
- (void)goBack { [ADHaptic tap]; [self.navigationController popViewControllerAnimated:YES]; }
- (void)reload {
    NSInteger n = [ADStore shared].history.count;
    self.count.text = n ? [NSString stringWithFormat:@"共 %ld 本 · 左滑可移除或收藏", (long)n] : @"";
    self.empty.hidden = n > 0; self.clear.hidden = n == 0;
    [self.table reloadData];
}
- (void)clearAll {
    [ADHaptic warning];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空收听历史？" message:@"只清除历史记录，不影响收藏和已下载的音频。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        for (ADAlbum *al in [[ADStore shared].history copy]) [[ADStore shared] removeContinue:al.albumId];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [ADStore shared].history.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADHistCell *c = [t dequeueReusableCellWithIdentifier:@"h"];
    if (!c) c = [[ADHistCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"h"];
    ADAlbum *a = [ADStore shared].history[ip.row];
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    c.title.text = a.title;
    [ADUtil cover:c.cover url:a.cover];
    if (info) {
        NSInteger idx = [info[@"index"] integerValue];
        double sec = [info[@"seconds"] doubleValue], dur = [info[@"duration"] doubleValue];
        c.sub.text = [NSString stringWithFormat:@"第 %ld 集 · %@", (long)idx + 1, info[@"title"] ?: @""];
        NSMutableArray *bits = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"听到 %@", [ADUtil time:sec]]];
        if (a.trackCount > 0) [bits addObject:[NSString stringWithFormat:@"剩余 %ld 集", (long)MAX(0, a.trackCount - idx - 1)]];
        c.meta.text = [bits componentsJoinedByString:@" · "];
        c.frac = dur > 0 ? MIN(1, sec / dur) : 0;
    } else {
        c.sub.text = a.anchor ?: @""; c.meta.text = @""; c.frac = 0;
    }
    c.barBg.hidden = c.frac <= 0;
    __weak typeof(self) w = self;
    c.onPlay = ^{
        if (!info) return;
        [ADPlayer.shared openAlbum:a trackId:info[@"trackId"] index:[info[@"index"] integerValue] seconds:[info[@"seconds"] doubleValue] autoPlay:YES];
        [w presentViewController:[ADPlayerController new] animated:YES completion:nil];
    };
    [c setNeedsLayout];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    [ADHaptic tap];
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = [ADStore shared].history[ip.row];
    [self.navigationController pushViewController:vc animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    ADAlbum *a = [ADStore shared].history[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"移除" handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
        [ADHaptic warning];
        [[ADStore shared] removeContinue:a.albumId];
        [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
        [self performSelector:@selector(reload) withObject:nil afterDelay:0.35];
        done(YES);
    }];
    BOOL fav = [[ADStore shared] isFavorite:a.albumId];
    UIContextualAction *fv = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:fav ? @"取消收藏" : @"收藏" handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
        [ADHaptic success]; [[ADStore shared] toggleFavorite:a]; done(YES);
    }];
    fv.backgroundColor = [ADUtil brand];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, fv]];
}
@end

// ───────────── 本机下载 ─────────────
@interface ADDownloadsController ()
@end

@implementation ADDownloadsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"本机下载";
    self.view.backgroundColor = [UIColor colorWithRed:0.075 green:0.075 blue:0.082 alpha:1];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [NSNotificationCenter.defaultCenter addObserver:self.tableView selector:@selector(reloadData) name:@"ADDownloadChanged" object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.navigationController.navigationBar.hidden = NO;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? nil : @"长按或左滑可删除";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    return [ADDownloader shared].tasks.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    if (ip.section == 0) {
        NSArray *tasks = [ADDownloader shared].tasks;
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        c.textLabel.text = anyRunning ? @"全部暂停" : @"全部继续";
        c.textLabel.textColor = [ADUtil brand];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        return c;
    }
    if (![ADDownloader shared].tasks.count) {
        c.textLabel.text = @"还没有下载";
        c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        c.detailTextLabel.text = @"在专辑页点「缓存到本机」";
        return c;
    }
    ADTask *task = [ADDownloader shared].tasks[ip.row];
    c.textLabel.text = task.title.length ? task.title : task.albumId;
    NSString *st = task.state == ADTaskStateRunning ? @"下载中"
                 : (task.state == ADTaskStatePaused ? @"已暂停"
                 : (task.state == ADTaskStateDone ? @"已完成"
                 : (task.state == ADTaskStateFailed ? @"有失败" : @"排队中")));
    NSString *bytes = task.bytes > 0 ? [NSString stringWithFormat:@" · %.1fMB", task.bytes / 1048576.0] : @"";
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld/%ld%@", st, (long)task.done, (long)task.tracks.count, bytes];
    [ADUtil cover:c.imageView url:task.cover];
    c.imageView.contentMode = UIViewContentModeScaleAspectFill;
    c.imageView.clipsToBounds = YES;
    c.imageView.layer.cornerRadius = 8;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        NSArray *tasks = [ADDownloader shared].tasks;
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        if (anyRunning) [[ADDownloader shared] pauseAll]; else [[ADDownloader shared] resumeAll];
        [t reloadData];
        return;
    }
    NSArray *tasks = [ADDownloader shared].tasks;
    if (ip.row < (NSInteger)tasks.count) {
        ADTask *task = tasks[ip.row];
        if (task.state == ADTaskStateRunning || task.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:task];
        else [[ADDownloader shared] resumeTask:task];
        [t reloadData];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1) return nil;
    NSArray *tasks = [ADDownloader shared].tasks;
    if (ip.row >= (NSInteger)tasks.count) return nil;
    ADTask *task = tasks[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[ADDownloader shared] deleteTask:task];
        [t reloadData];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end
