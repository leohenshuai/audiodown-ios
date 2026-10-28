#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <Network/Network.h>
#import <os/proc.h>

// ───────────── 系统事件监控 ─────────────
// 前台/后台、内存警告、网络变化、音频打断、路由变化、省电模式——这些都是"为什么突然没声音/没网"最常见的真凶。
@interface ADLogWatcher : NSObject
@end
static nw_path_monitor_t gMon;
static ADLogWatcher *gWatcher;
@implementation ADLogWatcher
+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        ADLogWatcher *w = [ADLogWatcher new];
        [nc addObserver:w selector:@selector(active) name:UIApplicationDidBecomeActiveNotification object:nil];
        [nc addObserver:w selector:@selector(resign) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:w selector:@selector(mem) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [nc addObserver:w selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
        [nc addObserver:w selector:@selector(interrupt:) name:AVAudioSessionInterruptionNotification object:nil];
        [nc addObserver:w selector:@selector(route:) name:AVAudioSessionRouteChangeNotification object:nil];
        [nc addObserver:w selector:@selector(power) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
        [nc addObserver:w selector:@selector(thermal) name:NSProcessInfoThermalStateDidChangeNotification object:nil];

        nw_path_monitor_t mon = nw_path_monitor_create();
        nw_path_monitor_set_queue(mon, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        __block NSString *last = nil;
        nw_path_monitor_set_update_handler(mon, ^(nw_path_t path) {
            nw_path_status_t st = nw_path_get_status(path);
            NSString *kind = nw_path_uses_interface_type(path, nw_interface_type_wifi) ? @"Wi‑Fi"
                           : nw_path_uses_interface_type(path, nw_interface_type_cellular) ? @"蜂窝"
                           : nw_path_uses_interface_type(path, nw_interface_type_wired) ? @"有线" : @"其它";
            NSString *s = st == nw_path_status_satisfied ? kind : (st == nw_path_status_unsatisfied ? @"无网络" : @"需要连接");
            if (nw_path_is_constrained(path)) s = [s stringByAppendingString:@"(低数据)"];
            if (nw_path_is_expensive(path)) s = [s stringByAppendingString:@"(计费)"];
            if ([s isEqualToString:last]) return;
            last = s;
            ADLogSetNetState(s);
            if (st == nw_path_status_satisfied) ADLogTag(@"NET", @"网络变化 → %@", s);
            else ADLogWarn(@"NET", @"网络变化 → %@", s);
        });
        nw_path_monitor_start(mon);
        gMon = mon;      // 监视器和观察者都要常驻,用静态变量持有
        gWatcher = w;
        // 活跃标记:前台活跃时存在,正常切后台/退出时删除——下次启动发现它还在,就说明上次是异常中断
        [NSFileManager.defaultManager createFileAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/logs/.active"] contents:nil attributes:nil];
    });
}
- (void)active {
    ADLogTag(@"SYS", @"回到前台 · 可用内存 %luMB", (unsigned long)(os_proc_available_memory() / 1048576));
    [NSFileManager.defaultManager createFileAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/logs/.active"] contents:nil attributes:nil];
}
- (void)resign {
    ADLogTag(@"SYS", @"进入后台");
    [NSFileManager.defaultManager removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/logs/.active"] error:nil];
}
- (void)terminate { ADLogTag(@"SYS", @"应用正常退出"); }
- (void)mem {
    ADLogWarn(@"SYS", @"⚠ 收到内存警告 · 剩余可用 %luMB(再不释放可能被系统杀掉)", (unsigned long)(os_proc_available_memory() / 1048576));
}
- (void)interrupt:(NSNotification *)n {
    NSUInteger t = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (t == AVAudioSessionInterruptionTypeBegan) {
        NSNumber *why = n.userInfo[AVAudioSessionInterruptionReasonKey];
        ADLogWarn(@"PLAY", @"音频被打断(电话/闹钟/其它 App)%@", why ? [NSString stringWithFormat:@" 原因%@", why] : @"");
    } else {
        NSUInteger o = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        ADLogTag(@"PLAY", @"音频打断结束 %@", (o & AVAudioSessionInterruptionOptionShouldResume) ? @"(系统建议恢复播放)" : @"(不建议自动恢复)");
    }
}
- (void)route:(NSNotification *)n {
    NSUInteger r = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    NSString *why = r == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ? @"设备断开(如拔耳机/蓝牙断开)"
                  : r == AVAudioSessionRouteChangeReasonNewDeviceAvailable ? @"新设备接入"
                  : r == AVAudioSessionRouteChangeReasonCategoryChange ? @"音频类别变更" : [NSString stringWithFormat:@"原因%lu", (unsigned long)r];
    AVAudioSessionPortDescription *o = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    ADLogTag(@"PLAY", @"音频路由变化:%@ → %@", why, o.portName ?: @"无");
}
- (void)power { ADLogTag(@"SYS", @"省电模式 %@", NSProcessInfo.processInfo.lowPowerModeEnabled ? @"开启" : @"关闭"); }
- (void)thermal {
    NSArray *n = @[@"正常", @"轻微发热", @"较热", @"严重发热"];
    NSInteger t = NSProcessInfo.processInfo.thermalState;
    ADLogWarn(@"SYS", @"设备温度状态 %@", t >= 0 && t < 4 ? n[t] : @"?");
}
@end

void ADLogStartWatching(void) { [ADLogWatcher install]; }

// ───────────── 日志页 ─────────────
@interface ADLogCell : UITableViewCell
@property (nonatomic, strong) UILabel *line;
@end
@implementation ADLogCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _line = [UILabel new];
        _line.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        _line.numberOfLines = 0;
        [self.contentView addSubview:_line];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.line.frame = CGRectMake(12, 2, self.contentView.bounds.size.width - 24, self.contentView.bounds.size.height - 4);
}
@end

@interface ADLogController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSString *> *all, *shown;
@property (nonatomic, strong) UIButton *back, *share, *more, *bottom;
@property (nonatomic, strong) UILabel *head, *sub;
@property (nonatomic, strong) UISegmentedControl *tag;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, assign) BOOL follow, onlyErr;
@property (nonatomic, assign) uint64_t seenVer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *hCache;
@property (nonatomic, assign) CGFloat hCacheW;
@end

@implementation ADLogController

static NSArray *kTags(void) { return @[@"全部", @"NET", @"PLAY", @"DL", @"SYS"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.follow = YES;
    self.hCache = [NSMutableDictionary dictionary];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.table.contentInset = UIEdgeInsetsMake(4, 0, 90, 0);
    [self.view addSubview:self.table];

    self.back = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.back radius:22];
    self.back.tintColor = UIColor.whiteColor;
    [self.back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.back];

    self.head = [ADUtil label:@"PingFangSC-Semibold" size:30 color:UIColor.whiteColor];
    self.head.text = @"运行日志";
    [self.view addSubview:self.head];
    self.sub = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
    [self.view addSubview:self.sub];

    self.more = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.more radius:18];
    self.more.tintColor = UIColor.whiteColor;
    [self.more setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    [self.more addTarget:self action:@selector(showMore) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.more];

    self.tag = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"网络", @"播放", @"下载", @"系统"]];
    self.tag.selectedSegmentIndex = 0;
    [self.tag setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]} forState:UIControlStateNormal];
    [self.tag setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.blackColor, NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]} forState:UIControlStateSelected];
    self.tag.selectedSegmentTintColor = UIColor.whiteColor;
    self.tag.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.tag addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.tag];

    self.search = [UISearchBar new];
    self.search.delegate = self;
    self.search.placeholder = @"搜索日志(如 ✗、HTTP、第12集)";
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.barStyle = UIBarStyleBlack;
    self.search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.search];

    self.share = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.share setTitle:@"导出并分享" forState:UIControlStateNormal];
    self.share.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.share.tintColor = UIColor.whiteColor;
    self.share.backgroundColor = [ADUtil brand];
    self.share.layer.cornerRadius = 20;
    [self.share addTarget:self action:@selector(doShare) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.share];

    self.bottom = [UIButton buttonWithType:UIButtonTypeSystem];
    [ADLiquid glassButton:self.bottom radius:18];
    self.bottom.tintColor = UIColor.whiteColor;
    [self.bottom setImage:[UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    [self.bottom addTarget:self action:@selector(jumpBottom) forControlEvents:UIControlEventTouchUpInside];
    self.bottom.hidden = YES;
    [self.view addSubview:self.bottom];

    [self refresh:YES];
    __weak typeof(self) w = self;
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        __strong typeof(w) self = w; if (!self) return;
        if (ADLogVersion() != self.seenVer) [self refresh:NO];   // 没有新日志就不动,省电
    }];
}

- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.navigationController.navigationBar.hidden = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.navigationController.viewControllers.count > 1; }
- (void)viewWillDisappear:(BOOL)a {
    [super viewWillDisappear:a];
    if (self.isMovingFromParentViewController) {
        [self.ticker invalidate]; self.ticker = nil;
        self.navigationController.navigationBar.hidden = NO;
    }
}
- (void)dealloc { [self.ticker invalidate]; }
- (void)goBack { [ADHaptic tap]; [self.navigationController popViewControllerAnimated:YES]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = MAX(self.view.safeAreaInsets.top, 47);
    self.back.frame = CGRectMake(16, top + 2, 44, 44);
    self.more.frame = CGRectMake(W - 16 - 36, top + 6, 36, 36);
    self.head.frame = CGRectMake(72, top + 6, W - 72 - 60, 38);
    self.sub.frame = CGRectMake(20, top + 52, W - 40, 16);
    self.tag.frame = CGRectMake(16, top + 76, W - 32, 32);
    self.search.frame = CGRectMake(8, top + 112, W - 16, 44);
    CGFloat ty = top + 160;
    CGFloat bot = MAX(self.view.safeAreaInsets.bottom, 12);
    self.table.frame = CGRectMake(0, ty, W, H - ty);
    self.share.frame = CGRectMake(20, H - bot - 48, W - 40, 40);
    self.bottom.frame = CGRectMake(W - 16 - 36, H - bot - 48 - 48, 36, 36);
    if (fabs(self.hCacheW - W) > 1) { self.hCacheW = W; [self.hCache removeAllObjects]; }
}

