#import "AD.h"

// ───────────── 书签 / 离线存储 / 备份恢复：统一的玻璃卡片界面 ─────────────
static NSString *ADDocs(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }
static NSString *ADSize(double b) {
    if (b >= 1073741824.0) return [NSString stringWithFormat:@"%.2f GB", b / 1073741824.0];
    if (b >= 1048576.0) return [NSString stringWithFormat:@"%.1f MB", b / 1048576.0];
    if (b > 0) return [NSString stringWithFormat:@"%.0f KB", b / 1024.0];
    return @"0 KB";
}
static double ADDirSize(NSString *dir) {
    double sum = 0; NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil])
        sum += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:f] error:nil] fileSize];
    return sum;
}
static UIImage *ADS(NSString *n, CGFloat sz, UIImageSymbolWeight w) {
    return [UIImage systemImageNamed:n withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:sz weight:w]];
}
static NSString *ADRelTime(NSTimeInterval ts) {
    NSTimeInterval d = [NSDate date].timeIntervalSince1970 - ts;
    if (d < 60) return @"刚刚";
    if (d < 3600) return [NSString stringWithFormat:@"%ld 分钟前", (long)(d / 60)];
    if (d < 86400) return [NSString stringWithFormat:@"%ld 小时前", (long)(d / 3600)];
    if (d < 86400 * 7) return [NSString stringWithFormat:@"%ld 天前", (long)(d / 86400)];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"M月d日";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@interface UIViewController (ADClose) - (void)adClose; @end
@implementation UIViewController (ADClose)
- (void)adClose { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
@end

// 公共页面骨架：渐变背景、玻璃返回钮、大标题、副标题、空状态、右上按钮
@interface ADGlassPage () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIButton *back, *right;
@property (nonatomic, strong) UILabel *head, *sub, *empty;
@property (nonatomic, strong) UIImageView *emptyIcon;
- (void)setupTitle:(NSString *)t emptyIcon:(NSString *)icon emptyText:(NSString *)e;
- (void)showEmpty:(BOOL)on;
@end
@implementation ADGlassPage
- (void)setupTitle:(NSString *)t emptyIcon:(NSString *)icon emptyText:(NSString *)e {
    [ADLiquid canvas:self.view];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.contentInset = UIEdgeInsetsMake(4, 0, 110, 0);
    if (@available(iOS 15.0, *)) self.table.sectionHeaderTopPadding = 0;
    [self.view addSubview:self.table];
    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    BOOL modal = (self.navigationController.viewControllers.firstObject == self && self.navigationController.presentingViewController);
    [self.back setImage:ADS(modal ? @"xmark" : @"chevron.left", 17, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    self.right = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.right radius:18];
    self.right.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.right.hidden = YES;
    self.head = [ADUtil label:@"PingFangSC-Semibold" size:30 color:UIColor.whiteColor];
    self.head.text = t; self.head.numberOfLines = 1;
    self.sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.5]]; self.sub.numberOfLines = 1;
    self.emptyIcon = [[UIImageView alloc] initWithImage:ADS(icon, 46, UIImageSymbolWeightLight)];
    self.emptyIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.22]; self.emptyIcon.contentMode = UIViewContentModeCenter;
    self.empty = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.45]];
    self.empty.textAlignment = NSTextAlignmentCenter; self.empty.text = e;
    for (UIView *v in @[self.back, self.right, self.head, self.sub, self.emptyIcon, self.empty]) [self.view addSubview:v];
}
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.navigationController.viewControllers.count > 1; }
- (void)goBack {
    [ADHaptic tap];
    if (self.navigationController.viewControllers.firstObject == self && self.navigationController.presentingViewController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    // 回到用系统导航栏的设置页时恢复导航栏
    NSArray *vcs = self.navigationController.viewControllers;
    UIViewController *prev = vcs.count >= 2 ? vcs[vcs.count - 2] : nil;
    if ([prev isKindOfClass:ADSettingsController.class]) self.navigationController.navigationBar.hidden = NO;
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)viewWillDisappear:(BOOL)a {
    [super viewWillDisappear:a];
    if (self.isMovingFromParentViewController) {
        UIViewController *top = self.navigationController.topViewController;
        if ([top isKindOfClass:ADSettingsController.class]) self.navigationController.navigationBar.hidden = NO;
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = MAX(self.view.safeAreaInsets.top, 47);
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    [self.right sizeToFit];
    CGFloat rw = MAX(64, self.right.bounds.size.width + 28);
    self.right.frame = CGRectMake(W - 16 - rw, top + 6, rw, 36);
    self.head.frame = CGRectMake(72, top + 6, W - 72 - rw - 24, 38);
    self.sub.frame = CGRectMake(20, top + 54, W - 40, 18);
    self.table.frame = CGRectMake(0, top + 78, W, H - top - 78);
    self.emptyIcon.frame = CGRectMake(0, H / 2 - 100, W, 60);
    self.empty.frame = CGRectMake(30, H / 2 - 34, W - 60, 50);
}
- (void)showEmpty:(BOOL)on { self.empty.hidden = self.emptyIcon.hidden = !on; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 0; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip { return [UITableViewCell new]; }
@end

// 玻璃卡片行：左侧图标或封面，标题、副标题、右侧附件
@interface ADGlassRow : UITableViewCell
@property (nonatomic, strong) UIView *card, *iconBg;
@property (nonatomic, strong) UIImageView *icon, *cover, *chev;
@property (nonatomic, strong) UILabel *title, *sub, *right, *note;
@property (nonatomic, assign) CGFloat coverSize;
@property (nonatomic, assign) BOOL first, last, grouped;
@end
@implementation ADGlassRow
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [UIView new];
        [ADLiquid glassLite:self.card radius:18];
        [self.contentView addSubview:self.card];
        self.iconBg = [UIView new]; self.iconBg.layer.cornerRadius = 9;
        if (@available(iOS 13.0, *)) self.iconBg.layer.cornerCurve = kCACornerCurveContinuous;
        self.icon = [UIImageView new]; self.icon.tintColor = UIColor.whiteColor; self.icon.contentMode = UIViewContentModeCenter;
        [self.iconBg addSubview:self.icon];
        self.cover = [UIImageView new]; self.cover.layer.cornerRadius = 10; self.cover.clipsToBounds = YES;
        self.cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        self.title = [ADUtil label:nil size:16 color:UIColor.whiteColor]; self.title.numberOfLines = 1;
        self.title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        self.sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.55]]; self.sub.numberOfLines = 1;
        self.note = [ADUtil label:nil size:12.5 color:[ADUtil brand]]; self.note.numberOfLines = 1;
        self.right = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.7]]; self.right.numberOfLines = 1;
        self.right.textAlignment = NSTextAlignmentRight;
        self.right.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
        self.chev = [[UIImageView alloc] initWithImage:ADS(@"chevron.right", 12, UIImageSymbolWeightSemibold)];
        self.chev.tintColor = [UIColor colorWithWhite:1 alpha:0.28]; self.chev.contentMode = UIViewContentModeCenter;
        for (UIView *v in @[self.iconBg, self.cover, self.title, self.sub, self.note, self.right, self.chev]) [self.card addSubview:v];
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconBg.hidden = self.cover.hidden = self.chev.hidden = YES;
    self.note.text = nil; self.sub.text = nil; self.right.text = nil;
    self.title.textColor = UIColor.whiteColor; self.coverSize = 0;
}
- (void)setHighlighted:(BOOL)h animated:(BOOL)a {
    [super setHighlighted:h animated:a];
    [UIView animateWithDuration:h ? 0.12 : 0.38 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.card.transform = h ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity; } completion:nil];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    self.card.frame = CGRectMake(16, 4, W - 32, H - 8);
    CGFloat cw = self.card.bounds.size.width, ch = self.card.bounds.size.height;
    CGFloat x = 16;
    if (!self.cover.hidden) {
        CGFloat s = self.coverSize > 0 ? self.coverSize : 52;
        self.cover.frame = CGRectMake(12, (ch - s) / 2, s, s); x = 12 + s + 12;
    } else if (!self.iconBg.hidden) {
        self.iconBg.frame = CGRectMake(14, (ch - 32) / 2, 32, 32); self.icon.frame = self.iconBg.bounds; x = 14 + 32 + 12;
    }
    CGFloat rx = cw - 14;
    if (!self.chev.hidden) { self.chev.frame = CGRectMake(cw - 26, (ch - 14) / 2, 14, 14); rx = cw - 32; }
    CGFloat rw = 0;
    if (self.right.text.length) { rw = MIN(140, [self.right.text sizeWithAttributes:@{NSFontAttributeName: self.right.font}].width + 4); self.right.frame = CGRectMake(rx - rw, 0, rw, ch); rx -= rw + 10; }
    CGFloat tw = rx - x;
    BOOL two = self.sub.text.length > 0, three = self.note.text.length > 0;
    if (three) {
        self.title.frame = CGRectMake(x, 11, tw, 20);
        self.sub.frame = CGRectMake(x, 33, tw, 16);
        self.note.frame = CGRectMake(x, 51, tw, 16);
    } else if (two) {
        self.title.frame = CGRectMake(x, ch / 2 - 19, tw, 20);
        self.sub.frame = CGRectMake(x, ch / 2 + 3, tw, 16);
    } else self.title.frame = CGRectMake(x, 0, tw, ch);
}
- (void)iconNamed:(NSString *)n color:(UIColor *)c {
    self.iconBg.hidden = NO; self.cover.hidden = YES;
    self.iconBg.backgroundColor = c;
    self.icon.image = ADS(n, 15, UIImageSymbolWeightSemibold);
}
@end

