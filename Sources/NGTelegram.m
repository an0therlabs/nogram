#import "NGTelegram.h"
#import "NGConfig.h"
#import "ngmt.h"
#import "ngtl.h"
#import "NGModel.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

// TelegramCore's seed address list (Network.swift).
static NSString *NGDatacenterAddress(int dc, BOOL test) {
    if (test) {
        switch (dc) {
            case 1: return @"149.154.175.10";
            case 3: return @"149.154.175.117";
            default: return @"149.154.167.40";
        }
    }
    switch (dc) {
        case 1: return @"149.154.175.50";
        case 3: return @"149.154.175.100";
        case 4: return @"149.154.167.91";
        case 5: return @"149.154.171.5";
        default: return @"149.154.167.50";
    }
}

static NSString *const NGStoreKey = @"ng.mtproto.account";

@implementation NGTelegram {
    dispatch_queue_t _queue;
    ngmt_session *_session;
    int _dc;
    BOOL _connected;
    BOOL _connectionInited;
    NSDictionary *_currentUser;
    BOOL _authorized;
}

+ (instancetype)shared {
    static NGTelegram *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [NGTelegram new]; });
    return shared;
}

+ (BOOL)hasCredentials {
    return NG_API_ID != 0 && strlen(NG_API_HASH) > 0;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("ng.mtproto", DISPATCH_QUEUE_SERIAL);
        _session = ngmt_session_new();
        _dc = 2;
        NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:NGStoreKey];
        if (stored) {
            _dc = [stored[@"dc"] intValue] ?: 2;
            NSData *key = stored[@"key"];
            if (key.length == 256) ngmt_set_auth_key(_session, key.bytes, [stored[@"salt"] unsignedLongLongValue]);
            _authorized = [stored[@"authorized"] boolValue];
            _currentUser = stored[@"user"];
        }
    }
    return self;
}

- (BOOL)isAuthorized { return _authorized; }
- (NSDictionary *)currentUser { return _currentUser; }