// ── 数据 ──
- (void)filterChanged { [ADHaptic select]; [self.hCache removeAllObjects]; [self refresh:YES]; }
- (void)searchBar:(UISearchBar *)b textDidChange:(NSString *)t { [self.hCache removeAllObjects]; [self refresh:YES]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)b { [b resignFirstResponder]; }

- (BOOL)keep:(NSString *)l {
    // 行格式固定: "MM-dd HH:mm:ss.SSS L TAG  消息"(前 18 位是时间,第 19 位是级别,20~24 位是标签)
    NSInteger ti = self.tag.selectedSegmentIndex;
    if (ti > 0 && l.length > 24) {
        NSString *t = [[l substringWithRange:NSMakeRange(20, MIN(4, l.length - 20))] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![t isEqualToString:kTags()[ti]]) return NO;
    } else if (ti > 0) return NO;
    if (self.onlyErr) {
        if (l.length < 20) return NO;
        unichar lv = [l characterAtIndex:19];
        if (lv != 'E' && lv != 'W') return NO;
    }
    NSString *q = self.search.text;
    if (q.length && [l rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) return NO;
    return YES;
}

- (void)refresh:(BOOL)force {
    self.seenVer = ADLogVersion();
    self.all = ADLogLines();
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger errs = 0;
    for (NSString *l in self.all) {
        if (l.length > 19) { unichar lv = [l characterAtIndex:19]; if (lv == 'E') errs++; }
        if ([self keep:l]) [out addObject:l];
    }
    CGFloat prevOff = self.table.contentOffset.y;
    CGFloat prevH = self.table.contentSize.height;
    BOOL wasFollow = self.follow;
    self.shown = out;
    [self.table reloadData];
    NSString *net = ADLogNetState();
    self.sub.text = [NSString stringWithFormat:@"%lu 行 · 错误 %lu · 网络 %@%@", (unsigned long)self.all.count, (unsigned long)errs, net, ADLogLastRunAbnormal() ? @" · 上次异常退出" : @""];
    self.sub.textColor = ADLogLastRunAbnormal() ? [UIColor colorWithRed:1 green:0.6 blue:0.3 alpha:1] : [UIColor colorWithWhite:1 alpha:0.5];
    if (self.shown.count == 0) return;
    if (wasFollow || force) [self scrollToEnd:NO];
    else if (prevH > 0) self.table.contentOffset = CGPointMake(0, prevOff);   // 手动往回翻时位置不动
}

- (void)scrollToEnd:(BOOL)anim {
    if (!self.shown.count) return;
    [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.shown.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:anim];
}
- (void)jumpBottom { [ADHaptic tap]; self.follow = YES; self.bottom.hidden = YES; [self scrollToEnd:YES]; }

// ── 滚动:往回翻自动暂停跟随,翻回底部再恢复 ──
- (void)scrollViewDidScroll:(UIScrollView *)s {
    CGFloat dist = s.contentSize.height - (s.contentOffset.y + s.bounds.size.height - s.contentInset.bottom);
    if (s.isTracking || s.isDragging || s.isDecelerating) {
        self.follow = dist < 40;
        self.bottom.hidden = self.follow;
    }
}

// ── 列表 ──
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.shown.count; }

