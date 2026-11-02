#import "NGModel.h"

static NSString *NGFirstLetter(NSString *s) {
    if (s.length == 0) return @"";
    NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:0];
    return [[s substringWithRange:r] uppercaseString];
}

static NSString *NGInitials(NSString *title) {
    NSArray *words = [title componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableString *result = [NSMutableString string];
    for (NSString *word in words) {
        if (word.length == 0) continue;
        [result appendString:NGFirstLetter(word)];
        if (result.length >= 2) break;
    }
    return result;
}

@implementation NGUser

+ (instancetype)userWithFirst:(NSString *)first last:(NSString *)last color:(NSInteger)color online:(BOOL)online lastSeen:(NSString *)lastSeen {
    NGUser *user = [self new];
    user.firstName = first;
    user.lastName = last;
    user.colorIndex = color;
    user.online = online;
    user.lastSeen = lastSeen;
    return user;
}

- (NSString *)displayName {
    if (self.lastName.length == 0) return self.firstName;
    return [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
}

- (NSString *)initials {
    return [NSString stringWithFormat:@"%@%@", NGFirstLetter(self.firstName), NGFirstLetter(self.lastName)];
}

- (NSString *)statusText {
    return self.online ? @"в сети" : (self.lastSeen ?: @"был(а) недавно");
}

@end

@implementation NGMessage

+ (instancetype)messageWithText:(NSString *)text outgoing:(BOOL)outgoing date:(NSDate *)date {
    NGMessage *message = [self new];
    message.text = text;
    message.outgoing = outgoing;
    message.date = date;
    message.status = NGMessageStatusRead;
    return message;
}

@end

@implementation NGChat

- (instancetype)init {
    if ((self = [super init])) {
        _messages = [NSMutableArray array];
    }
    return self;
}

- (NGMessage *)lastMessage {
    return [self.messages lastObject];
}

- (NSString *)initials {
    return self.user ? [self.user initials] : NGInitials(self.title);
}

- (NSString *)statusText {
    if (self.typing) return @"печатает…";
    if (self.kind == NGChatKindPrivate) return [self.user statusText];
    return self.subtitle;
}

@end

@implementation NGCall
@end

@implementation NGDemoData {
    NSArray *_replies;
}

+ (instancetype)shared {
    static NGDemoData *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [NGDemoData new]; });
    return shared;
}

static NSDate *NGAgo(double minutes) {
    return [NSDate dateWithTimeIntervalSinceNow:-minutes * 60.0];
}

static NGMessage *NGOut(NSString *text, double minutesAgo) {
    return [NGMessage messageWithText:text outgoing:YES date:NGAgo(minutesAgo)];
}

