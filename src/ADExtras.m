#import "AD.h"

static UITableViewCell *ADCell(UITableView *t, NSString *title, NSString *sub) {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.textLabel.text = title; c.detailTextLabel.text = sub;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}
static void ADStyle(UITableViewController *vc, NSString *title) {
    vc.title = title;
    UIView *bg = [[UIView alloc] initWithFrame:vc.view.bounds];
    [ADLiquid canvas:bg];
    vc.tableView.backgroundView = bg;
    vc.tableView.backgroundColor = UIColor.clearColor;
    vc.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    vc.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    vc.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}
static void ADCloseIfModal(UIViewController *vc) {
    if (vc.navigationController.viewControllers.firstObject == vc && vc.navigationController.presentingViewController)
        vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:vc action:@selector(adClose)];
}
static NSString *ADSize(double b) {
    if (b >= 1073741824.0) return [NSString stringWithFormat:@"%.2f GB", b / 1073741824.0];
    if (b >= 1048576.0) return [NSString stringWithFormat:@"%.1f MB", b / 1048576.0];
    return [NSString stringWithFormat:@"%.0f KB", b / 1024.0];
}
static double ADDirSize(NSString *dir) {
    double sum = 0; NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil])
        sum += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:f] error:nil] fileSize];
    return sum;
}
static NSString *ADDocs(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }

@interface UIViewController (ADClose) - (void)adClose; @end
@implementation UIViewController (ADClose)
- (void)adClose { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
@end

// ───────────── 书签 ─────────────
@implementation ADBookmarksController
- (void)viewDidLoad {
    [super viewDidLoad];
    ADStyle(self, @"书签"); ADCloseIfModal(self);
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return MAX(1, (NSInteger)[ADStore shared].bookmarks.count);
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *b = [ADStore shared].bookmarks;
    if (!b.count) {
        UITableViewCell *c = ADCell(t, @"还没有书签", @"在播放页 ⋯ → 在此处添加书签");
        c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        return c;
    }
    NSDictionary *d = b[ip.row];
    NSString *note = [d[@"note"] length] ? [NSString stringWithFormat:@"  “%@”", d[@"note"]] : @"";
    UITableViewCell *c = ADCell(t, [NSString stringWithFormat:@"%@%@", d[@"albumTitle"], note],
        [NSString stringWithFormat:@"%@ · %@", d[@"trackTitle"], [ADUtil time:[d[@"seconds"] doubleValue]]]);
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSArray *b = [ADStore shared].bookmarks;
    if (!b.count) return;
    NSDictionary *d = b[ip.row];
    [ADHaptic tap];
    ADAlbum *a = [ADAlbum new];
    a.albumId = d[@"albumId"]; a.title = d[@"albumTitle"]; a.cover = d[@"cover"]; a.provider = d[@"provider"]; a.anchor = d[@"anchor"];
    for (ADAlbum *x in [ADStore shared].history) if ([x.albumId isEqualToString:a.albumId]) { a = x; break; }
    [ADPlayer.shared openAlbum:a trackId:d[@"trackId"] index:[d[@"index"] integerValue] seconds:[d[@"seconds"] doubleValue] autoPlay:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *b = [ADStore shared].bookmarks;
    if (!b.count) return nil;
    NSDictionary *d = b[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[ADStore shared] removeBookmark:d]; [t reloadData]; done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end

// ───────────── 离线存储管理 ─────────────
@interface ADStorageController ()
@property (nonatomic, assign) double dl, pre, cov;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *perAlbum;
@end
@implementation ADStorageController
- (void)viewDidLoad {
    [super viewDidLoad];
    ADStyle(self, @"离线存储");
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scan) name:@"ADDownloadChanged" object:nil];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self scan]; }
- (void)scan {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *docs = ADDocs();
        double dl = ADDirSize([docs stringByAppendingPathComponent:@"audio"]);
        double pre = ADDirSize([docs stringByAppendingPathComponent:@"cache/prefetch"]);
        double cov = ADDirSize([docs stringByAppendingPathComponent:@"cache/covers"]);
        NSMutableDictionary *per = [NSMutableDictionary dictionary];
        for (ADTask *tk in [ADDownloader shared].tasks) {
            double sum = 0;
            for (ADTrack *tr in tk.tracks) {
                NSURL *u = [[ADDownloader shared] localURL:tr.trackId];
                if (u) sum += [[NSFileManager.defaultManager attributesOfItemAtPath:u.path error:nil] fileSize];
            }
            per[tk.albumId] = @(sum);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.dl = dl; self.pre = pre; self.cov = cov; self.perAlbum = per;
            [self.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"占用" : (s == 1 ? @"清理" : @"本机下载（按专辑）");
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 2) return @"点一行：有失败/暂停的集会重试；左滑删除整本";
    return nil;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == 1) return 3;
    return MAX(1, (NSInteger)[ADDownloader shared].tasks.count);
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        NSArray *n = @[@"本机下载", @"预缓存（临时）", @"封面缓存", @"合计"];
        double v[] = {self.dl, self.pre, self.cov, self.dl + self.pre + self.cov};
        UITableViewCell *c = ADCell(t, n[ip.row], nil);
        UILabel *l = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.75]];
        l.text = ADSize(v[ip.row]); [l sizeToFit]; c.accessoryView = l;
        return c;
    }
    if (ip.section == 1) {
        NSArray *n = @[@"清空预缓存", @"清空封面缓存", @"重试所有失败 / 暂停的下载"];
        UITableViewCell *c = ADCell(t, n[ip.row], nil);
        c.textLabel.textColor = [ADUtil brand];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        return c;
    }
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (!tasks.count) { UITableViewCell *c = ADCell(t, @"暂无本机下载", nil); c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45]; return c; }
    ADTask *k = tasks[ip.row];
    NSString *st = k.state == ADTaskStateRunning ? @"下载中" : (k.state == ADTaskStatePaused ? @"已暂停" : (k.state == ADTaskStateDone ? @"已完成" : (k.state == ADTaskStateFailed ? @"有失败" : @"排队中")));
    NSString *fail = k.failed ? [NSString stringWithFormat:@" · 失败 %ld", (long)k.failed] : @"";
    UITableViewCell *c = ADCell(t, k.title.length ? k.title : k.albumId,
        [NSString stringWithFormat:@"%@ · %ld/%ld 集 · %@%@", st, (long)k.done, (long)k.tracks.count, ADSize([self.perAlbum[k.albumId] doubleValue]), fail]);
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}
- (void)confirm:(NSString *)msg action:(void (^)(void))go {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { go(); [self scan]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (ip.section == 1) {
        if (ip.row == 0) [self confirm:@"清空预缓存？（不影响本机下载）" action:^{
            NSString *d = [ADDocs() stringByAppendingPathComponent:@"cache/prefetch"];
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:nil];
        }];
        else if (ip.row == 1) [self confirm:@"清空封面缓存？下次会重新下载" action:^{
            NSString *d = [ADDocs() stringByAppendingPathComponent:@"cache/covers"];
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:nil];
        }];
        else { [[ADDownloader shared] resumeAll]; [ADHaptic success]; [self scan]; }
        return;
    }
    if (ip.section == 2) {
        NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
        if (!tasks.count) return;
        ADTask *k = tasks[ip.row];
        if (k.state == ADTaskStatePaused || k.state == ADTaskStateFailed) { [[ADDownloader shared] resumeTask:k]; [ADHaptic success]; }
        else if (k.state == ADTaskStateRunning || k.state == ADTaskStateQueued) [[ADDownloader shared] pauseTask:k];
        [t reloadData];
    }
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.section != 2 || !tasks.count) return nil;
    ADTask *k = tasks[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[ADDownloader shared] deleteTask:k]; [self scan]; done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end