static UIView *ADSectionHeader(NSString *t, CGFloat W) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 40)];
    UILabel *l = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.5]];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.text = t; l.numberOfLines = 1; l.frame = CGRectMake(24, 14, W - 48, 20);
    [v addSubview:l];
    return v;
}
static UIView *ADSectionFooter(NSString *t, CGFloat W) {
    UILabel *l = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.4]];
    l.text = t; l.numberOfLines = 0;
    CGSize sz = [l sizeThatFits:CGSizeMake(W - 48, 200)];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, sz.height + 16)];
    l.frame = CGRectMake(24, 6, W - 48, sz.height);
    [v addSubview:l];
    return v;
}

// ───────────── 书签 ─────────────
@interface ADBookmarksController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end
@implementation ADBookmarksController
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTitle:@"书签" emptyIcon:@"bookmark" emptyText:@"还没有书签\n在播放页 ⋯ → 在此处添加书签"];
    self.table.rowHeight = 92;
    [self.table registerClass:ADGlassRow.class forCellReuseIdentifier:@"r"];
    [self.right setTitle:@"编辑" forState:UIControlStateNormal];
    [self.right setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.right addTarget:self action:@selector(toggleEdit) forControlEvents:UIControlEventTouchUpInside];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reload]; }
- (void)reload {
    self.items = [ADStore shared].bookmarks;
    NSMutableSet *books = [NSMutableSet set];
    for (NSDictionary *d in self.items) if (d[@"albumId"]) [books addObject:d[@"albumId"]];
    self.sub.text = self.items.count ? [NSString stringWithFormat:@"%ld 条 · %ld 本书 · 点一条从那里继续听", (long)self.items.count, (long)books.count] : @"";
    self.right.hidden = self.items.count == 0;
    [self showEmpty:self.items.count == 0];
    [self.table reloadData];
    [self.view setNeedsLayout];
}
- (void)toggleEdit {
    [ADHaptic select];
    [self.table setEditing:!self.table.editing animated:YES];
    [self.right setTitle:self.table.editing ? @"完成" : @"编辑" forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADGlassRow *c = [t dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    NSDictionary *d = self.items[ip.row];
    c.cover.hidden = NO; c.iconBg.hidden = YES; c.coverSize = 64;
    [ADUtil cover:c.cover url:d[@"cover"]];
    c.title.text = d[@"albumTitle"] ?: @"";
    c.sub.text = [NSString stringWithFormat:@"%@ · %@", d[@"trackTitle"] ?: @"", [ADUtil time:[d[@"seconds"] doubleValue]]];
    NSString *note = [d[@"note"] length] ? [NSString stringWithFormat:@"“%@”", d[@"note"]] : nil;
    NSString *when = [d[@"ts"] doubleValue] > 0 ? ADRelTime([d[@"ts"] doubleValue]) : nil;
    c.note.text = note ?: when;
    c.note.textColor = note ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.38];
    c.right.text = nil;
    c.chev.hidden = NO;
    [c setNeedsLayout];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (t.editing) return;
    NSDictionary *d = self.items[ip.row];
    [ADHaptic tap];
    ADAlbum *a = [ADAlbum new];
    a.albumId = d[@"albumId"]; a.title = d[@"albumTitle"]; a.cover = d[@"cover"]; a.provider = d[@"provider"]; a.anchor = d[@"anchor"];
    for (ADAlbum *x in [ADStore shared].history) if ([x.albumId isEqualToString:a.albumId]) { a = x; break; }
    [ADPlayer.shared openAlbum:a trackId:d[@"trackId"] index:[d[@"index"] integerValue] seconds:[d[@"seconds"] doubleValue] autoPlay:YES];
    // 从播放页弹出的书签列表：关掉自己回到播放页；从设置进来的：弹出播放页
    UIViewController *presenter = self.navigationController.presentingViewController;
    if (presenter && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    if (!self.presentedViewController) [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)t editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleDelete; }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if (st != UITableViewCellEditingStyleDelete) return;
    [ADHaptic warning];
    [[ADStore shared] removeBookmark:self.items[ip.row]];
    self.items = [ADStore shared].bookmarks;
    [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.3];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *d = self.items[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ADHaptic warning];
        [[ADStore shared] removeBookmark:d];
        self.items = [ADStore shared].bookmarks;
        [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
        done(YES);
        [self performSelector:@selector(reload) withObject:nil afterDelay:0.3];
    }];
    del.image = ADS(@"trash.fill", 15, UIImageSymbolWeightSemibold);
    UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"备注" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [self editNote:d];
    }];
    edit.backgroundColor = [ADUtil swipe];
    edit.image = ADS(@"square.and.pencil", 15, UIImageSymbolWeightSemibold);
    return [UISwipeActionsConfiguration configurationWithActions:@[del, edit]];
}
- (void)editNote:(NSDictionary *)d {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"书签备注" message:[NSString stringWithFormat:@"%@ · %@", d[@"trackTitle"] ?: @"", [ADUtil time:[d[@"seconds"] doubleValue]]] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = d[@"note"]; tf.placeholder = @"写点什么（可留空）"; tf.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSMutableDictionary *m = [d mutableCopy];
        m[@"note"] = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        // 原位替换：先删再按原位置插回
        NSInteger idx = [[ADStore shared].bookmarks indexOfObject:d];
        [[ADStore shared] removeBookmark:d];
        [[ADStore shared] addBookmark:m];
        if (idx != NSNotFound && idx > 0) {
            NSMutableArray *arr = (NSMutableArray *)[ADStore shared].bookmarks;
            if ([arr isKindOfClass:NSMutableArray.class] && arr.count > (NSUInteger)idx) { [arr removeObjectAtIndex:0]; [arr insertObject:m atIndex:idx]; [[ADStore shared] save]; }
        }
        [ADHaptic success];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

// ───────────── 离线存储管理 ─────────────
@interface ADStorageController ()
@property (nonatomic, assign) double dl, pre, cov, freeDisk;
@property (nonatomic, assign) BOOL scanned;
@property (nonatomic, strong) UIView *gauge;
@end
@implementation ADStorageController
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTitle:@"离线存储" emptyIcon:@"internaldrive" emptyText:@""];
    [self showEmpty:NO];
    self.table.rowHeight = 64;
    [self.table registerClass:ADGlassRow.class forCellReuseIdentifier:@"r"];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scan) name:@"ADDownloadChanged" object:nil];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self scan]; }
