#import "AD.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate, UITabBarControllerDelegate, UINavigationControllerDelegate>
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

    ADDockController *tab = [ADDockController new];
    tab.viewControllers = @[d, s, b];
    tab.tabBar.hidden = YES;                       // 用自绘悬浮导航代替系统底栏
    d.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"发现" image:[UIImage systemImageNamed:@"sparkles"] tag:0];
    s.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"搜索" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];
    b.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"书架" image:[UIImage systemImageNamed:@"books.vertical"] tag:2];

    tab.delegate = self;
    for (UINavigationController *nav in @[d, s, b]) nav.delegate = self;
    __weak ADDockController *weakTab = tab;
    [ADNavDock shared].onSelect = ^(NSInteger idx) { weakTab.selectedIndex = idx; };
    [ADNavDock shared].selectedIndex = 0;
    self.window.rootViewController = tab;
    self.window.backgroundColor = [ADUtil bg];
    [self.window makeKeyAndVisible];
    NSLog(@"[AD] launched");
    return YES;
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    BOOL atRoot = (nav.viewControllers.count <= 1);
    [[ADNavDock shared] show:atRoot animated:animated];
}

- (void)tabBarController:(UITabBarController *)c didSelectViewController:(UIViewController *)v {
    static NSInteger last = 0;
    if (c.selectedIndex == last) return;
    last = c.selectedIndex;
    [ADHaptic select];
}

- (void)applicationDidEnterBackground:(UIApplication *)app { [[ADStore shared] save]; }
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"AppDelegate"); }
}
