#import <UIKit/UIKit.h>
#import "NGModel.h"
#import "NGGlass.h"

// A root list in the new design: no UINavigationBar; the glass capsule row
// (NGHeaderView) floats over the list and stays put while it scrolls.
@interface NGListController : UITableViewController
@property (nonatomic, readonly) NGHeaderView *header;
@end

@interface NGChatListController : NGListController
@end

@interface NGContactsController : NGListController
// Set for the "New Message" picker: the list shows a Cancel button and calls
// this instead of opening the chat itself.
@property (nonatomic, copy) void (^onSelect)(NGUser *user);
@end

@interface NGCallsController : NGListController
@end

@interface NGSettingsController : NGListController
@end
