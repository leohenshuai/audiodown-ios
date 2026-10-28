#import "AD.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"ad_prefetch": @NO,
                                                            @"ad_prefetch_wifi": @YES,
                                                            @"ad_prefetch_count": @2,
                                                            @"ad_prefetch_days": @3,
                                                            @"ad_haptic": @YES,
                                                            @"ad_sound": @YES}];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UINavigationController *d = [[UINavigationController alloc] initWithRootViewController:[ADDiscoverController new]];
    UINavigationController *s = [[UINavigationController alloc] initWithRootViewController:[ADSearchController new]];
    UINavigationController *b = [[UINavigationController alloc] initWithRootViewController:[ADShelfController new]];

    UINavigationController *g = [[UINavigationController alloc] initWithRootViewController:[ADSettingsController new]];

    ADDockController *host = [ADDockController new];
    host.pages = @[d, s, b, g];
    for (UINavigationController *nav in @[d, s, b, g]) nav.delegate = self;
    self.window.rootViewController = host;
    self.window.backgroundColor = [ADUtil bg];
    [self.window makeKeyAndVisible];
    NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *bd = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    ADLogTag(@"SYS", @"──── 启动 阅听 %@ (%@) iOS %@ %@ ────", v, bd, UIDevice.currentDevice.systemVersion, ADLogLastRunAbnormal() ? @"· 上次异常退出" : @"");
    ADLogStartWatching();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ADBackupController autoSnapshotIfNeeded]; });
    [[ADPlayer shared] restoreLast];
    [ADUpdater backgroundCheck];
    NSLog(@"[AD] launched");
    return YES;
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    BOOL atRoot = (nav.viewControllers.count <= 1);
    [[ADNavDock shared] show:atRoot animated:animated];
}

- (void)applicationDidEnterBackground:(UIApplication *)app { [[ADStore shared] save]; }

// 应用被杀或挂起后,后台下载仍在继续;有下载完成时系统会拉起应用走这里。
// 必须马上重建同名会话(取 shared 即可),系统才会把完成事件交给下载器。
- (void)application:(UIApplication *)app handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))handler {
    ADLogTag(@"DL", @"被后台下载唤醒 %@", identifier);
    ADDownloader *d = [ADDownloader shared];
    d.bgCompletion = handler;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        ADLogInstallCrashHandler();     // 崩溃/信号也写进运行日志
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
