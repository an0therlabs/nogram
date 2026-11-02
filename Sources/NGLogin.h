#import <UIKit/UIKit.h>

// AuthorizationUI's phone and code entry, over NGTelegram.
// onLoggedIn runs on the main queue once auth.signIn succeeds.
UIViewController *NGLoginScreen(void (^onLoggedIn)(void));
