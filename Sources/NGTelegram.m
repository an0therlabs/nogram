#import "NGTelegram.h"
#import "NGConfig.h"
#import "ngmt.h"
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

@end
