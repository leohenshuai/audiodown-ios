#import "AD.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UINavigationController *d = [[UINavigationController alloc] initWithRootViewController:[ADDiscoverController new]];
    UINavigationController *s = [[UINavigationController alloc] initWithRootViewController:[ADSearchController new]];
    UINavigationController *b = [[UINavigationController alloc] initWithRootViewController:[ADShelfController new]];

    UITabBarController *tab = [UITabBarController new];
    tab.viewControllers = @[d, s, b];
    tab.tabBar.barStyle = UIBarStyleBlack;
    tab.tabBar.tintColor = [ADUtil brand];
    tab.tabBar.unselectedItemTintColor = [ADUtil dim];
    d.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"发现" image:[UIImage systemImageNamed:@"sparkles"] tag:0];
    s.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"搜索" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];
    b.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"书架" image:[UIImage systemImageNamed:@"books.vertical"] tag:2];

    self.window.rootViewController = tab;
    self.window.backgroundColor = [ADUtil bg];
    [self.window makeKeyAndVisible];
    NSLog(@"[AD] launched");
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)app { [[ADStore shared] save]; }
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"AppDelegate"); }
}
