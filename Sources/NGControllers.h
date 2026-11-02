#import <UIKit/UIKit.h>
#import "NGModel.h"

@interface NGChatListController : UITableViewController
@end

@interface NGContactsController : UITableViewController
// Set for the "New Message" picker: the list shows a Cancel button and calls
// this instead of opening the chat itself.
@property (nonatomic, copy) void (^onSelect)(NGUser *user);
@end

@interface NGCallsController : UITableViewController
@end

@interface NGSettingsController : UITableViewController
@end
