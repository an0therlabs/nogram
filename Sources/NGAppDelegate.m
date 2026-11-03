#import "NGAppDelegate.h"
#import "NGControllers.h"
#import "NGTabBarController.h"
#import "NGTheme.h"
#import "NGTelegram.h"
#import "NGLogin.h"
#import "NGModel.h"

@implementation NGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [NGTheme applyAppearance];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionEnded) name:NGTelegramSessionEndedNotification object:nil];
    if ([NGTelegram shared].isAuthorized) {
        [self showMain];
    } else {
        [self showLogin];
    }
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showLogin {
    __weak NGAppDelegate *weakSelf = self;
    self.window.rootViewController = NGLoginScreen(^{ [weakSelf showMain]; });
}

// The server ended the session (it was terminated from another device, or
// the key was revoked): stop everything and go back to the login screen.
- (void)sessionEnded {
    [self showLogin];
    [[[UIAlertView alloc] initWithTitle:@"Сеанс завершён"
                                message:@"Telegram завершил этот сеанс. Войдите снова."
                               delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

// The signed-in account's name and phone replace the demo profile; the chat
// list is still the demo data until the dialogs are loaded from the server.
- (void)showMain {
    NSDictionary *user = [NGTelegram shared].currentUser;
    if (user) {
        NGUser *me = [NGDemoData shared].me;
        me.firstName = user[@"first_name"] ?: @"";
        me.lastName = user[@"last_name"] ?: @"";
        if ([user[@"phone"] length]) me.phone = [@"+" stringByAppendingString:user[@"phone"]];
        me.username = user[@"username"] ?: @"";
    }
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
}
@end