- (void)scan {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *docs = ADDocs();
        double dl = ADDirSize([docs stringByAppendingPathComponent:@"audio"]);
        double pre = ADDirSize([docs stringByAppendingPathComponent:@"cache/prefetch"]);
        double cov = ADDirSize([docs stringByAppendingPathComponent:@"cache/covers"]);
        NSDictionary *fs = [NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
        double freeB = [fs[NSFileSystemFreeSize] doubleValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.dl = dl; self.pre = pre; self.cov = cov; self.freeDisk = freeB; self.scanned = YES;
            self.sub.text = [NSString stringWithFormat:@"共占用 %@ · 手机剩余 %@", ADSize(dl + pre + cov), ADSize(freeB)];
            [self buildGauge];
            [self.table reloadData];
        });
    });
}
// 顶部堆叠条：下载 / 预缓存 / 封面 三段占比
- (void)buildGauge {
    CGFloat W = self.view.bounds.size.width;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 112)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 6, W - 32, 100)];
    [ADLiquid glassLite:card radius:20];
    [h addSubview:card];
    double total = MAX(1, self.dl + self.pre + self.cov);
    UILabel *big = [ADUtil label:@"PingFangSC-Semibold" size:26 color:UIColor.whiteColor]; big.numberOfLines = 1;
    big.text = ADSize(self.dl + self.pre + self.cov); big.frame = CGRectMake(18, 12, card.bounds.size.width - 36, 32);
    [card addSubview:big];
    CGFloat bw = card.bounds.size.width - 36;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(18, 50, bw, 10)];
    bar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1]; bar.layer.cornerRadius = 5; bar.clipsToBounds = YES;
    [card addSubview:bar];
    NSArray *vals = @[@(self.dl), @(self.pre), @(self.cov)];
    NSArray *cols = @[[UIColor systemGreenColor], [ADUtil brand], [UIColor systemIndigoColor]];
    NSArray *names = @[@"下载", @"预缓存", @"封面"];
    CGFloat x = 0;
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat w = bw * [vals[i] doubleValue] / total;
        if (w > 0 && w < 3) w = 3;
        UIView *seg = [[UIView alloc] initWithFrame:CGRectMake(x, 0, w, 10)]; seg.backgroundColor = cols[i];
        [bar addSubview:seg]; x += w;
    }
    CGFloat lx = 18;
    for (NSInteger i = 0; i < 3; i++) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(lx, 74, 8, 8)]; dot.backgroundColor = cols[i]; dot.layer.cornerRadius = 4;
        [card addSubview:dot];
        UILabel *l = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.6]]; l.numberOfLines = 1;
        l.text = [NSString stringWithFormat:@"%@ %@", names[i], ADSize([vals[i] doubleValue])];
        [l sizeToFit]; l.frame = CGRectMake(lx + 13, 68, l.bounds.size.width, 20);
        [card addSubview:l]; lx += 13 + l.bounds.size.width + 16;
    }
    self.table.tableHeaderView = h;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s { return 40; }
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s { return ADSectionHeader(s == 0 ? @"清理" : @"按专辑", t.bounds.size.width); }
- (CGFloat)tableView:(UITableView *)t heightForFooterInSection:(NSInteger)s { return s == 1 ? 44 : 0.01; }
- (UIView *)tableView:(UITableView *)t viewForFooterInSection:(NSInteger)s { return s == 1 ? ADSectionFooter(@"点专辑查看单集；左滑删除整本", t.bounds.size.width) : [UIView new]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 3;
    return MAX(1, (NSInteger)[ADDownloader shared].tasks.count);
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 1 ? 76 : 64; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADGlassRow *c = [t dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    if (ip.section == 0) {
        NSArray *n = @[@"清空预缓存", @"清空封面缓存", @"重试所有失败的下载"];
        NSArray *s = @[@"不影响已下载的音频", @"下次浏览时会重新下载", @"暂停中的也会继续"];
        NSArray *ic = @[@"bolt.slash.fill", @"photo.on.rectangle", @"arrow.clockwise"];
        NSArray *col = @[[UIColor colorWithWhite:0.38 alpha:1], [UIColor systemIndigoColor], [UIColor systemGreenColor]];
        [c iconNamed:ic[ip.row] color:col[ip.row]];
        c.title.text = n[ip.row]; c.sub.text = s[ip.row];
        c.right.text = ip.row == 0 ? ADSize(self.pre) : (ip.row == 1 ? ADSize(self.cov) : nil);
        return c;
    }
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (!tasks.count) {
        [c iconNamed:@"arrow.down.circle" color:[UIColor colorWithWhite:1 alpha:0.15]];
        c.title.text = @"还没有下载"; c.title.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        return c;
    }
    ADTask *k = tasks[ip.row];
    ADDownloader *dl = [ADDownloader shared];
    c.cover.hidden = NO; c.iconBg.hidden = YES; c.coverSize = 52;
    [ADUtil cover:c.cover url:k.cover];
    c.title.text = k.title.length ? k.title : k.albumId;
    NSInteger local = [dl localCountOf:k], failed = [dl failedCountOf:k];
    c.sub.text = [NSString stringWithFormat:@"%ld/%ld 集%@", (long)local, (long)k.tracks.count, failed ? [NSString stringWithFormat:@" · %ld 集失败", (long)failed] : @""];
    c.right.text = ADSize([dl bytesForTask:k]);
    c.chev.hidden = NO;
    return c;
}
- (void)confirm:(NSString *)msg action:(void (^)(void))go {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [ADHaptic success]; go(); [self scan]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSFileManager *fm = NSFileManager.defaultManager;
    [ADHaptic tap];
    if (ip.section == 0) {
        if (ip.row == 0) [self confirm:[NSString stringWithFormat:@"清空预缓存（%@）？", ADSize(self.pre)] action:^{
            NSString *d = [ADDocs() stringByAppendingPathComponent:@"cache/prefetch"];
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:nil];
        }];
        else if (ip.row == 1) [self confirm:[NSString stringWithFormat:@"清空封面缓存（%@）？", ADSize(self.cov)] action:^{
            NSString *d = [ADDocs() stringByAppendingPathComponent:@"cache/covers"];
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:nil];
        }];
        else {
            for (ADTask *k in [ADDownloader shared].tasks) if ([[ADDownloader shared] localCountOf:k] < (NSInteger)k.tracks.count) [[ADDownloader shared] retryFailed:k];
            [[ADDownloader shared] resumeAll];
            [ADHaptic success]; [self scan];
        }
        return;
    }
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (!tasks.count) return;
    ADDownloadDetailController *vc = [ADDownloadDetailController new];
    vc.task = tasks[ip.row];
    [self.navigationController pushViewController:vc animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
    if (ip.section != 1 || !tasks.count) return nil;
    ADTask *k = tasks[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        UIAlertController *q = [UIAlertController alertControllerWithTitle:@"删除整本下载？" message:[NSString stringWithFormat:@"《%@》占用 %@", k.title ?: @"", ADSize([[ADDownloader shared] bytesForTask:k])] preferredStyle:UIAlertControllerStyleAlert];
        [q addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
        [q addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [ADHaptic warning]; [[ADDownloader shared] deleteTask:k]; [self scan]; done(YES);
        }]];
        [self presentViewController:q animated:YES completion:nil];
    }];
    del.image = ADS(@"trash.fill", 15, UIImageSymbolWeightSemibold);
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end

