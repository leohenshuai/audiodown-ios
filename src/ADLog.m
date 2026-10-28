#import "AD.h"
#import <ImageIO/ImageIO.h>

// 运行日志:写 Documents/logs/app.log,内存里留最近 800 行供界面直接看。
// 目的很单一——出问题时能拿到"那一刻经历了什么",所以只记状态变化和网络往返,不当调试器用。

static NSLock *gLock;
static NSMutableArray<NSString *> *gLines;
static NSString *gPath;
static BOOL gReady;
static NSFileHandle *gFile;
static unsigned long long gSize;

static void ADLogSetup(void) {
    if (gReady) return;
    gReady = YES;
    gLock = [NSLock new];
    gLines = [NSMutableArray array];
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    gPath = [dir stringByAppendingPathComponent:@"app.log"];
    // 上次的日志留一份,方便出问题后翻上一次
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *old = [dir stringByAppendingPathComponent:@"app.prev.log"];
    unsigned long long sz = [NSFileManager.defaultManager attributesOfItemAtPath:gPath error:nil].fileSize;
    if (sz > 1024 * 1024) {
        [NSFileManager.defaultManager removeItemAtPath:old error:nil];
        [NSFileManager.defaultManager moveItemAtPath:gPath toPath:old error:nil];
        sz = 0;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:gPath]) [NSFileManager.defaultManager createFileAtPath:gPath contents:nil attributes:nil];
    gFile = [NSFileHandle fileHandleForWritingAtPath:gPath];
    [gFile seekToEndOfFile];
    gSize = sz;
    NSData *data = [NSData dataWithContentsOfFile:gPath];
    if (data.length) {
        NSString *all = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        for (NSString *l in [all componentsSeparatedByString:@"\n"]) if (l.length) [gLines addObject:l];
        while (gLines.count > 800) [gLines removeObjectAtIndex:0];
    }
}

void ADLog(NSString *fmt, ...) {
    if (!fmt.length) return;
    ADLogSetup();
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@", [df stringFromDate:[NSDate date]], msg];
    [gLock lock];
    [gLines addObject:line];
    while (gLines.count > 800) [gLines removeObjectAtIndex:0];
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    @try { [gFile writeData:d]; gSize += d.length; } @catch (NSException *e) { gFile = nil; }
    [gLock unlock];
    NSLog(@"[AD] %@", line);
}

NSString *ADLogTail(NSUInteger n) {
    ADLogSetup();
    [gLock lock];
    NSUInteger cnt = MIN(n, gLines.count);
    NSArray *out = [gLines subarrayWithRange:NSMakeRange(gLines.count - cnt, cnt)];
    [gLock unlock];
    return [out componentsJoinedByString:@"\n"];
}

// 崩溃/信号也落进同一个文件:下次打开就能看到死在哪
static void ADLogSignal(int sig) {
    ADLog(@"✗✗✗ 收到信号 %d,进程即将退出", sig);
    signal(sig, SIG_DFL);
    raise(sig);
}

void ADLogExceptionHandler(NSException *e) {
    ADLog(@"✗✗✗ 未捕获异常 %@: %@\n%@", e.name, e.reason, [e.callStackSymbols componentsJoinedByString:@"\n"]);
}

void ADLogInstallCrashHandler(void) {
    ADLogSetup();
    NSSetUncaughtExceptionHandler(&ADLogExceptionHandler);
    for (int i = 0; i < 5; i++) {
        int sigs[] = {SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS};
        signal(sigs[i], ADLogSignal);
    }
}

NSString *ADLogFilePath(void) {
    ADLogSetup();
    return gPath;
}

void ADLogClear(void) {
    ADLogSetup();
    [gLock lock];
    [gLines removeAllObjects];
    [gFile closeFile];
    [NSFileManager.defaultManager removeItemAtPath:gPath error:nil];
    [NSFileManager.defaultManager createFileAtPath:gPath contents:nil attributes:nil];
    gFile = [NSFileHandle fileHandleForWritingAtPath:gPath];
    gSize = 0;
    [gLock unlock];
}

// ───────────── 日志页 ─────────────
@interface ADLogCell : UITableViewCell
@property (nonatomic, strong) UILabel *line;
@end
@implementation ADLogCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:r])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _line = [ADUtil label:nil size:10.5 color:[UIColor colorWithWhite:1 alpha:0.78]];
        _line.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
        _line.numberOfLines = 0;
        [self.contentView addSubview:_line];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.line.frame = CGRectMake(14, 3, self.contentView.bounds.size.width - 28, self.contentView.bounds.size.height - 6);
}
@end

@interface ADLogController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSString *> *lines;
@property (nonatomic, strong) UIButton *share;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, assign) BOOL autoScroll;
@end

@implementation ADLogController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.title = @"运行日志";
    self.autoScroll = YES;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.contentInset = UIEdgeInsetsMake(8, 0, 120, 0);
    [self.view addSubview:self.table];

    self.share = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.share setTitle:@"分享" forState:UIControlStateNormal];
    self.share.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.share.tintColor = UIColor.whiteColor;
    self.share.backgroundColor = [[ADUtil brand] colorWithAlphaComponent:0.9];
    self.share.layer.cornerRadius = 18;
    [self.share addTarget:self action:@selector(doShare) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.share];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"清空" forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    clear.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    [clear addTarget:self action:@selector(doClear) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:clear];

    [self reload];
    // 日志是活的:每 1.5 秒刷一次,停在底部时自动跟随
    __weak typeof(self) w = self;
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
        __strong typeof(w) self = w; if (!self) return;
        if (!self.autoScroll) return;
        [self reload];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.ticker invalidate]; self.ticker = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = MAX(self.view.safeAreaInsets.top, 20);
    self.table.frame = CGRectMake(0, top + 44, W, H - top - 44);
    self.share.frame = CGRectMake(20, H - MAX(self.view.safeAreaInsets.bottom, 16) - 52, W - 40, 40);
}

- (void)reload {
    self.lines = [ADLogTail(600) componentsSeparatedByString:@"\n"];
    [self.table reloadData];
    NSInteger n = (NSInteger)self.lines.count;
    if (n > 0) [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}

- (void)doShare {
    NSString *path = ADLogFilePath();
    NSURL *u = [NSURL fileURLWithPath:path];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[u] applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.share;
    vc.popoverPresentationController.sourceRect = self.share.bounds;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)doClear {
    [ADHaptic warning];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空日志" message:@"只会删除本机的运行日志，不影响其它数据。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        ADLogClear();
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.lines.count; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *s = self.lines[ip.row];
    CGFloat W = t.bounds.size.width - 28;
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular]};
    CGFloat h = [s boundingRectWithSize:CGSizeMake(W, 400) options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs context:nil].size.height;
    return MAX(18, h + 6);
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    ADLogCell *c = [t dequeueReusableCellWithIdentifier:@"log"];
    if (!c) c = [[ADLogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"log"];
    NSString *s = self.lines[ip.row];
    c.line.text = s;
    // 错误行标红一点,一眼能找到
    BOOL bad = [s containsString:@"✗"] || [s containsString:@"FAIL"] || [s containsString:@"失败"];
    c.line.textColor = bad ? [UIColor colorWithRed:1 green:0.45 blue:0.42 alpha:1] : [UIColor colorWithWhite:1 alpha:0.78];
    return c;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)s {
    // 用户手动往回翻的时候别再自动跳到底部
    self.autoScroll = NO;
    __weak typeof(self) w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(w) self = w; if (!self) return;
        self.autoScroll = YES;
    });
}
@end
