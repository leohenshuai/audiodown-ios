#import "AD.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate, UITabBarControllerDelegate>
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

    UITabBarController *tab = [UITabBarController new];
    tab.viewControllers = @[d, s, b];
    tab.tabBar.barStyle = UIBarStyleBlack;
    tab.tabBar.tintColor = [ADUtil brand];
    tab.tabBar.unselectedItemTintColor = [ADUtil dim];
    // 修：从搜索结果进专辑再返回后，标签栏变成透明（滚动边缘样式）
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *ap = [UITabBarAppearance new];
        [ap configureWithDefaultBackground];
        ap.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        tab.tabBar.standardAppearance = ap;
        if (@available(iOS 15.0, *)) tab.tabBar.scrollEdgeAppearance = ap;
    }
    d.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"发现" image:[UIImage systemImageNamed:@"sparkles"] tag:0];
    s.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"搜索" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];
    b.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"书架" image:[UIImage systemImageNamed:@"books.vertical"] tag:2];

    tab.delegate = self;
    self.window.rootViewController = tab;
    self.window.backgroundColor = [ADUtil bg];
    [self.window makeKeyAndVisible];
    NSLog(@"[AD] launched");
    return YES;
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