- (void)save {
    NSMutableDictionary *stored = [NSMutableDictionary dictionary];
    stored[@"dc"] = @(_dc);
    if (ngmt_has_auth_key(_session)) {
        stored[@"key"] = [NSData dataWithBytes:ngmt_auth_key(_session) length:256];
        stored[@"salt"] = @(ngmt_server_salt(_session));
    }
    stored[@"authorized"] = @(_authorized);
    if (_currentUser) stored[@"user"] = _currentUser;
    [[NSUserDefaults standardUserDefaults] setObject:stored forKey:NGStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Connection (on _queue)

- (NSString *)ensureConnection {
    if (_connected) return nil;
    NSString *host = NGDatacenterAddress(_dc, NG_TEST_SERVERS);
    if (ngmt_connect(_session, host.UTF8String, 443, _dc, NG_TEST_SERVERS) != NGMT_OK) {
        return [NSString stringWithUTF8String:ngmt_last_error(_session)];
    }
    if (!ngmt_has_auth_key(_session)) {
        if (ngmt_create_auth_key(_session) != NGMT_OK) {
            NSString *error = [NSString stringWithUTF8String:ngmt_last_error(_session)];
            ngmt_disconnect(_session);
            return error;
        }
        [self save];
    }
    _connected = YES;
    _connectionInited = NO;
    return nil;
}

- (void)switchToDatacenter:(int)dc {
    ngmt_disconnect(_session);
    ngmt_session_free(_session);
    _session = ngmt_session_new();
    _dc = dc;
    _connected = NO;
    [self save];
}

// invokeWithLayer(layer, initConnection(api_id, device, system, app, langs, query))
- (void)wrapQuery:(const ngmt_buf *)query into:(ngmt_buf *)out {
    struct utsname info;
    uname(&info);
    NSString *device = [NSString stringWithUTF8String:info.machine];
    NSString *system = [@"iOS " stringByAppendingString:[UIDevice currentDevice].systemVersion ?: @""];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1";
    ngmt_put_int(out, 0xda9b0d0d);
    ngmt_put_int(out, NG_API_LAYER);
    ngmt_put_int(out, 0xc1cd5ea9);
    ngmt_put_int(out, 0);   /* flags */
    ngmt_put_int(out, NG_API_ID);
    ngmt_put_cstring(out, device.UTF8String);
    ngmt_put_cstring(out, system.UTF8String);
    ngmt_put_cstring(out, version.UTF8String);
    ngmt_put_cstring(out, "ru");
    ngmt_put_cstring(out, "");
    ngmt_put_cstring(out, "ru");
    ngmt_put_bytes_raw(out, query->data, query->len);
}

// Runs one query, reconnecting to the account's DC on *_MIGRATE_X.
- (NSData *)call:(const ngmt_buf *)query error:(NSString **)error {
    for (int attempt = 0; attempt < 3; attempt++) {
        NSString *connectError = [self ensureConnection];
        if (connectError) { *error = connectError; return nil; }
        ngmt_buf wrapped = {0};
        [self wrapQuery:query into:&wrapped];
        ngmt_buf result = {0};
        int code = 0;
        char message[256] = {0};
        int rc = ngmt_call(_session, wrapped.data, wrapped.len, &result, &code, message, sizeof(message));
        ngmt_buf_free(&wrapped);
        [self save];   /* the salt may have changed */
        if (rc == NGMT_OK) {
            NSData *data = [NSData dataWithBytes:result.data length:result.len];
            ngmt_buf_free(&result);
            return data;
        }
        ngmt_buf_free(&result);
        if (rc == NGMT_RPC_ERROR) {
            NSString *text = [NSString stringWithUTF8String:message];
            NSRange migrate = [text rangeOfString:@"_MIGRATE_"];
            if (code == 303 && migrate.location != NSNotFound) {
                [self switchToDatacenter:[[text substringFromIndex:NSMaxRange(migrate)] intValue]];
                continue;
            }
            *error = text;
            return nil;
        }
        *error = [NSString stringWithUTF8String:ngmt_last_error(_session)];
        ngmt_disconnect(_session);
        _connected = NO;
        if (rc != NGMT_ERR_IO) return nil;
    }
    if (!*error) *error = @"Не удалось подключиться";
    return nil;
}

static NSString *NGReadString(ngmt_reader *r) {
    size_t n = 0;
    const uint8_t *p = ngmt_get_string(r, &n);
    if (!p) return @"";
    return [[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] ?: @"";
}

// user#b1b8cc83: flags flags2 id access_hash? first_name? last_name? username? phone? …
static NSDictionary *NGParseUser(ngmt_reader *r) {
    uint32_t ctor = ngmt_get_int(r);
    if (ctor != 0xb1b8cc83) return nil;
    uint32_t flags = ngmt_get_int(r);
    ngmt_get_int(r);   /* flags2 */
    NSMutableDictionary *user = [NSMutableDictionary dictionary];
    user[@"id"] = @(ngmt_get_long(r));
    if (flags & (1 << 0)) ngmt_get_long(r);
    if (flags & (1 << 1)) user[@"first_name"] = NGReadString(r);
    if (flags & (1 << 2)) user[@"last_name"] = NGReadString(r);
    if (flags & (1 << 3)) user[@"username"] = NGReadString(r);
    if (flags & (1 << 4)) user[@"phone"] = NGReadString(r);
    return r->error ? nil : user;
}

#pragma mark - Auth

- (void)sendCode:(NSString *)phone completion:(void (^)(NSString *, NSString *, NSInteger, NSString *))completion {
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0xa677244f);   /* auth.sendCode */
        ngmt_put_cstring(&q, phone.UTF8String);
        ngmt_put_int(&q, NG_API_ID);
        ngmt_put_cstring(&q, NG_API_HASH);
        ngmt_put_int(&q, 0xad253d78);   /* codeSettings, no flags */
        ngmt_put_int(&q, 0);
        NSString *error = nil;
        NSData *result = [self call:&q error:&error];
        ngmt_buf_free(&q);
        NSString *hash = nil, *via = nil;
        NSInteger length = 5;
        if (result) {
            ngmt_reader r = { result.bytes, result.length, 0, 0 };
            uint32_t ctor = ngmt_get_int(&r);
            if (ctor == 0x5e002502) {   /* auth.sentCode */
                ngmt_get_int(&r);   /* flags */
                uint32_t type = ngmt_get_int(&r);
                switch (type) {
                    case 0x3dbb5986: via = @"app"; length = ngmt_get_int(&r); break;
                    case 0xc000bba2: via = @"sms"; length = ngmt_get_int(&r); break;
                    case 0x5353e5a7: via = @"call"; length = ngmt_get_int(&r); break;
                    case 0xd9565c39: via = @"fragment"; NGReadString(&r); length = ngmt_get_int(&r); break;
                    case 0x82006484: via = @"missedCall"; NGReadString(&r); length = ngmt_get_int(&r); break;
                    default: error = [NSString stringWithFormat:@"Способ доставки кода не поддерживается (%08x)", type]; break;
                }
                if (!error) hash = NGReadString(&r);
                if (r.error) error = @"Не удалось разобрать ответ сервера";
            } else {
                error = [NSString stringWithFormat:@"Неожиданный ответ (%08x)", ctor];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(hash, via, length, error); });
    });
}

