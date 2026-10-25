#import "AD.h"

// ───────────── 收听历史 ─────────────
@interface ADHistoryController ()
@end

@implementation ADHistoryController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收听历史";
    self.view.backgroundColor = [UIColor colorWithRed:0.075 green:0.075 blue:0.082 alpha:1];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.tableView.rowHeight = 68;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.navigationController.navigationBar.hidden = NO;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [ADStore shared].history.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"h";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    ADAlbum *a = [ADStore shared].history[ip.item];
    NSDictionary *info = [[ADStore shared] lastInfoOf:a.albumId];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    c.detailTextLabel.font = [UIFont systemFontOfSize:12];
    c.textLabel.text = a.title;
    NSInteger idx = [info[@"index"] integerValue];
    double sec = [info[@"seconds"] doubleValue];
    c.detailTextLabel.text = info ? [NSString stringWithFormat:@"第 %ld 集 · %@ · 剩余 %ld 集", (long)idx + 1, [ADUtil time:sec], (long)MAX(0, a.trackCount - idx - 1)] : @"";
    [ADUtil cover:c.imageView url:a.cover];
    c.imageView.contentMode = UIViewContentModeScaleAspectFill;
    c.imageView.clipsToBounds = YES;
    c.imageView.layer.cornerRadius = 8;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    ADAlbum *a = [ADStore shared].history[ip.item];
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = a;
    [self.navigationController pushViewController:vc animated:YES];
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
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
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