// ───────────── 备份与恢复 ─────────────
// 备份里的用户偏好键前缀：片头片尾是 ad_skip_head / ad_skip_tail（每本书单独的值在 skip.dat 里），
// 这里用前缀拼键名，恢复时旧备份缺这两个键也不会把用户的默认值写坏。
static NSString *const kSkipPrefix = @"ad_skip";
@interface ADBackupController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<NSString *> *files;
@end
@implementation ADBackupController
+ (NSArray<NSString *> *)keys { return @[@"fav.dat", @"hist.dat", @"pos.dat", @"last.dat", @"info.dat", @"done.dat", @"donealbums.dat", @"want.dat", @"pin.dat", @"bm.dat", @"skip.dat"]; }
- (NSString *)dir {
    NSString *d = [ADDocs() stringByAppendingPathComponent:@"backups"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTitle:@"备份与恢复" emptyIcon:@"externaldrive" emptyText:@""];
    [self showEmpty:NO];
    [self.table registerClass:ADGlassRow.class forCellReuseIdentifier:@"r"];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reloadFiles]; }
- (void)reloadFiles {
    NSMutableArray *fs = [NSMutableArray array];
    for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self dir] error:nil]) if ([f hasSuffix:@".adbak"]) [fs addObject:f];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *da = [fm attributesOfItemAtPath:[[self dir] stringByAppendingPathComponent:a] error:nil].fileModificationDate;
        NSDate *db = [fm attributesOfItemAtPath:[[self dir] stringByAppendingPathComponent:b] error:nil].fileModificationDate;
        return [db compare:da];
    }];
    self.files = fs;
    ADStore *st = [ADStore shared];
    self.sub.text = [NSString stringWithFormat:@"当前：收藏 %ld · 历史 %ld · 书签 %ld", (long)st.favorites.count, (long)st.history.count, (long)st.bookmarks.count];
    [self.table reloadData];
}
- (NSString *)makeBackup:(NSString *)prefix {
    [[ADStore shared] save];
    return [ADBackupController writeBackup:prefix];
}