- (void)signIn:(NSString *)phone phoneCodeHash:(NSString *)hash code:(NSString *)code completion:(void (^)(NSDictionary *, NSString *))completion {
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0x8d52a951);   /* auth.signIn */
        ngmt_put_int(&q, 1 << 0);       /* phone_code present */
        ngmt_put_cstring(&q, phone.UTF8String);
        ngmt_put_cstring(&q, hash.UTF8String);
        ngmt_put_cstring(&q, code.UTF8String);
        NSString *error = nil;
        NSData *result = [self call:&q error:&error];
        ngmt_buf_free(&q);
        NSDictionary *user = nil;
        if (result) {
            ngmt_reader r = { result.bytes, result.length, 0, 0 };
            uint32_t ctor = ngmt_get_int(&r);
            if (ctor == 0x2ea2c0d4) {   /* auth.authorization */
                uint32_t flags = ngmt_get_int(&r);
                if (flags & (1 << 1)) ngmt_get_int(&r);           /* otherwise_relogin_days */
                if (flags & (1 << 0)) ngmt_get_int(&r);           /* tmp_sessions */
                if (flags & (1 << 2)) { size_t n; ngmt_get_string(&r, &n); }   /* future_auth_token */
                user = NGParseUser(&r);
                if (!user) error = @"Не удалось разобрать профиль";
            } else if (ctor == 0x44747e9a) {
                error = @"Этот номер не зарегистрирован в Telegram";
            } else {
                error = [NSString stringWithFormat:@"Неожиданный ответ (%08x)", ctor];
            }
        }
        if (user) {
            self->_authorized = YES;
            self->_currentUser = user;
            [self save];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(user, error); });
    });
}

- (void)logOut {
    dispatch_async(_queue, ^{
        self->_authorized = NO;
        self->_currentUser = nil;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:NGStoreKey];
        [self switchToDatacenter:2];
    });
}


#pragma mark - TL objects

// A decoded TL tree as Foundation objects: objects are dictionaries with
// the constructor name under "_", vectors arrays, strings NSString (NSData
// when not UTF-8), numbers NSNumber.
static id NGTLObject(const ngtl_node *n) {
    switch (n->kind) {
        case NGTL_INT:
        case NGTL_LONG:
            return @(n->i);
        case NGTL_BOOL:
            return @(n->i != 0);
        case NGTL_DOUBLE:
            return @(n->d);
        case NGTL_BYTES: {
            NSString *s = [[NSString alloc] initWithBytes:n->bytes length:n->len encoding:NSUTF8StringEncoding];
            return s ?: [NSData dataWithBytes:n->bytes length:n->len];
        }
        case NGTL_VECTOR: {
            NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)n->count];
            for (int i = 0; i < n->count; i++) [a addObject:NGTLObject(n->items[i])];
            return a;
        }
        case NGTL_OBJECT: {
            NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)n->count + 1];
            d[@"_"] = [NSString stringWithUTF8String:n->ctor];
            for (int i = 0; i < n->count; i++) d[[NSString stringWithUTF8String:n->items[i]->key]] = NGTLObject(n->items[i]);
            return d;
        }
    }
    return [NSNull null];
}

- (NSDictionary *)callObject:(const ngmt_buf *)query error:(NSString **)error {
    NSData *data = [self call:query error:error];
    if (!data) return nil;
    char message[160];
    ngtl_node *node = ngtl_decode(data.bytes, data.length, message, sizeof(message));
    if (!node) {
        *error = [NSString stringWithFormat:@"Не удалось разобрать ответ: %s", message];
        return nil;
    }
    NSDictionary *object = NGTLObject(node);
    ngtl_free(node);
    return object;
}

