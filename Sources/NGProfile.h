#import <UIKit/UIKit.h>
#import "NGModel.h"

// PeerInfoScreen for a user, a group or a channel, opened from the avatar in
// a chat's bar: PeerInfoHeaderNode (avatar, name, status, the action
// buttons, the profile-music strip), the info items of infoItems, and the
// shared-media panes under them.
UIViewController *NGPeerInfoScreen(NGChat *chat, BOOL openedFromChat);
