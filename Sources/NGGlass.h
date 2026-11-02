#import <UIKit/UIKit.h>

// GlassBackgroundView without a backdrop layer: the legacy shadow image
// under the legacy glass image, both overhanging the view by 32pt.
@interface NGGlassView : UIView
@property (nonatomic, strong) UIColor *fillColor;   // default opaque white
@property (nonatomic, readonly) UIView *contentView;
@end

typedef NS_ENUM(NSInteger, NGGlassButtonTint) {
    NGGlassButtonTintGeneric,   // panel glass, theme.buttonColor content
    NGGlassButtonTintAccent,    // accent glass, white content
};

// One navigation-bar capsule (NavigationButtonComponent in a GlassControlGroup):
// 44pt tall, text in Font.medium(17) with 12pt insets, or a 44x44 icon.
@interface NGGlassButton : UIControl
+ (instancetype)textButton:(NSString *)title target:(id)target action:(SEL)action;
+ (instancetype)iconButton:(NSString *)assetName tint:(NGGlassButtonTint)tint target:(id)target action:(SEL)action;
@property (nonatomic, copy) NSString *title;
- (CGSize)preferredSize;
@end

// NavigationBarComponent's row: left capsules, centred title, right capsules
// (12pt apart), over the fading white backdrop the bar puts behind them.
@interface NGHeaderView : UIView
@property (nonatomic, copy) NSArray *leftButtons;
@property (nonatomic, copy) NSArray *rightButtons;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIView *titleView;     // replaces the title text when set
@property (nonatomic) BOOL showsBackdrop;            // default YES; off over a chat wallpaper
+ (CGFloat)height;
@end
