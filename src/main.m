#import "AD.h"
#import "ADInternal.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    ADShelfController *shelf = [ADShelfController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:shelf];

    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:[ADSettingsController new]];

    UITabBarController *tab = [UITabBarController new];
    tab.viewControllers = @[nav, settingsNav];
    tab.tabBar.barStyle = UIBarStyleBlack;
    tab.tabBar.tintColor = [ADUtil brand];
    tab.tabBar.unselectedItemTintColor = [ADUtil dim];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"书架" image:[UIImage systemImageNamed:@"books.vertical"] tag:0];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"gearshape"] tag:1];

    self.window.rootViewController = tab;
    self.window.backgroundColor = [ADUtil bg];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)app {
    [[ADStore shared] save];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
