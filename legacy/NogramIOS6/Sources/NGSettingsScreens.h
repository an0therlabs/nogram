#import <UIKit/UIKit.h>

// The screens behind the settings rows, each listing the entries of its
// Swift controller in order (SettingsUI/Sources/...). Values are local: the
// demo has no server, so nothing here is sent anywhere.
UIViewController *NGProfileScreen(void);
UIViewController *NGRecentCallsScreen(void);
UIViewController *NGDevicesScreen(void);
UIViewController *NGChatFoldersScreen(void);
UIViewController *NGNotificationsScreen(void);
UIViewController *NGPrivacyScreen(void);
UIViewController *NGDataAndStorageScreen(void);
UIViewController *NGAppearanceScreen(void);
UIViewController *NGPowerSavingScreen(void);
UIViewController *NGLanguageScreen(void);
UIViewController *NGSupportScreen(NSString *title);
