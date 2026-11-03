#import <UIKit/UIKit.h>

// The account's connection to Telegram over the ngmt MTProto core: one DC,
// one permanent auth key (kept in NSUserDefaults), calls made in order on a
// serial queue, completions on the main queue. Follows *_MIGRATE_X errors to
// the account's DC.
// Posted on the main queue when the server ends this session (401:
// AUTH_KEY_UNREGISTERED, SESSION_REVOKED, USER_DEACTIVATED, …). The account is
// forgotten locally and every call fails until the user signs in again.
extern NSString *const NGTelegramSessionEndedNotification;

@interface NGTelegram : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isAuthorized;
@property (nonatomic, readonly) NSDictionary *currentUser;   // first_name, last_name, username, phone, id
+ (BOOL)hasCredentials;

// auth.sendCode → phone_code_hash and a description of where the code went.
- (void)sendCode:(NSString *)phone completion:(void (^)(NSString *phoneCodeHash, NSString *deliveredVia, NSInteger codeLength, NSString *error))completion;
// auth.signIn → the user on success. error is the server's message
// (PHONE_CODE_INVALID, SESSION_PASSWORD_NEEDED, …) or a transport problem.
- (void)signIn:(NSString *)phone phoneCodeHash:(NSString *)hash code:(NSString *)code completion:(void (^)(NSDictionary *user, NSString *error))completion;
- (void)logOut;

// messages.getDialogs → NGChat objects (users, groups, channels, Saved
// Messages), each with its last message, unread count and mute state.
- (void)loadDialogs:(void (^)(NSArray *chats, NSString *error))completion;
// messages.getHistory → the latest messages, oldest first.
- (void)loadHistory:(id)chat completion:(void (^)(NSArray *messages, NSString *error))completion;
// messages.sendMessage
- (void)sendText:(NSString *)text toChat:(id)chat completion:(void (^)(NSString *error))completion;
// messages.readHistory / channels.readHistory up to maxId
- (void)markRead:(id)chat maxId:(int32_t)maxId;

// contacts.getContacts → NGUser objects.
- (void)loadContacts:(void (^)(NSArray *users, NSString *error))completion;

// Images (upload.getFile from the file's DC, with a disk cache). The
// completion runs on the main queue, only when an image was found.
- (UIImage *)cachedImageForKey:(NSString *)key;
- (void)loadAvatarForUser:(id)user completion:(void (^)(UIImage *image))completion;
- (void)loadAvatarForChat:(id)chat completion:(void (^)(UIImage *image))completion;
- (void)loadPhoto:(NSDictionary *)photo completion:(void (^)(UIImage *image))completion;
// The blurred inline preview Telegram sends with a photo (photoStrippedSize).
+ (UIImage *)imageFromStrippedThumb:(NSData *)data;

@end
