#import <UIKit/UIKit.h>
#import "NGTheme.h"
#import "NGModel.h"

// Gradient circle with initials (or a glyph), as AvatarNode draws it.
@interface NGAvatarView : UIView
@property (nonatomic) NSInteger colorIndex;
@property (nonatomic, copy) NSString *initials;
@property (nonatomic) BOOL hasIcon;
@property (nonatomic) BOOL showsOnline;
- (void)configureWithChat:(NGChat *)chat;
- (void)configureWithUser:(NGUser *)user;
@end

// Avatar + title + subtitle + right detail; used by Contacts, Calls and pickers.
@interface NGPeerCell : UITableViewCell
@property (nonatomic, readonly) NGAvatarView *avatar;
@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly) UILabel *subtitleLabel;
@property (nonatomic, readonly) UILabel *detailLabel;
@property (nonatomic, readonly) UIImageView *subtitleIcon;
@property (nonatomic) BOOL hidesSeparator;
@end

// Icon + title row in an accent colour ("Invite Friends").
@interface NGActionCell : UITableViewCell
@property (nonatomic, readonly) UIImageView *iconView;
@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic) BOOL hidesSeparator;
@end

// A grey gap between blocks of rows.
@interface NGSpacerCell : UITableViewCell
@end

@interface NGChatListCell : UITableViewCell
- (void)configureWithChat:(NGChat *)chat;
@end
