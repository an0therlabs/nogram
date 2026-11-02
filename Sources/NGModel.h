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
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *birthday;
@property (nonatomic, copy) NSString *musicTitle;    // the profile's saved music (peerInfoProfileMusic)
@property (nonatomic, copy) NSString *musicArtist;
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
@property (nonatomic) int32_t remoteId;   /* server message id, 0 for local */
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
@property (nonatomic, copy) NSString *about;
@property (nonatomic, copy) NSString *link;
// Set for chats loaded from the server (NGTelegram); nil peerKey = demo chat.
@property (nonatomic, copy) NSString *peerKey;     /* "u<id>", "c<id>" (basic group), "h<id>" (channel) */
@property (nonatomic) int64_t peerId;
@property (nonatomic) int64_t accessHash;
@property (nonatomic) int32_t readOutboxMaxId;
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
