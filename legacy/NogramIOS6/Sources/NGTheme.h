#import <UIKit/UIKit.h>

// Colours and metrics are taken from the Telegram day theme
// (submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift)
// and AvatarNode's gradient table.

#define NGHex(h) [UIColor colorWithRed:(CGFloat)(((h) >> 16) & 0xFF) / 255.0f green:(CGFloat)(((h) >> 8) & 0xFF) / 255.0f blue:(CGFloat)((h) & 0xFF) / 255.0f alpha:1.0f]
#define NGHexA(h, a) [UIColor colorWithRed:(CGFloat)(((h) >> 16) & 0xFF) / 255.0f green:(CGFloat)(((h) >> 8) & 0xFF) / 255.0f blue:(CGFloat)((h) & 0xFF) / 255.0f alpha:(a)]

@interface NGTheme : NSObject

+ (UIColor *)accentColor;
+ (UIColor *)separatorColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)blocksBackgroundColor;
+ (NSArray *)avatarColorsAtIndex:(NSInteger)index;
+ (UIColor *)nameColorAtIndex:(NSInteger)index;

+ (UIFont *)regularFont:(CGFloat)size;
+ (UIFont *)mediumFont:(CGFloat)size;
+ (UIFont *)semiboldFont:(CGFloat)size;
+ (UIFont *)boldFont:(CGFloat)size;
+ (CGFloat)pixel;

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size;

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color;
+ (UIView *)separatorView;
+ (UIView *)highlightView;

+ (void)applyAppearance;
+ (UIBarButtonItem *)barButtonWithTitle:(NSString *)title bold:(BOOL)bold target:(id)target action:(SEL)action;
+ (UIBarButtonItem *)barButtonWithAsset:(NSString *)name target:(id)target action:(SEL)action;
+ (UIBarButtonItem *)backButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
+ (void)setTitle:(NSString *)title ofBarButton:(UIBarButtonItem *)item;
+ (void)disableExtendedLayoutFor:(UIViewController *)controller;

+ (NSString *)listDateString:(NSDate *)date;
+ (NSString *)timeString:(NSDate *)date;
+ (NSString *)dayHeaderString:(NSDate *)date;
+ (BOOL)date:(NSDate *)a isSameDayAs:(NSDate *)b;

+ (CGSize)sizeOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width;
+ (CGFloat)widthOfText:(NSString *)text font:(UIFont *)font;

@end