static NGMessage *NGIn(NSString *text, double minutesAgo, NGUser *author) {
    NGMessage *m = [NGMessage messageWithText:text outgoing:NO date:NGAgo(minutesAgo)];
    m.author = author;
    return m;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;

    _me = [NGUser userWithFirst:@"Иван" last:@"Петров" color:5 online:YES lastSeen:nil];
    _me.phone = @"+7 999 123-45-67";
    _me.username = @"ios6garage";

    NGUser *dima = [NGUser userWithFirst:@"Дима" last:@"Гаражный" color:2 online:YES lastSeen:nil];
    NGUser *mom = [NGUser userWithFirst:@"Мама" last:@"" color:0 online:NO lastSeen:@"был(а) 5 минут назад"];
    NGUser *katya = [NGUser userWithFirst:@"Катя" last:@"Соколова" color:6 online:NO lastSeen:@"был(а) недавно"];
    NGUser *oleg = [NGUser userWithFirst:@"Олег" last:@"Джейлбрейк" color:3 online:YES lastSeen:nil];
    NGUser *sergey = [NGUser userWithFirst:@"Сергей" last:@"Иванов" color:1 online:NO lastSeen:@"был(а) вчера в 23:14"];
    NGUser *anna = [NGUser userWithFirst:@"Анна" last:@"Кузнецова" color:4 online:NO lastSeen:@"был(а) на этой неделе"];
    NGUser *nikita = [NGUser userWithFirst:@"Никита" last:@"Орлов" color:5 online:NO lastSeen:@"был(а) давно"];
    NGUser *lena = [NGUser userWithFirst:@"Лена" last:@"Морозова" color:0 online:NO lastSeen:@"был(а) недавно"];
    for (NGUser *u in @[ dima, mom, katya, oleg, sergey, anna, nikita, lena ]) {
        u.phone = @"+7 900 000-00-00";
    }
    dima.phone = @"+7 916 555-12-34";
    dima.username = @"dima_garage";
    dima.bio = @"Паяю, прошиваю, джейлбрейкаю. iPhone 4S навсегда.";
    dima.birthday = @"14 марта";
    dima.musicTitle = @"Группа крови";
    dima.musicArtist = @"Кино";
    oleg.username = @"oleg_jb";
    oleg.bio = @"Твики для iOS 6 с 2013 года";
    oleg.musicTitle = @"Smells Like Teen Spirit";
    oleg.musicArtist = @"Nirvana";
    katya.username = @"katya_s";
    katya.birthday = @"2 ноября";
    sergey.bio = @"Работа: 9:00–18:00";
    _contacts = [@[ dima, mom, katya, oleg, sergey, anna, nikita, lena ] sortedArrayUsingComparator:^NSComparisonResult(NGUser *a, NGUser *b) {
        if (a.online != b.online) return a.online ? NSOrderedAscending : NSOrderedDescending;
        return [[a displayName] compare:[b displayName]];
    }];

    NSMutableArray *chats = [NSMutableArray array];

    NGChat *saved = [NGChat new];
    saved.kind = NGChatKindSaved;
    saved.title = @"Избранное";
    saved.colorIndex = 5;
    saved.pinned = YES;
    [saved.messages addObjectsFromArray:@[
        NGOut(@"SDK: theos/sdks → iPhoneOS9.3.sdk, там ещё есть armv7", 60 * 26),
        NGOut(@"make package install THEOS_DEVICE_IP=192.168.1.5", 60 * 3),
    ]];
    [chats addObject:saved];

    NGChat *dimaChat = [self chatWithUser:dima];
    dimaChat.pinned = YES;
    dimaChat.unreadCount = 2;
    [dimaChat.messages addObjectsFromArray:@[
        NGIn(@"Ты где пропал?", 60 * 25, dima),
        NGOut(@"В гараже, собираю клиент под iOS 6", 60 * 25 - 2),
        NGIn(@"Под шестёрку?? 😂", 60 * 25 - 3, dima),
        NGIn(@"Там же даже свифта нет", 60 * 25 - 3, dima),
        NGOut(@"Поэтому на ObjC. Theos, armv7, всё как в 2013", 60 * 25 - 5),
        NGOut(@"Скевоморфизм не завезу, будет как настоящая телега", 60 * 25 - 5),
        NGIn(@"Скинь деб, закину на свой 4S", 14, dima),
        NGIn(@"Он у меня до сих пор на 6.1.3 сидит", 13, dima),
    ]];
    [chats addObject:dimaChat];

    NGChat *garage = [NGChat new];
    garage.kind = NGChatKindGroup;
    garage.title = @"Гараж iOS 6";
    garage.subtitle = @"4 участника, 2 в сети";
    garage.colorIndex = 1;
    garage.members = @[ dima, oleg, katya ];
    garage.about = @"Чат для тех, кто до сих пор держит iPhone на iOS 6. Делимся твиками, прошивками и болью.";
    garage.link = @"t.me/ios6garage";
    garage.unreadCount = 5;
    [garage.messages addObjectsFromArray:@[
        NGIn(@"Кто-нибудь помнит, как Cydia ставить на 6.1.6?", 60 * 5, oleg),
        NGIn(@"p0sixspwn, но там надо iTunes старый", 60 * 5 - 1, katya),
        NGOut(@"У меня всё стоит, могу помочь", 60 * 5 - 3),
        NGIn(@"Красава", 60 * 5 - 4, oleg),
        NGIn(@"Ребят, а ретину на iPhone 4 кто-то тестил?", 40, dima),
        NGIn(@"На 3GS тоже пойдёт, armv7 же", 38, oleg),
        NGIn(@"Главное, чтоб батарея не сдохла 🔋", 7, katya),
    ]];
    [chats addObject:garage];

    NGChat *momChat = [self chatWithUser:mom];
    momChat.unreadCount = 1;
    [momChat.messages addObjectsFromArray:@[
        NGOut(@"Мам, я задержусь", 60 * 2),
        NGIn(@"Хорошо. Ты покушал?", 60 * 2 - 10, mom),
        NGIn(@"Сынок, ответь", 31, mom),
    ]];
    [chats addObject:momChat];

    NGChat *channel = [NGChat new];
    channel.kind = NGChatKindChannel;
    channel.title = @"Jailbreak News";
    channel.subtitle = @"48 213 подписчиков";
    channel.colorIndex = 2;
    channel.muted = YES;
    channel.unreadCount = 23;
    channel.about = @"Новости джейлбрейка, твиков и старых прошивок. Без рекламы.";
    channel.link = @"t.me/jailbreak_news";
    [channel.messages addObjectsFromArray:@[
        NGIn(@"Вышел p0sixspwn для iOS 6.1.3–6.1.6. Untethered, поддерживаются все устройства на armv7.", 60 * 30, nil),
        NGIn(@"Обновился Theos: добавлена поддержка новых тулчейнов на Linux.", 60 * 8, nil),
        NGIn(@"Напоминаем: делайте бэкап SHSH, пока Apple подписывает прошивки.", 55, nil),
    ]];
    [chats addObject:channel];

    NGChat *katyaChat = [self chatWithUser:katya];
    [katyaChat.messages addObjectsFromArray:@[
        NGIn(@"Скинешь фотки с субботы?", 60 * 7, katya),
        NGOut(@"Да, вечером", 60 * 6),
        NGOut(@"Уже скинул в общий чат", 60 * 4),
    ]];
    [chats addObject:katyaChat];

    NGChat *olegChat = [self chatWithUser:oleg];
    olegChat.draft = @"щас скину твик";
    [olegChat.messages addObjectsFromArray:@[
        NGIn(@"Есть твик для статусбара на шестёрку?", 60 * 9, oleg),
    ]];
    [chats addObject:olegChat];

    NGChat *sergeyChat = [self chatWithUser:sergey];
    [sergeyChat.messages addObjectsFromArray:@[
        NGOut(@"Сергей, привет! Документы получил?", 60 * 28),
        NGIn(@"Да, всё пришло, спасибо 👍", 60 * 27, sergey),
    ]];
    [chats addObject:sergeyChat];

    NGChat *annaChat = [self chatWithUser:anna];
    [annaChat.messages addObjectsFromArray:@[
        NGIn(@"С днём рождения! 🎉", 60 * 24 * 3, anna),
        NGOut(@"Спасибо большое!", 60 * 24 * 3 - 30),
    ]];
    [chats addObject:annaChat];

    NGChat *nikitaChat = [self chatWithUser:nikita];
    [nikitaChat.messages addObjectsFromArray:@[
        NGIn(@"Ок, договорились", 60 * 24 * 12, nikita),
    ]];
    [chats addObject:nikitaChat];

    _chats = chats;

    NSMutableArray *calls = [NSMutableArray array];
    struct { __unsafe_unretained NGUser *user; double ago; BOOL outgoing, missed; NSInteger minutes; } table[] = {
        { mom, 45, NO, YES, 0 },
        { dima, 60 * 3, YES, NO, 12 },
        { oleg, 60 * 26, NO, NO, 3 },
        { mom, 60 * 30, YES, NO, 7 },
        { katya, 60 * 24 * 2, NO, YES, 0 },
        { sergey, 60 * 24 * 4, YES, NO, 1 },
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        NGCall *call = [NGCall new];
        call.user = table[i].user;
        call.date = NGAgo(table[i].ago);
        call.outgoing = table[i].outgoing;
        call.missed = table[i].missed;
        call.minutes = table[i].minutes;
        [calls addObject:call];
    }
    _calls = calls;

    _replies = @[
        @"ахаха жёстко", @"ну ты даёшь", @"а на 3GS запустится?", @"скинь деб", @"ок 👍",
        @"респект", @"щас гляну", @"это реально работает?!", @"бро, ты легенда",
    ];
    return self;
}

- (NSString *)randomReply {
    return _replies[arc4random_uniform((uint32_t)_replies.count)];
}

- (NGChat *)chatWithUser:(NGUser *)user {
    for (NGChat *chat in self.chats) {
        if (chat.user == user) return chat;
        if (user.userId && chat.peerId == user.userId && [chat.peerKey hasPrefix:@"u"]) return chat;
    }
    NGChat *chat = [NGChat new];
    chat.kind = NGChatKindPrivate;
    chat.user = user;
    if (user.userId) {
        chat.peerKey = [NSString stringWithFormat:@"u%lld", user.userId];
        chat.peerId = user.userId;
        chat.accessHash = user.accessHash;
    }
    chat.title = [user displayName];
    chat.colorIndex = user.colorIndex;
    return chat;
}

@end