static NSString *NGPeerKey(NSDictionary *peer) {
    NSString *type = peer[@"_"];
    if ([type isEqualToString:@"peerUser"]) return [NSString stringWithFormat:@"u%@", peer[@"user_id"]];
    if ([type isEqualToString:@"peerChat"]) return [NSString stringWithFormat:@"c%@", peer[@"chat_id"]];
    if ([type isEqualToString:@"peerChannel"]) return [NSString stringWithFormat:@"h%@", peer[@"channel_id"]];
    return nil;
}

// UserStatus → the profile line Telegram shows.
static NSString *NGLastSeen(NSDictionary *status, BOOL *online) {
    NSString *type = status[@"_"];
    *online = NO;
    if ([type isEqualToString:@"userStatusOnline"]) {
        *online = [status[@"expires"] doubleValue] > [[NSDate date] timeIntervalSince1970];
        if (*online) return @"в сети";
    }
    if ([type isEqualToString:@"userStatusOffline"] || [type isEqualToString:@"userStatusOnline"]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[status[[type isEqualToString:@"userStatusOnline"] ? @"expires" : @"was_online"] doubleValue]];
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
        NSTimeInterval ago = -[date timeIntervalSinceNow];
        if (ago < 60) return @"был(а) только что";
        if (ago < 3600) return [NSString stringWithFormat:@"был(а) %d мин. назад", (int)(ago / 60)];
        f.dateFormat = ago < 86400 ? @"'был(а) в' HH:mm" : @"'был(а)' d MMM 'в' HH:mm";
        return [f stringFromDate:date];
    }
    if ([type isEqualToString:@"userStatusRecently"]) return @"был(а) недавно";
    if ([type isEqualToString:@"userStatusLastWeek"]) return @"был(а) на этой неделе";
    if ([type isEqualToString:@"userStatusLastMonth"]) return @"был(а) в этом месяце";
    return @"был(а) давно";
}

// One NGUser per user id, so a group's messages from one sender share it.
- (NGUser *)userFrom:(NSDictionary *)u {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSNumber *uid = u[@"id"];
    NGUser *user = cache[uid];
    if (!user) {
        user = [NGUser new];
        cache[uid] = user;
    }
    user.firstName = u[@"first_name"] ?: ([u[@"_"] isEqualToString:@"userEmpty"] ? @"Удалённый аккаунт" : @"");
    user.lastName = u[@"last_name"] ?: @"";
    user.username = u[@"username"];
    if ([u[@"phone"] length]) user.phone = [@"+" stringByAppendingString:u[@"phone"]];
    user.colorIndex = (NSInteger)(llabs([uid longLongValue]) % 7);
    BOOL online = NO;
    user.lastSeen = [u[@"bot"] boolValue] ? @"бот" : NGLastSeen(u[@"status"], &online);
    user.online = online;
    return user;
}

