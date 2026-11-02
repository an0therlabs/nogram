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

@interface NSData (NGBase64)
- (instancetype)initWithBase64EncodedStringCompat:(NSString *)string;
@end

@implementation NSData (NGBase64)
// -[NSData initWithBase64EncodedString:options:] is iOS 7+.
- (instancetype)initWithBase64EncodedStringCompat:(NSString *)string {
    static const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableData *out = [NSMutableData data];
    uint32_t acc = 0;
    int bits = 0;
    for (NSUInteger i = 0; i < string.length; i++) {
        const char *p = strchr(alphabet, (char)[string characterAtIndex:i]);
        if (!p || !*p) continue;
        acc = (acc << 6) | (uint32_t)(p - alphabet);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            uint8_t b = (uint8_t)(acc >> bits);
            [out appendBytes:&b length:1];
        }
    }
    return [self initWithData:out];
}
@end

static NSString *const NGStoreKey = @"ng.mtproto.account";

@implementation NGTelegram {
    dispatch_queue_t _queue;
    dispatch_queue_t _fileQueue;
    NSMutableDictionary *_fileSessions;   /* dc → NSValue(ngmt_session *) */
    NSCache *_imageCache;
    NSMutableDictionary *_imageWaiters;   /* key → [completion] */
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
        _fileQueue = dispatch_queue_create("ng.mtproto.files", DISPATCH_QUEUE_SERIAL);
        _fileSessions = [NSMutableDictionary dictionary];
        _imageCache = [NSCache new];
        _imageCache.countLimit = 300;
        _imageWaiters = [NSMutableDictionary dictionary];
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
            if (!n->is_string) return [NSData dataWithBytes:n->bytes length:n->len];
            NSString *s = [[NSString alloc] initWithBytes:n->bytes length:n->len encoding:NSUTF8StringEncoding];
            return s ?: @"";
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
    user.userId = [uid longLongValue];
    if (u[@"access_hash"]) user.accessHash = [u[@"access_hash"] longLongValue];
    NSDictionary *photo = u[@"photo"];
    if ([photo[@"_"] isEqualToString:@"userProfilePhoto"]) {
        user.photoId = [photo[@"photo_id"] longLongValue];
        user.photoDc = [photo[@"dc_id"] intValue];
        user.photoStripped = [photo[@"stripped_thumb"] isKindOfClass:[NSData class]] ? photo[@"stripped_thumb"] : nil;
    } else {
        user.photoId = 0;
    }
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
    NSDictionary *photoInfo = nil;
    NSDictionary *media = m[@"media"];
    if ([media[@"_"] isEqualToString:@"messageMediaPhoto"] && [media[@"photo"][@"_"] isEqualToString:@"photo"]) {
        NSDictionary *photo = media[@"photo"];
        // The largest size no bigger than 800px ("x"), else the smallest.
        NSDictionary *best = nil, *smallest = nil;
        NSData *stripped = nil;
        for (NSDictionary *size in photo[@"sizes"]) {
            NSString *st = size[@"_"];
            if ([st isEqualToString:@"photoStrippedSize"]) { stripped = size[@"bytes"]; continue; }
            if (![st isEqualToString:@"photoSize"] && ![st isEqualToString:@"photoSizeProgressive"]) continue;
            int w = [size[@"w"] intValue], h = [size[@"h"] intValue];
            if (!smallest || w * h < [smallest[@"w"] intValue] * [smallest[@"h"] intValue]) smallest = size;
            if (MAX(w, h) <= 800 && (!best || w * h > [best[@"w"] intValue] * [best[@"h"] intValue])) best = size;
        }
        if (!best) best = smallest;
        if (best) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[@"id"] = photo[@"id"];
            info[@"access_hash"] = photo[@"access_hash"];
            info[@"file_reference"] = photo[@"file_reference"] ?: [NSData data];
            info[@"dc"] = photo[@"dc_id"];
            info[@"type"] = best[@"type"];
            info[@"w"] = best[@"w"];
            info[@"h"] = best[@"h"];
            if (stripped) info[@"stripped"] = stripped;
            photoInfo = info;
        }
        if ([text isEqualToString:@"🖼 Фото"]) text = @"";
    }
    NGMessage *msg = [NGMessage messageWithText:text ?: @"" outgoing:[m[@"out"] boolValue] date:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
    msg.photo = photoInfo;
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
                    NSDictionary *gp = g[@"photo"];
                    if ([gp[@"_"] isEqualToString:@"chatPhoto"]) {
                        chat.photoId = [gp[@"photo_id"] longLongValue];
                        chat.photoDc = [gp[@"dc_id"] intValue];
                        chat.photoStripped = [gp[@"stripped_thumb"] isKindOfClass:[NSData class]] ? gp[@"stripped_thumb"] : nil;
                    }
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


#pragma mark - Contacts

- (void)loadContacts:(void (^)(NSArray *, NSString *))completion {
    dispatch_async(_queue, ^{
        ngmt_buf q = {0};
        ngmt_put_int(&q, 0x5dd69e12);   /* contacts.getContacts */
        ngmt_put_long(&q, 0);
        NSString *error = nil;
        NSDictionary *result = [self callObject:&q error:&error];
        ngmt_buf_free(&q);
        NSMutableArray *users = nil;
        if (result) {
            users = [NSMutableArray array];
            for (NSDictionary *u in result[@"users"]) {
                if ([u[@"_"] isEqualToString:@"user"]) [users addObject:[self userFrom:u]];
            }
            [users sortUsingComparator:^NSComparisonResult(NGUser *a, NGUser *b) {
                if (a.online != b.online) return a.online ? NSOrderedAscending : NSOrderedDescending;
                return [[a displayName] localizedCaseInsensitiveCompare:[b displayName]];
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(users, error); });
    });
}

#pragma mark - Files

+ (UIImage *)imageFromStrippedThumb:(NSData *)data {
    // TinyThumbnail.swift: decodeTinyThumbnail
    static NSData *header, *footer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        header = [[NSData alloc] initWithBase64EncodedStringCompat:@"/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDACgcHiMeGSgjISMtKygwPGRBPDc3PHtYXUlkkYCZlo+AjIqgtObDoKrarYqMyP/L2u71////m8H////6/+b9//j/2wBDASstLTw1PHZBQXb4pYyl+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj/wAARCAAAAAADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwA="];
        footer = [[NSData alloc] initWithBase64EncodedStringCompat:@"/9k="];
    });
    if (data.length < 3) return nil;
    const uint8_t *bytes = data.bytes;
    if (bytes[0] != 1) return nil;
    NSMutableData *jpeg = [header mutableCopy];
    [jpeg appendData:[data subdataWithRange:NSMakeRange(3, data.length - 3)]];
    [jpeg appendData:footer];
    uint8_t *out = jpeg.mutableBytes;
    out[164] = bytes[1];
    out[166] = bytes[2];
    return [UIImage imageWithData:jpeg];
}

