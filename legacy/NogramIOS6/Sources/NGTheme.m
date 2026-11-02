#import "NGTheme.h"
#import "NGOriginal.h"
#import <QuartzCore/QuartzCore.h>

@implementation NGTheme

#pragma mark - Colours

+ (UIColor *)accentColor { return NGHex(0x0088ff); }
+ (UIColor *)separatorColor { return NGHex(0xc8c7cc); }
+ (UIColor *)secondaryTextColor { return NGHex(0x8e8e93); }
+ (UIColor *)blocksBackgroundColor { return NGHex(0xefeff4); }

+ (NSArray *)avatarColorsAtIndex:(NSInteger)index {
    static const unsigned int table[7][2] = {
        { 0xff516a, 0xff885e },
        { 0xffa85c, 0xffcd6a },
        { 0x665fff, 0x82b1ff },
        { 0x54cb68, 0xa0de7e },
        { 0x4acccd, 0x00fcfd },
        { 0x2a9ef1, 0x72d5fd },
        { 0xd669ed, 0xe0a2f3 },
    };
    NSInteger i = ((index % 7) + 7) % 7;
    return @[ NGHex(table[i][0]), NGHex(table[i][1]) ];
}

+ (UIColor *)nameColorAtIndex:(NSInteger)index {
    static const unsigned int table[7] = { 0xcc5049, 0xd67722, 0x955cdb, 0x40a920, 0x309eba, 0x368ad1, 0xc7508b };
    return NGHex(table[((index % 7) + 7) % 7]);
}

#pragma mark - Fonts

+ (UIFont *)regularFont:(CGFloat)size { return [UIFont systemFontOfSize:size]; }

+ (UIFont *)mediumFont:(CGFloat)size {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    }
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
    return font ?: [UIFont boldSystemFontOfSize:size];
}

+ (UIFont *)semiboldFont:(CGFloat)size {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    }
    return [self mediumFont:size];
}

+ (UIFont *)boldFont:(CGFloat)size { return [UIFont boldSystemFontOfSize:size]; }

+ (CGFloat)pixel { return 1.0f / [UIScreen mainScreen].scale; }

#pragma mark - Images

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)barBackgroundWithHeight:(CGFloat)height lineAtTop:(BOOL)top {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, height), YES, 0);
    [NGHex(0xf7f7f7) setFill];
    UIRectFill(CGRectMake(0, 0, 1, height));
    [NGHex(0xb2b2b2) setFill];
    CGFloat px = [self pixel];
    UIRectFill(CGRectMake(0, top ? 0 : height - px, 1, px));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Views

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    return label;
}

+ (UIView *)separatorView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [self separatorColor];
    return view;
}

+ (UIView *)highlightView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = NGHex(0xe5e5ea);
    return view;
}

#pragma mark - Bars

+ (void)applyAppearance {
    NSValue *noOffset = [NSValue valueWithUIOffset:UIOffsetZero];

    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:[self barBackgroundWithHeight:44 lineAtTop:NO] forBarMetrics:UIBarMetricsDefault];
    if ([nav respondsToSelector:@selector(setShadowImage:)]) {
        [nav setShadowImage:[UIImage new]];
    }
    [nav setTitleTextAttributes:@{
        UITextAttributeTextColor: [UIColor blackColor],
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self semiboldFont:17],
    }];

    // The tab bar is NGTabBarController's own; UITabBar is not used.
    UITabBar *tab = [UITabBar appearance];
    [tab setBackgroundImage:[self barBackgroundWithHeight:49 lineAtTop:YES]];
    [tab setSelectionIndicatorImage:[self imageWithColor:[UIColor clearColor] size:CGSizeMake(1, 1)]];
    if ([tab respondsToSelector:@selector(setShadowImage:)]) {
        [tab setShadowImage:[UIImage new]];
    }

    UITabBarItem *item = [UITabBarItem appearance];
    [item setTitleTextAttributes:@{
        UITextAttributeTextColor: NGHex(0x959595),
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self mediumFont:10],
    } forState:UIControlStateNormal];
    [item setTitleTextAttributes:@{
        UITextAttributeTextColor: [self accentColor],
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self mediumFont:10],
    } forState:UIControlStateSelected];
}