- (NSAttributedString *)styled:(NSString *)l {
    UIFont *f = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    UIColor *base = [UIColor colorWithWhite:1 alpha:0.78], *dim = [UIColor colorWithWhite:1 alpha:0.38];
    unichar lv = l.length > 19 ? [l characterAtIndex:19] : 'I';
    UIColor *body = lv == 'E' ? [UIColor colorWithRed:1 green:0.45 blue:0.42 alpha:1]
                  : lv == 'W' ? [UIColor colorWithRed:1 green:0.78 blue:0.35 alpha:1] : base;
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:l attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: body}];
    if (l.length > 25) {
        [a addAttribute:NSForegroundColorAttributeName value:dim range:NSMakeRange(0, 18)];               // 时间灰一点
        UIColor *tc = base; NSString *t = [[l substringWithRange:NSMakeRange(20, 4)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([t isEqualToString:@"NET"]) tc = [UIColor colorWithRed:0.45 green:0.75 blue:1 alpha:1];
        else if ([t isEqualToString:@"PLAY"]) tc = [UIColor colorWithRed:0.55 green:0.9 blue:0.6 alpha:1];
        else if ([t isEqualToString:@"DL"]) tc = [UIColor colorWithRed:0.8 green:0.65 blue:1 alpha:1];
        else if ([t isEqualToString:@"SYS"]) tc = [UIColor colorWithRed:0.95 green:0.8 blue:0.5 alpha:1];
        [a addAttribute:NSForegroundColorAttributeName value:tc range:NSMakeRange(20, 4)];
        [a addAttribute:NSFontAttributeName value:[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold] range:NSMakeRange(20, 4)];
    }
    NSString *q = self.search.text;
    if (q.length) {
        NSRange r = NSMakeRange(0, l.length);
        while (r.location < l.length) {
            NSRange f2 = [l rangeOfString:q options:NSCaseInsensitiveSearch range:r];
            if (f2.location == NSNotFound) break;
            [a addAttribute:NSBackgroundColorAttributeName value:[[ADUtil brand] colorWithAlphaComponent:0.45] range:f2];
            r = NSMakeRange(NSMaxRange(f2), l.length - NSMaxRange(f2));
        }
    }
    return a;
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *s = self.shown[ip.row];
    NSNumber *c = self.hCache[@(s.hash)];
    if (c) return c.doubleValue;
    CGFloat W = t.bounds.size.width - 24;
    CGFloat h = [s boundingRectWithSize:CGSizeMake(W, 800) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular]} context:nil].size.height;
    h = MAX(16, ceil(h) + 4);
    self.hCache[@(s.hash)] = @(h);
    if (self.hCache.count > 4000) [self.hCache removeAllObjects];
    return h;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADLogCell *c = [t dequeueReusableCellWithIdentifier:@"log"];
    if (!c) c = [[ADLogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"log"];
    c.line.attributedText = [self styled:self.shown[ip.row]];
    return c;
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)t contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)p {
    NSString *line = self.shown[ip.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        return [UIMenu menuWithChildren:@[[UIAction actionWithTitle:@"复制这行" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *a) {
            UIPasteboard.generalPasteboard.string = line; [ADHaptic success];
        }]]];
    }];
}

// ── 操作 ──
- (void)doShare {
    [ADHaptic tap];
    NSString *path = ADLogExportPath();
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.share;
    vc.popoverPresentationController.sourceRect = self.share.bounds;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)showMore {
    [ADHaptic tap];
    NSArray *opts = @[self.onlyErr ? @"✓ 只看警告和错误" : @"只看警告和错误", @"复制当前显示的全部", @"清空日志"];
    [ADOptionSheet showIn:self title:@"运行日志" options:opts destructive:2 choose:^(NSInteger i) {
        if (i == 0) { self.onlyErr = !self.onlyErr; [self.hCache removeAllObjects]; [self refresh:YES]; }
        else if (i == 1) { UIPasteboard.generalPasteboard.string = [self.shown componentsJoinedByString:@"\n"]; [ADHaptic success]; }
        else {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空日志?" message:@"只删除本机的运行日志(含上一份),不影响其它数据。" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { ADLogClear(); [self.hCache removeAllObjects]; [self refresh:YES]; }]];
            [self presentViewController:a animated:YES completion:nil];
        }
    }];
}
@end