static NSString *NGCachePath(NSString *key) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"ng-media"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:[key stringByAppendingString:@".jpg"]];
}

- (UIImage *)cachedImageForKey:(NSString *)key {
    UIImage *image = [_imageCache objectForKey:key];
    if (image) return image;
    NSData *data = [NSData dataWithContentsOfFile:NGCachePath(key)];
    image = data ? [UIImage imageWithData:data] : nil;
    if (image) [_imageCache setObject:image forKey:key];
    return image;
}

// A session on a DC for files: the account's own key there (a fresh session
// id) or, on another DC, a key of its own plus the exported authorization.
- (ngmt_session *)fileSessionForDC:(int)dc error:(NSString **)error {
    NSValue *existing = _fileSessions[@(dc)];
    if (existing) return existing.pointerValue;
    __block int homeDc = 0;
    __block NSData *homeKey = nil;
    __block uint64_t homeSalt = 0;
    dispatch_sync(_queue, ^{
        homeDc = self->_dc;
        if (ngmt_has_auth_key(self->_session)) {
            homeKey = [NSData dataWithBytes:ngmt_auth_key(self->_session) length:256];
            homeSalt = ngmt_server_salt(self->_session);
        }
    });
    ngmt_session *s = ngmt_session_new();
    NSString *host = NGDatacenterAddress(dc, NG_TEST_SERVERS);
    if (ngmt_connect(s, host.UTF8String, 443, dc, NG_TEST_SERVERS) != NGMT_OK) {
        *error = [NSString stringWithUTF8String:ngmt_last_error(s)];
        ngmt_session_free(s);
        return NULL;
    }
    NSString *storeKey = [NSString stringWithFormat:@"ng.mtproto.dc%d", dc];
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:storeKey];
    if (dc == homeDc && homeKey) {
        ngmt_set_auth_key(s, homeKey.bytes, homeSalt);
    } else if ([stored[@"key"] length] == 256 && [stored[@"authorized"] boolValue]) {
        ngmt_set_auth_key(s, [stored[@"key"] bytes], [stored[@"salt"] unsignedLongLongValue]);
    } else {
        if (ngmt_create_auth_key(s) != NGMT_OK) {
            *error = [NSString stringWithUTF8String:ngmt_last_error(s)];
            ngmt_session_free(s);
            return NULL;
        }
        // auth.exportAuthorization on the home DC, auth.importAuthorization here.
        __block NSDictionary *exported = nil;
        __block NSString *exportError = nil;
        dispatch_sync(_queue, ^{
            ngmt_buf q = {0};
            ngmt_put_int(&q, 0xe5bfffcd);
            ngmt_put_int(&q, (uint32_t)dc);
            NSString *e = nil;
            exported = [self callObject:&q error:&e];
            exportError = e;
            ngmt_buf_free(&q);
        });
        if (!exported) { *error = exportError; ngmt_session_free(s); return NULL; }
        ngmt_buf imp = {0}, wrapped = {0}, result = {0};
        ngmt_put_int(&imp, 0xa57a7dad);
        ngmt_put_long(&imp, (uint64_t)[exported[@"id"] longLongValue]);
        NSData *bytes = exported[@"bytes"];
        ngmt_put_string(&imp, bytes.bytes, bytes.length);
        [self wrapQuery:&imp into:&wrapped];
        int code = 0;
        char message[128] = {0};
        int rc = ngmt_call(s, wrapped.data, wrapped.len, &result, &code, message, sizeof(message));
        ngmt_buf_free(&imp); ngmt_buf_free(&wrapped); ngmt_buf_free(&result);
        if (rc != NGMT_OK) {
            *error = rc == NGMT_RPC_ERROR ? [NSString stringWithUTF8String:message] : [NSString stringWithUTF8String:ngmt_last_error(s)];
            ngmt_session_free(s);
            return NULL;
        }
        [[NSUserDefaults standardUserDefaults] setObject:@{ @"key": [NSData dataWithBytes:ngmt_auth_key(s) length:256], @"salt": @(ngmt_server_salt(s)), @"authorized": @YES } forKey:storeKey];
    }
    _fileSessions[@(dc)] = [NSValue valueWithPointer:s];
    return s;
}