+ (UIButton *)barButtonBase {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitleColor:[self accentColor] forState:UIControlStateNormal];
    [button setTitleColor:[[self accentColor] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
    button.titleLabel.font = [self regularFont:17];
    button.showsTouchWhenHighlighted = NO;
    return button;
}

+ (UIBarButtonItem *)barButtonWithTitle:(NSString *)title bold:(BOOL)bold target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    if (bold) button.titleLabel.font = [self mediumFont:17];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    [self setTitle:title ofBarButton:item];
    return item;
}

+ (void)setTitle:(NSString *)title ofBarButton:(UIBarButtonItem *)item {
    UIButton *button = (UIButton *)item.customView;
    [button setTitle:title forState:UIControlStateNormal];
    CGFloat width = [self widthOfText:title font:button.titleLabel.font];
    button.frame = CGRectMake(0, 0, MAX(44, width + 4), 44);
}

+ (UIBarButtonItem *)barButtonWithAsset:(NSString *)name target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    [button setImage:NGTintedAsset(name, [self accentColor]) forState:UIControlStateNormal];
    [button setImage:NGTintedAsset(name, [[self accentColor] colorWithAlphaComponent:0.4f]) forState:UIControlStateHighlighted];
    button.frame = CGRectMake(0, 0, 44, 44);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

+ (UIBarButtonItem *)backButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    [button setImage:NGTintedAsset(@"nav_back", [self accentColor]) forState:UIControlStateNormal];
    [button setImage:NGTintedAsset(@"nav_back", [[self accentColor] colorWithAlphaComponent:0.4f]) forState:UIControlStateHighlighted];
    [button setTitle:title forState:UIControlStateNormal];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, -10, 0, 0);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 3);
    CGFloat width = [self widthOfText:title font:button.titleLabel.font];
    button.frame = CGRectMake(0, 0, MIN(130, width + 26), 44);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

+ (void)disableExtendedLayoutFor:(UIViewController *)controller {
    if ([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        controller.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

#pragma mark - Dates

static NSDateFormatter *NGFormatter(NSString *format) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSDateFormatter *formatter = cache[format];
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
        formatter.dateFormat = format;
        cache[format] = formatter;
    }
    return formatter;
}

static NSDate *NGDayStart(NSDate *date) {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
    return [calendar dateFromComponents:parts];
}

static NSInteger NGDaysAgo(NSDate *date) {
    NSTimeInterval delta = [NGDayStart([NSDate date]) timeIntervalSinceDate:NGDayStart(date)];
    return (NSInteger)floor(delta / 86400.0 + 0.5);
}

+ (BOOL)date:(NSDate *)a isSameDayAs:(NSDate *)b {
    return [NGDayStart(a) isEqualToDate:NGDayStart(b)];
}

+ (NSString *)timeString:(NSDate *)date {
    return [NGFormatter(@"HH:mm") stringFromDate:date];
}

+ (NSString *)listDateString:(NSDate *)date {
    NSInteger days = NGDaysAgo(date);
    if (days <= 0) return [self timeString:date];
    if (days < 7) return [NGFormatter(@"EE") stringFromDate:date];
    return [NGFormatter(@"dd.MM.yy") stringFromDate:date];
}

+ (NSString *)dayHeaderString:(NSDate *)date {
    NSInteger days = NGDaysAgo(date);
    if (days <= 0) return @"Сегодня";
    if (days == 1) return @"Вчера";
    return [NGFormatter(@"d MMMM") stringFromDate:date];
}

#pragma mark - Text

+ (CGSize)sizeOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    CGSize size = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, 100000) lineBreakMode:NSLineBreakByWordWrapping];
    return CGSizeMake(ceilf(size.width), ceilf(size.height));
}

+ (CGFloat)widthOfText:(NSString *)text font:(UIFont *)font {
    return ceilf([text sizeWithFont:font].width);
}

@end
