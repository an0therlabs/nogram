#import "NGAppDelegate.h"
#import "NGControllers.h"
#import "NGTheme.h"

@implementation NGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [NGTheme applyAppearance];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    NSMutableArray *tabs = [NSMutableArray array];
    for (UIViewController *root in @[ [NGContactsController new], [NGCallsController new], [NGChatListController new], [NGSettingsController new] ]) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
        nav.tabBarItem = root.tabBarItem;
        [tabs addObject:nav];
    }
    UITabBarController *tabBar = [UITabBarController new];
    tabBar.viewControllers = tabs;
    tabBar.selectedIndex = 2;

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
