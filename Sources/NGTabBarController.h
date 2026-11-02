#import <UIKit/UIKit.h>

// A port of TabBarUI's TabBarNode: Telegram's own tab bar, drawn by the app
// rather than UITabBar (whose iOS 6 look is the glossy black bar).
@interface NGTabBarItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *imageName;      // template icon from Images.xcassets
@property (nonatomic, copy) NSString *animationName;  // optional pre-rendered Lottie frames: <name>_<n>.png
@property (nonatomic, copy) NSString *badgeValue;
+ (instancetype)itemWithTitle:(NSString *)title imageName:(NSString *)imageName animationName:(NSString *)animationName;
@end

@interface NGTabBarController : UIViewController <UINavigationControllerDelegate>
@property (nonatomic, copy) NSArray *viewControllers;   // UINavigationControllers
@property (nonatomic, copy) NSArray *items;             // NGTabBarItem, one per controller
@property (nonatomic) NSUInteger selectedIndex;
- (void)setBadgeValue:(NSString *)value atIndex:(NSUInteger)index;
@end

@interface UIViewController (NGTabBar)
- (NGTabBarController *)ng_tabBarController;
@end

extern const CGFloat NGTabBarHeight;
