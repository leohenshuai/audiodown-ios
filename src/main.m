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
    [[ADPlayer shared] restoreLast];
    NSLog(@"[AD] launched");
    return YES;
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    BOOL atRoot = (nav.viewControllers.count <= 1);
    [[ADNavDock shared] show:atRoot animated:animated];
}

- (void)applicationDidEnterBackground:(UIApplication *)app { [[ADStore shared] save]; }
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"AppDelegate"); }
}