// upload.getFile in 512 KB parts.
- (NSData *)downloadFromDC:(int)dc location:(void (^)(ngmt_buf *q))location error:(NSString **)error {
    NSMutableData *file = [NSMutableData data];
    const int limit = 512 * 1024;
    for (int attempt = 0; attempt < 2; attempt++) {
        ngmt_session *s = [self fileSessionForDC:dc error:error];
        if (!s) return nil;
        BOOL failed = NO;
        for (;;) {
            ngmt_buf q = {0}, wrapped = {0}, result = {0};
            ngmt_put_int(&q, 0xbe5335be);
            ngmt_put_int(&q, 0);
            location(&q);
            ngmt_put_long(&q, file.length);
            ngmt_put_int(&q, limit);
            [self wrapQuery:&q into:&wrapped];
            int code = 0;
            char message[128] = {0};
            int rc = ngmt_call(s, wrapped.data, wrapped.len, &result, &code, message, sizeof(message));
            ngmt_buf_free(&q); ngmt_buf_free(&wrapped);
            if (rc != NGMT_OK) {
                *error = rc == NGMT_RPC_ERROR ? [NSString stringWithUTF8String:message] : [NSString stringWithUTF8String:ngmt_last_error(s)];
                ngmt_buf_free(&result);
                if (rc == NGMT_RPC_ERROR) return nil;
                failed = YES;
                break;
            }
            char perr[64];
            ngtl_node *node = ngtl_decode(result.data, result.len, perr, sizeof(perr));
            ngmt_buf_free(&result);
            const ngtl_node *bytes = ngtl_get(node, "bytes");
            if (!node || !bytes) { ngtl_free(node); *error = @"Неожиданный ответ upload.getFile"; return nil; }
            [file appendBytes:bytes->bytes length:bytes->len];
            BOOL last = (int)bytes->len < limit;
            ngtl_free(node);
            if (last) return file;
        }
        if (failed) {
            ngmt_session_free(s);
            [_fileSessions removeObjectForKey:@(dc)];
            [file setLength:0];
        }
    }
    return nil;
}