// 自动快照:每天最多一份,只保留最近 3 份。
// 刻意不调用 [ADStore save]:快照的目的是保住"磁盘上现在的样子",如果启动时数据已经被
// 误清空,先 save 一次只会把空数据也存进快照。
+ (void)autoSnapshotIfNeeded {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd";
    NSString *today = [df stringFromDate:NSDate.date];
    if ([[ud stringForKey:@"ad_snap_day"] isEqualToString:today]) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // 磁盘上几乎没数据(全新安装/刚被清空)就不存,免得 3 份快照被空数据挤满
        NSUInteger total = 0;
        for (NSString *k in [ADBackupController keys]) total += [NSData dataWithContentsOfFile:[ADDocs() stringByAppendingPathComponent:k]].length;
        if (total < 600) { ADLogTag(@"APP", @"数据几乎为空,跳过自动快照"); return; }
        NSString *name = [ADBackupController writeBackup:@"auto"];
        [ud setObject:today forKey:@"ad_snap_day"];
        // 只清自动快照,不动用户手动存的
        NSString *dir = [ADDocs() stringByAppendingPathComponent:@"backups"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray *autos = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) if ([f hasPrefix:@"auto-"] && [f hasSuffix:@".adbak"]) [autos addObject:f];
        [autos sortUsingSelector:@selector(compare:)];          // 文件名里是时间戳,字典序即时间序
        while (autos.count > 3) { [fm removeItemAtPath:[dir stringByAppendingPathComponent:autos.firstObject] error:nil]; [autos removeObjectAtIndex:0]; }
        ADLogTag(@"APP", @"自动快照 %@(现有 %lu 份)", name, (unsigned long)autos.count);
    });
}