// Message → NGMessage: the text, or what the media is when there is none.
- (NGMessage *)messageFrom:(NSDictionary *)m users:(NSDictionary *)users readOutbox:(int32_t)readOutbox {
    NSString *type = m[@"_"];
    if ([type isEqualToString:@"messageEmpty"]) return nil;
    NSString *text = m[@"message"];
    if ([type isEqualToString:@"messageService"]) {
        text = @"Служебное сообщение";
    } else if (text.length == 0 && m[@"media"]) {
        NSDictionary *media = m[@"media"];
        NSString *mt = media[@"_"];
        if ([mt isEqualToString:@"messageMediaPhoto"]) text = @"🖼 Фото";
        else if ([mt isEqualToString:@"messageMediaGeo"] || [mt isEqualToString:@"messageMediaVenue"] || [mt isEqualToString:@"messageMediaGeoLive"]) text = @"📍 Геопозиция";
        else if ([mt isEqualToString:@"messageMediaContact"]) text = @"👤 Контакт";
        else if ([mt isEqualToString:@"messageMediaPoll"]) text = @"📊 Опрос";
        else if ([mt isEqualToString:@"messageMediaDocument"]) {
            text = @"📎 Файл";
            for (NSDictionary *attr in media[@"document"][@"attributes"]) {
                NSString *at = attr[@"_"];
                if ([at isEqualToString:@"documentAttributeSticker"]) { text = [NSString stringWithFormat:@"%@ Стикер", attr[@"alt"] ?: @""]; break; }
                if ([at isEqualToString:@"documentAttributeVideo"]) text = [attr[@"round_message"] boolValue] ? @"📹 Видеосообщение" : @"🎬 Видео";
                if ([at isEqualToString:@"documentAttributeAudio"]) text = [attr[@"voice"] boolValue] ? @"🎤 Голосовое сообщение" : @"🎵 Музыка";
                if ([at isEqualToString:@"documentAttributeAnimated"]) text = @"GIF";
            }
        } else text = @"Медиа";
    }
    NGMessage *msg = [NGMessage messageWithText:text ?: @"" outgoing:[m[@"out"] boolValue] date:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
    msg.remoteId = [m[@"id"] intValue];
    msg.status = msg.outgoing && msg.remoteId > readOutbox ? NGMessageStatusSent : NGMessageStatusRead;
    NSDictionary *from = m[@"from_id"];
    if ([from[@"_"] isEqualToString:@"peerUser"]) {
        NSDictionary *u = users[from[@"user_id"]];
        if (u) msg.author = [self userFrom:u];
    }
    return msg;
}

static NSDictionary *NGIndexById(NSArray *objects) {
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    for (NSDictionary *o in objects) if (o[@"id"]) index[o[@"id"]] = o;
    return index;
}

- (void)loadDialogs:(void (^)(NSArray *, NSString *))completion {
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0xa0f4cb4f);   /* messages.getDialogs */
        ngmt_put_int(&q, 0);
        ngmt_put_int(&q, 0);            /* offset_date */
        ngmt_put_int(&q, 0);            /* offset_id */
        ngmt_put_int(&q, 0x7f3b18ea);   /* inputPeerEmpty */
        ngmt_put_int(&q, 100);
        ngmt_put_long(&q, 0);
        NSString *error = nil;
        NSDictionary *result = [self callObject:&q error:&error];
        ngmt_buf_free(&q);
        NSMutableArray *chats = nil;
        if (result) {
            chats = [NSMutableArray array];
            NSDictionary *users = NGIndexById(result[@"users"]);
            NSDictionary *groups = NGIndexById(result[@"chats"]);
            NSMutableDictionary *lastMessages = [NSMutableDictionary dictionary];
            for (NSDictionary *m in result[@"messages"]) {
                NSString *key = NGPeerKey(m[@"peer_id"]);
                if (key && m[@"id"]) lastMessages[[NSString stringWithFormat:@"%@:%@", key, m[@"id"]]] = m;
            }
            int64_t selfId = [self->_currentUser[@"id"] longLongValue];
            for (NSDictionary *d in result[@"dialogs"]) {
                if (![d[@"_"] isEqualToString:@"dialog"]) continue;
                NSDictionary *peer = d[@"peer"];
                NSString *key = NGPeerKey(peer);
                if (!key) continue;
                NGChat *chat = [NGChat new];
                chat.peerKey = key;
                chat.unreadCount = [d[@"unread_count"] integerValue];
                chat.pinned = [d[@"pinned"] boolValue];
                chat.readOutboxMaxId = [d[@"read_outbox_max_id"] intValue];
                double muteUntil = [d[@"notify_settings"][@"mute_until"] doubleValue];
                chat.muted = muteUntil > [[NSDate date] timeIntervalSince1970];
                if ([peer[@"_"] isEqualToString:@"peerUser"]) {
                    NSDictionary *u = users[peer[@"user_id"]];
                    chat.peerId = [peer[@"user_id"] longLongValue];
                    chat.accessHash = [u[@"access_hash"] longLongValue];
                    if (chat.peerId == selfId || [u[@"self"] boolValue]) {
                        chat.kind = NGChatKindSaved;
                        chat.title = @"Избранное";
                        chat.colorIndex = 5;
                    } else {
                        chat.kind = NGChatKindPrivate;
                        chat.user = [self userFrom:u ?: @{ @"id": peer[@"user_id"] }];
                        chat.title = [chat.user displayName];
                        chat.colorIndex = chat.user.colorIndex;
                    }
                } else {
                    NSNumber *gid = peer[@"chat_id"] ?: peer[@"channel_id"];
                    NSDictionary *g = groups[gid];
                    chat.peerId = [gid longLongValue];
                    chat.accessHash = [g[@"access_hash"] longLongValue];
                    chat.title = g[@"title"] ?: @"Чат";
                    chat.colorIndex = (NSInteger)(llabs(chat.peerId) % 7);
                    BOOL broadcast = [g[@"broadcast"] boolValue];
                    chat.kind = broadcast ? NGChatKindChannel : NGChatKindGroup;
                    NSNumber *count = g[@"participants_count"];
                    chat.subtitle = count ? [NSString stringWithFormat:broadcast ? @"%@ подписчиков" : @"%@ участников", count] : (broadcast ? @"канал" : @"группа");
                    chat.link = g[@"username"] ? [@"t.me/" stringByAppendingString:g[@"username"]] : nil;
                }
                NSDictionary *top = lastMessages[[NSString stringWithFormat:@"%@:%@", key, d[@"top_message"]]];
                NGMessage *last = top ? [self messageFrom:top users:users readOutbox:chat.readOutboxMaxId] : nil;
                if (last) [chat.messages addObject:last];
                [chats addObject:chat];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(chats, error); });
    });
}

