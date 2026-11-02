#import <UIKit/UIKit.h>
#import "NGControllers.h"

// ItemListUI in the glass system style (ItemListDisclosureItem,
// ItemListSwitchItem, ItemListCheckboxItem, ItemListActionItem,
// ItemListSectionHeaderItem, ItemListTextItem), in the inset white cards of
// PresentationResourcesItemList.cornersImage(glass: true).

typedef NS_ENUM(NSInteger, NGItemKind) {
    NGItemKindHeader,       // section header, Font.regular(13), sectionHeaderTextColor
    NGItemKindFooter,       // ItemListTextItem under a block
    NGItemKindDisclosure,   // title, optional icon, label, arrow
    NGItemKindSwitch,
    NGItemKindCheck,        // one of a group, checkmark on the right
    NGItemKindAction,       // accent title
    NGItemKindDestructive,  // destructive title
    NGItemKindInfo,         // title over a secondary subtitle, no arrow
    NGItemKindSlider,
    NGItemKindCustom,       // a view supplied by the screen
};

@interface NGItem : NSObject
@property (nonatomic) NGItemKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;     // label, or the subtitle of a check/info row
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *iconColor;
@property (nonatomic) BOOL on;                     // switch value, or the selected check
@property (nonatomic) BOOL disabled;
@property (nonatomic) float value;                 // slider
@property (nonatomic, copy) NSString *group;       // checks sharing a group are exclusive
@property (nonatomic, strong) UIView *customView;
@property (nonatomic, copy) UIViewController *(^destination)(void);
@property (nonatomic, copy) void (^action)(NGItem *item);

+ (instancetype)header:(NSString *)text;
+ (instancetype)footer:(NSString *)text;
+ (instancetype)disclosure:(NSString *)title detail:(NSString *)detail;
+ (instancetype)disclosure:(NSString *)title detail:(NSString *)detail icon:(NSString *)icon color:(UIColor *)color;
+ (instancetype)toggle:(NSString *)title on:(BOOL)on;
+ (instancetype)check:(NSString *)title subtitle:(NSString *)subtitle group:(NSString *)group selected:(BOOL)selected;
+ (instancetype)action:(NSString *)title;
+ (instancetype)destructive:(NSString *)title;
+ (instancetype)info:(NSString *)title subtitle:(NSString *)subtitle;
+ (instancetype)slider:(float)value;
+ (instancetype)custom:(UIView *)view;
@end

@interface NGItemListController : NGListController
- (instancetype)initWithTitle:(NSString *)title items:(NSArray *)items;
@property (nonatomic, copy) NSArray *items;
@end

// The blocks colour with a card's 26pt corners cut out (cornersImage(glass: true)).
UIImage *NGBlockCornersImage(BOOL top, BOOL bottom);