+ (NSString *)writeBackup:(NSString *)prefix {
    NSMutableDictionary *pack = [NSMutableDictionary dictionary];
    for (NSString *k in [ADBackupController keys]) {
        NSData *d = [NSData dataWithContentsOfFile:[ADDocs() stringByAppendingPathComponent:k]];
        if (d) pack[k] = d;
    }
    NSMutableDictionary *ud = [NSMutableDictionary dictionary];
    NSArray *udKeys = @[@"ad.rate", @"ad_playmode", @"ad_prefetch", @"ad_prefetch_wifi", @"ad_prefetch_count", @"ad_prefetch_days", @"ad_haptic", @"ad_sound",
                        [kSkipPrefix stringByAppendingString:@"_head"], [kSkipPrefix stringByAppendingString:@"_tail"]];
    for (NSString *k in udKeys) {
        id v = [NSUserDefaults.standardUserDefaults objectForKey:k]; if (v) ud[k] = v;
    }
    ADStore *st = [ADStore shared];
    NSDictionary *summary = @{@"fav": @(st.favorites.count), @"hist": @(st.history.count), @"bm": @(st.bookmarks.count)};
    NSDictionary *root = @{@"magic": @"adbak1", @"files": pack, @"defaults": ud, @"summary": summary, @"time": @([NSDate date].timeIntervalSince1970)};
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"%@-%@.adbak", prefix, [df stringFromDate:NSDate.date]];
    NSString *dir = [ADDocs() stringByAppendingPathComponent:@"backups"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [out writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
    return name;
}
- (NSDictionary *)summaryOf:(NSString *)f {
    NSData *raw = [NSData dataWithContentsOfFile:[[self dir] stringByAppendingPathComponent:f]];
    NSDictionary *root = raw ? [NSPropertyListSerialization propertyListWithData:raw options:0 format:nil error:nil] : nil;
    return [root isKindOfClass:NSDictionary.class] ? root[@"summary"] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s { return 40; }
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s {
    return ADSectionHeader(s == 0 ? @"操作" : [NSString stringWithFormat:@"已有备份（%ld）", (long)self.files.count], t.bounds.size.width);
}
- (CGFloat)tableView:(UITableView *)t heightForFooterInSection:(NSInteger)s { return 60; }
- (UIView *)tableView:(UITableView *)t viewForFooterInSection:(NSInteger)s {
    return ADSectionFooter(s == 0 ? @"包含收藏、历史、想听、置顶、播放进度、听完标记、书签和播放设置；不含 Token 与已下载的音频"
                                  : @"点一份备份进行恢复，恢复前会自动保存当前状态；左滑可分享或删除。备份文件也在「文件」App → 阅听 → backups", t.bounds.size.width);
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? 3 : MAX(1, (NSInteger)self.files.count); }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 1 && self.files.count ? 76 : 64; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADGlassRow *c = [t dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    if (ip.section == 0) {
        NSArray *n = @[@"立即备份", @"备份并分享", @"从文件导入"];
        NSArray *s = @[@"保存到本机 backups 文件夹", @"生成后发到 AirDrop、iCloud 等", @"选择一份 .adbak 文件恢复"];
        NSArray *ic = @[@"arrow.down.doc.fill", @"square.and.arrow.up.fill", @"tray.and.arrow.down.fill"];
        NSArray *col = @[[UIColor systemBlueColor], [UIColor colorWithWhite:0.38 alpha:1], [UIColor systemGreenColor]];
        [c iconNamed:ic[ip.row] color:col[ip.row]];
        c.title.text = n[ip.row]; c.sub.text = s[ip.row];
        return c;
    }
    if (!self.files.count) {
        [c iconNamed:@"clock.arrow.circlepath" color:[UIColor colorWithWhite:1 alpha:0.15]];
        c.title.text = @"还没有备份"; c.title.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        return c;
    }
    NSString *f = self.files[ip.row];
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:[[self dir] stringByAppendingPathComponent:f] error:nil];
    BOOL autoB = [f hasPrefix:@"恢复前"];
    [c iconNamed:autoB ? @"clock.arrow.circlepath" : @"archivebox.fill" color:autoB ? [UIColor systemGrayColor] : [UIColor systemIndigoColor]];
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyy-MM-dd HH:mm";
    c.title.text = [df stringFromDate:at.fileModificationDate];
    c.sub.text = [NSString stringWithFormat:@"%@ · %@", autoB ? @"恢复前自动备份" : @"手动备份", ADSize(at.fileSize)];
    NSDictionary *sm = [self summaryOf:f];
    c.note.text = sm ? [NSString stringWithFormat:@"收藏 %@ · 历史 %@ · 书签 %@", sm[@"fav"], sm[@"hist"], sm[@"bm"]] : ADRelTime(at.fileModificationDate.timeIntervalSince1970);
    c.note.textColor = [UIColor colorWithWhite:1 alpha:0.4];
    c.chev.hidden = NO;
    return c;
}
- (void)share:(NSString *)name from:(UIView *)v {
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:[[self dir] stringByAppendingPathComponent:name]]] applicationActivities:nil];
    av.popoverPresentationController.sourceView = v ?: self.view;
    [self presentViewController:av animated:YES completion:nil];
}
- (void)toast:(NSString *)msg {
    UILabel *l = [ADUtil label:nil size:15 color:UIColor.whiteColor]; l.text = msg; l.textAlignment = NSTextAlignmentCenter; l.numberOfLines = 1;
    l.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.95]; l.layer.cornerRadius = 20; l.clipsToBounds = YES;
    CGFloat w = MIN(self.view.bounds.size.width - 60, [msg sizeWithAttributes:@{NSFontAttributeName: l.font}].width + 40);
    l.frame = CGRectMake((self.view.bounds.size.width - w) / 2, self.view.bounds.size.height - 160, w, 40);
    l.alpha = 0; [self.view addSubview:l];
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic tap];
    if (ip.section == 0) {
        if (ip.row == 2) {
            UIDocumentPickerViewController *pk = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"public.item"] inMode:UIDocumentPickerModeImport];
            pk.delegate = self;
            [self presentViewController:pk animated:YES completion:nil];
            return;
        }
        NSString *n = [self makeBackup:@"阅听备份"];
        [ADHaptic success];
        [self reloadFiles];
        if (ip.row == 1) [self share:n from:[t cellForRowAtIndexPath:ip]];
        else [self toast:@"已备份"];
        return;
    }
    if (!self.files.count) return;
    NSString *f = self.files[ip.row];
    [self askRestore:f];
}
- (void)askRestore:(NSString *)f {
    NSDictionary *sm = [self summaryOf:f];
    NSString *what = sm ? [NSString stringWithFormat:@"这份备份有 收藏 %@、历史 %@、书签 %@。\n", sm[@"fav"], sm[@"hist"], sm[@"bm"]] : @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"恢复这份备份？" message:[what stringByAppendingString:@"当前的收藏、进度等会被覆盖；恢复前会自动再存一份当前状态。"] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self restore:f]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject; if (!u) return;
    BOOL acc = [u startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (acc) [u stopAccessingSecurityScopedResource];
    NSDictionary *root = d ? [NSPropertyListSerialization propertyListWithData:d options:0 format:nil error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"magic"] isEqual:@"adbak1"]) { [ADHaptic error]; [self toast:@"这不是阅听的备份文件"]; return; }
    NSString *name = u.lastPathComponent;
    if (![name hasSuffix:@".adbak"]) name = [name stringByAppendingString:@".adbak"];
    [d writeToFile:[[self dir] stringByAppendingPathComponent:name] atomically:YES];
    [self reloadFiles];
    [self askRestore:name];
}
- (void)restore:(NSString *)f {
    NSData *raw = [NSData dataWithContentsOfFile:[[self dir] stringByAppendingPathComponent:f]];
    NSDictionary *root = raw ? [NSPropertyListSerialization propertyListWithData:raw options:0 format:nil error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"magic"] isEqual:@"adbak1"]) { [ADHaptic error]; [self toast:@"这不是有效的备份文件"]; return; }
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
    [NSNotificationCenter.defaultCenter postNotificationName:@"ADContinueChanged" object:nil];
    [ADHaptic success];
    [self reloadFiles];
    [self toast:@"已恢复"];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1 || !self.files.count) return nil;
    NSString *f = self.files[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ADHaptic warning];
        [NSFileManager.defaultManager removeItemAtPath:[[self dir] stringByAppendingPathComponent:f] error:nil];
        [self reloadFiles]; done(YES);
    }];
    del.image = ADS(@"trash.fill", 15, UIImageSymbolWeightSemibold);
    UIContextualAction *sh = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES); [self share:f from:v];
    }];
    sh.backgroundColor = [UIColor systemBlueColor];
    sh.image = ADS(@"square.and.arrow.up", 15, UIImageSymbolWeightSemibold);
    return [UISwipeActionsConfiguration configurationWithActions:@[del, sh]];
}
@end