static void NGPutInputPeer(ngmt_buf *q, NGChat *chat) {
    if (chat.kind == NGChatKindSaved) {
        ngmt_put_int(q, 0x7da07ec9);   /* inputPeerSelf */
    } else if ([chat.peerKey hasPrefix:@"u"]) {
        ngmt_put_int(q, 0xdde8a54c);   /* inputPeerUser */
        ngmt_put_long(q, (uint64_t)chat.peerId);
        ngmt_put_long(q, (uint64_t)chat.accessHash);
    } else if ([chat.peerKey hasPrefix:@"c"]) {
        ngmt_put_int(q, 0x35a95cb9);   /* inputPeerChat */
        ngmt_put_long(q, (uint64_t)chat.peerId);
    } else {
        ngmt_put_int(q, 0x27bcbbfc);   /* inputPeerChannel */
        ngmt_put_long(q, (uint64_t)chat.peerId);
        ngmt_put_long(q, (uint64_t)chat.accessHash);
    }
}

- (void)loadHistory:(id)chatObject completion:(void (^)(NSArray *, NSString *))completion {
    NGChat *chat = chatObject;
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0x4423e6c5);   /* messages.getHistory */
        NGPutInputPeer(&q, chat);
        ngmt_put_int(&q, 0);    /* offset_id */
        ngmt_put_int(&q, 0);    /* offset_date */
        ngmt_put_int(&q, 0);    /* add_offset */
        ngmt_put_int(&q, 60);   /* limit */
        ngmt_put_int(&q, 0);    /* max_id */
        ngmt_put_int(&q, 0);    /* min_id */
        ngmt_put_long(&q, 0);   /* hash */
        NSString *error = nil;
        NSDictionary *result = [self callObject:&q error:&error];
        ngmt_buf_free(&q);
        NSMutableArray *messages = nil;
        if (result) {
            messages = [NSMutableArray array];
            NSDictionary *users = NGIndexById(result[@"users"]);
            for (NSDictionary *m in [result[@"messages"] reverseObjectEnumerator]) {
                NGMessage *msg = [self messageFrom:m users:users readOutbox:chat.readOutboxMaxId];
                if (msg) [messages addObject:msg];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(messages, error); });
    });
}

- (void)sendText:(NSString *)text toChat:(id)chatObject completion:(void (^)(NSString *))completion {
    NGChat *chat = chatObject;
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0xfef48f62);   /* messages.sendMessage */
        ngmt_put_int(&q, 0);
        NGPutInputPeer(&q, chat);
        ngmt_put_cstring(&q, text.UTF8String);
        uint64_t randomId = ((uint64_t)arc4random() << 32) | arc4random();
        ngmt_put_long(&q, randomId);
        NSString *error = nil;
        NSData *result = [self call:&q error:&error];
        ngmt_buf_free(&q);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result ? nil : error); });
    });
}

- (void)markRead:(id)chatObject maxId:(int32_t)maxId {
    NGChat *chat = chatObject;
    if (maxId <= 0) return;
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        if ([chat.peerKey hasPrefix:@"h"]) {
            ngmt_put_int(&q, 0xcc104937);   /* channels.readHistory */
            ngmt_put_int(&q, 0xf35aec28);   /* inputChannel */
            ngmt_put_long(&q, (uint64_t)chat.peerId);
            ngmt_put_long(&q, (uint64_t)chat.accessHash);
        } else {
            ngmt_put_int(&q, 0x0e306d3a);   /* messages.readHistory */
            NGPutInputPeer(&q, chat);
        }
        ngmt_put_int(&q, (uint32_t)maxId);
        NSString *error = nil;
        [self call:&q error:&error];
        ngmt_buf_free(&q);
    });
}

@end
