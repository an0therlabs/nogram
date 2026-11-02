#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NGMessageStatus) {
    NGMessageStatusSending,
    NGMessageStatusSent,
    NGMessageStatusRead,
};

typedef NS_ENUM(NSInteger, NGChatKind) {
    NGChatKindPrivate,
    NGChatKindGroup,
    NGChatKindChannel,
    NGChatKindSaved,
};

@interface NGUser : NSObject
@property (nonatomic, copy) NSString *firstName;
@property (nonatomic, copy) NSString *lastName;
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *lastSeen;
@property (nonatomic) NSInteger colorIndex;
@property (nonatomic) BOOL online;
+ (instancetype)userWithFirst:(NSString *)first last:(NSString *)last color:(NSInteger)color online:(BOOL)online lastSeen:(NSString *)lastSeen;
- (NSString *)displayName;
- (NSString *)initials;
- (NSString *)statusText;
@end

@interface NGMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL outgoing;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic) NGMessageStatus status;
@property (nonatomic, strong) NGUser *author;
+ (instancetype)messageWithText:(NSString *)text outgoing:(BOOL)outgoing date:(NSDate *)date;
@end

@interface NGChat : NSObject
@property (nonatomic) NGChatKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NGUser *user;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) NSMutableArray *messages;
@property (nonatomic) NSInteger unreadCount;
@property (nonatomic) NSInteger colorIndex;
@property (nonatomic) BOOL muted;
@property (nonatomic) BOOL pinned;
@property (nonatomic) BOOL typing;
@property (nonatomic, copy) NSString *draft;
- (NGMessage *)lastMessage;
- (NSString *)initials;
- (NSString *)statusText;
@end

@interface NGCall : NSObject
@property (nonatomic, strong) NGUser *user;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic) BOOL outgoing;
@property (nonatomic) BOOL missed;
@property (nonatomic) NSInteger minutes;
@end

@interface NGDemoData : NSObject
@property (nonatomic, readonly) NSMutableArray *chats;
@property (nonatomic, readonly) NSArray *contacts;
@property (nonatomic, readonly) NSArray *calls;
@property (nonatomic, readonly) NGUser *me;
+ (instancetype)shared;
- (NSString *)randomReply;
- (NGChat *)chatWithUser:(NGUser *)user;
@end
