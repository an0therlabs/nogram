#import "NGAppDelegate.h"
#import "NGControllers.h"
#import "NGTabBarController.h"
#import "NGTheme.h"

@implementation NGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [NGTheme applyAppearance];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    NSMutableArray *navs = [NSMutableArray array];
    for (UIViewController *root in @[ [NGContactsController new], [NGCallsController new], [NGChatListController new], [NGSettingsController new] ]) {
        [navs addObject:[[UINavigationController alloc] initWithRootViewController:root]];
    }

    // TelegramRootController's tabs: Contacts, Calls, Chats, Settings, with the
    // Lottie icons TabContacts/TabCalls/TabChats/TabSettings where frames ship.
    NGTabBarController *tabs = [NGTabBarController new];
    tabs.viewControllers = navs;
    tabs.items = @[
        [NGTabBarItem itemWithTitle:@"Контакты" imageName:@"tab_contacts" animationName:@"anim_tab_contacts"],
        [NGTabBarItem itemWithTitle:@"Звонки" imageName:@"tab_calls" animationName:@"anim_tab_calls"],
        [NGTabBarItem itemWithTitle:@"Чаты" imageName:@"tab_chats" animationName:@"anim_tab_chats"],
        [NGTabBarItem itemWithTitle:@"Настройки" imageName:@"tab_settings" animationName:@"anim_tab_settings"],
    ];
    tabs.selectedIndex = 2;

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