// ───────────── 备份与恢复 ─────────────
@interface ADBackupController ()
@property (nonatomic, strong) NSArray<NSString *> *files;
@end
@implementation ADBackupController
+ (NSArray<NSString *> *)keys { return @[@"fav.dat", @"hist.dat", @"pos.dat", @"last.dat", @"info.dat", @"done.dat", @"donealbums.dat", @"want.dat", @"pin.dat", @"bm.dat"]; }
- (NSString *)dir {
    NSString *d = [ADDocs() stringByAppendingPathComponent:@"backups"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
- (void)viewDidLoad { [super viewDidLoad]; ADStyle(self, @"备份与恢复"); }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reloadFiles]; }
- (void)reloadFiles {
    NSMutableArray *fs = [NSMutableArray array];
    for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self dir] error:nil]) if ([f hasSuffix:@".adbak"]) [fs addObject:f];
    [fs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [b compare:a]; }];
    self.files = fs;
    [self.tableView reloadData];
}
- (NSString *)makeBackup:(NSString *)prefix {
    [[ADStore shared] save];
    NSMutableDictionary *pack = [NSMutableDictionary dictionary];
    for (NSString *k in [ADBackupController keys]) {
        NSData *d = [NSData dataWithContentsOfFile:[ADDocs() stringByAppendingPathComponent:k]];
        if (d) pack[k] = d;
    }
    NSMutableDictionary *ud = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"ad.rate", @"ad_playmode", @"ad_prefetch", @"ad_prefetch_wifi", @"ad_prefetch_count", @"ad_prefetch_days", @"ad_haptic", @"ad_sound"]) {
        id v = [NSUserDefaults.standardUserDefaults objectForKey:k]; if (v) ud[k] = v;
    }
    NSDictionary *root = @{@"magic": @"adbak1", @"files": pack, @"defaults": ud, @"time": @([NSDate date].timeIntervalSince1970)};
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"%@-%@.adbak", prefix, [df stringFromDate:NSDate.date]];
    [out writeToFile:[[self dir] stringByAppendingPathComponent:name] atomically:YES];
    return name;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s == 0 ? @"备份" : @"已有备份"; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return s == 0 ? @"包含：收藏、历史、想听、置顶、播放进度、听完标记、书签、播放设置。不含 token 和已下载的音频。" : @"点一行恢复；左滑删除。也可把 .adbak 文件放进 文件 App → 听书 → backups 再导入。";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? 2 : MAX(1, (NSInteger)self.files.count); }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = ADCell(t, ip.row == 0 ? @"立即备份" : @"备份并分享…", ip.row == 0 ? @"存到 backups 文件夹" : @"生成后用系统分享发到别处");
        c.textLabel.textColor = [ADUtil brand]; c.selectionStyle = UITableViewCellSelectionStyleDefault; return c;
    }
    if (!self.files.count) { UITableViewCell *c = ADCell(t, @"还没有备份", nil); c.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45]; return c; }
    NSString *f = self.files[ip.row];
    NSString *p = [[self dir] stringByAppendingPathComponent:f];
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    UITableViewCell *c = ADCell(t, f, [NSString stringWithFormat:@"%@ · %@", ADSize(at.fileSize), [NSDateFormatter localizedStringFromDate:at.fileModificationDate dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]]);
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        NSString *n = [self makeBackup:@"听书备份"]; [ADHaptic success]; [self reloadFiles];
        if (ip.row == 1) {
            UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:[[self dir] stringByAppendingPathComponent:n]]] applicationActivities:nil];
            av.popoverPresentationController.sourceView = t;
            [self presentViewController:av animated:YES completion:nil];
        }
        return;
    }
    if (!self.files.count) return;
    NSString *f = self.files[ip.row];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"恢复这份备份？" message:@"当前的收藏、进度等会被覆盖。恢复前会自动再存一份当前状态。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self restore:f]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)restore:(NSString *)f {
    NSData *raw = [NSData dataWithContentsOfFile:[[self dir] stringByAppendingPathComponent:f]];
    NSDictionary *root = raw ? [NSPropertyListSerialization propertyListWithData:raw options:0 format:nil error:nil] : nil;
    NSString *msg;
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"magic"] isEqual:@"adbak1"]) {
        msg = @"这不是有效的备份文件";
    } else {
        [self makeBackup:@"恢复前自动备份"];
        NSDictionary *files = root[@"files"];
        for (NSString *k in [ADBackupController keys]) {
            NSData *d = files[k];
            NSString *path = [ADDocs() stringByAppendingPathComponent:k];
            if (d) [d writeToFile:path atomically:YES]; else [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        }
        NSDictionary *ud = root[@"defaults"];
        for (NSString *k in ud) [NSUserDefaults.standardUserDefaults setObject:ud[k] forKey:k];
        [[ADStore shared] reload];
        [ADHaptic success];
        msg = [NSString stringWithFormat:@"已恢复 %lu 项数据", (unsigned long)files.count];
    }
    UIAlertController *r = [UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];
    [r addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:r animated:YES completion:nil];
    [self reloadFiles];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1 || !self.files.count) return nil;
    NSString *f = self.files[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [NSFileManager.defaultManager removeItemAtPath:[[self dir] stringByAppendingPathComponent:f] error:nil];
        [self reloadFiles]; done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end