- (void)loadImageForKey:(NSString *)key dc:(int)dc location:(void (^)(ngmt_buf *q))location completion:(void (^)(UIImage *))completion {
    UIImage *cached = [self cachedImageForKey:key];
    if (cached) { completion(cached); return; }
    NSMutableArray *waiters = _imageWaiters[key];
    if (waiters) { [waiters addObject:[completion copy]]; return; }
    _imageWaiters[key] = [NSMutableArray arrayWithObject:[completion copy]];
    dispatch_async(_fileQueue, ^{
        NSString *error = nil;
        NSData *data = [self downloadFromDC:dc location:location error:&error];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (image) [data writeToFile:NGCachePath(key) atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *list = self->_imageWaiters[key];
            [self->_imageWaiters removeObjectForKey:key];
            if (!image) return;
            [self->_imageCache setObject:image forKey:key];
            for (void (^waiter)(UIImage *) in list) waiter(image);
        });
    });
}

- (void)loadAvatarForUser:(id)userObject completion:(void (^)(UIImage *))completion {
    NGUser *user = userObject;
    if (!user.photoId || !user.userId) return;
    int64_t uid = user.userId, hash = user.accessHash, photoId = user.photoId;
    NSString *key = [NSString stringWithFormat:@"a%lld_%lld", uid, photoId];
    [self loadImageForKey:key dc:user.photoDc ?: _dc location:^(ngmt_buf *q) {
        ngmt_put_int(q, 0x37257e99);   /* inputPeerPhotoFileLocation */
        ngmt_put_int(q, 0);
        ngmt_put_int(q, 0xdde8a54c);   /* inputPeerUser */
        ngmt_put_long(q, (uint64_t)uid);
        ngmt_put_long(q, (uint64_t)hash);
        ngmt_put_long(q, (uint64_t)photoId);
    } completion:completion];
}

- (void)loadAvatarForChat:(id)chatObject completion:(void (^)(UIImage *))completion {
    NGChat *chat = chatObject;
    if (chat.kind == NGChatKindPrivate && chat.user) { [self loadAvatarForUser:chat.user completion:completion]; return; }
    if (!chat.photoId || !chat.peerKey) return;
    NSString *key = [NSString stringWithFormat:@"a%@_%lld", chat.peerKey, chat.photoId];
    int64_t peerId = chat.peerId, hash = chat.accessHash, photoId = chat.photoId;
    BOOL channel = [chat.peerKey hasPrefix:@"h"];
    [self loadImageForKey:key dc:chat.photoDc ?: _dc location:^(ngmt_buf *q) {
        ngmt_put_int(q, 0x37257e99);
        ngmt_put_int(q, 0);
        if (channel) {
            ngmt_put_int(q, 0x27bcbbfc);
            ngmt_put_long(q, (uint64_t)peerId);
            ngmt_put_long(q, (uint64_t)hash);
        } else {
            ngmt_put_int(q, 0x35a95cb9);
            ngmt_put_long(q, (uint64_t)peerId);
        }
        ngmt_put_long(q, (uint64_t)photoId);
    } completion:completion];
}

- (void)loadPhoto:(NSDictionary *)photo completion:(void (^)(UIImage *))completion {
    if (!photo) return;
    NSString *key = [NSString stringWithFormat:@"p%@_%@", photo[@"id"], photo[@"type"]];
    uint64_t pid = (uint64_t)[photo[@"id"] longLongValue], hash = (uint64_t)[photo[@"access_hash"] longLongValue];
    NSData *ref = photo[@"file_reference"];
    NSString *type = photo[@"type"];
    [self loadImageForKey:key dc:[photo[@"dc"] intValue] ?: _dc location:^(ngmt_buf *q) {
        ngmt_put_int(q, 0x40181ffe);   /* inputPhotoFileLocation */
        ngmt_put_long(q, pid);
        ngmt_put_long(q, hash);
        ngmt_put_string(q, ref.bytes, ref.length);
        ngmt_put_cstring(q, type.UTF8String);
    } completion:completion];
}

@end
