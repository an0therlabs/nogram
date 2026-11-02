#import <Foundation/Foundation.h>

// The account's connection to Telegram over the ngmt MTProto core: one DC,
// one permanent auth key (kept in NSUserDefaults), calls made in order on a
// serial queue, completions on the main queue. Follows *_MIGRATE_X errors to
// the account's DC.
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

@end
