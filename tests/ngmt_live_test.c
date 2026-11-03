/* Live test on Telegram's test DC 2 with a test account (+99966 2 XXXX, code 22222):
 * auth.sendCode, auth.signIn (auth.signUp for a new number), messages.getDialogs,
 * contacts.getContacts, each answer decoded by the schema-driven decoder.
 * NG_API_ID / NG_API_HASH come from the environment; NGMT_HTTP=1 for the HTTP transport.
 * Build: cc -O2 -I../Sources/mtproto ngmt_live_test.c ../Sources/mtproto/ngmt.c ../Sources/mtproto/ngtl.c ../Sources/mtproto/ngtl_schema.c -lssl -lcrypto -lz */
#include "ngmt.h"
#include "ngtl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int api_id;
static const char *api_hash;

static int call(ngmt_session *s, ngmt_buf *q, ngtl_node **out, char *err) {
    ngmt_buf w = {0}, r = {0};
    static int inited = 0;
    if (!inited || !getenv("NG_INIT_ONCE")) {
        ngmt_put_int(&w, 0xda9b0d0d); ngmt_put_int(&w, 232);
        ngmt_put_int(&w, 0xc1cd5ea9); ngmt_put_int(&w, 0); ngmt_put_int(&w, (uint32_t)api_id);
        ngmt_put_cstring(&w, "test"); ngmt_put_cstring(&w, "Linux"); ngmt_put_cstring(&w, "0.1");
        ngmt_put_cstring(&w, "en"); ngmt_put_cstring(&w, ""); ngmt_put_cstring(&w, "en");
        inited = 1;
    }
    ngmt_put_bytes_raw(&w, q->data, q->len);
    int code = 0;
    int rc = ngmt_call(s, w.data, w.len, &r, &code, err, 128);
    ngmt_buf_free(&w);
    if (rc == NGMT_OK) {
        char derr[128];
        *out = ngtl_decode(r.data, r.len, derr, sizeof(derr));
        if (!*out) { snprintf(err, 128, "decode: %s", derr); rc = -9; }
    } else if (rc != NGMT_RPC_ERROR) {
        snprintf(err, 128, "%s", ngmt_last_error(s));
    }
    ngmt_buf_free(&r);
    return rc;
}

int main(void) {
    api_id = getenv("NG_API_ID") ? atoi(getenv("NG_API_ID")) : 0;
    api_hash = getenv("NG_API_HASH");
    if (!api_id || !api_hash) { printf("set NG_API_ID and NG_API_HASH\n"); return 2; }
    ngmt_session *s = ngmt_session_new();
    int dc = getenv("NG_DC") ? atoi(getenv("NG_DC")) : 2;
    const char *ip = dc == 1 ? "149.154.175.10" : dc == 3 ? "149.154.175.117" : "149.154.167.40";
    int rc = getenv("NGMT_HTTP") ? ngmt_connect_http(s, ip, 80, dc, 1, NULL, 0) : ngmt_connect(s, ip, 443, dc, 1);
    if (rc || ngmt_create_auth_key(s)) { printf("connect/key: %s\n", ngmt_last_error(s)); return 1; }

    char phone[16], err[128];
    if (getenv("NG_PING")) printf("ping %d\n", ngmt_ping(s));
    srand((unsigned)time(NULL));
    snprintf(phone, sizeof(phone), "99966%d%04d", dc, rand() % 10000);
    ngmt_buf q = {0};
    ngtl_node *n = NULL;
    ngmt_put_int(&q, 0xa677244f); ngmt_put_cstring(&q, phone); ngmt_put_int(&q, (uint32_t)api_id);
    ngmt_put_cstring(&q, api_hash); ngmt_put_int(&q, 0xad253d78); ngmt_put_int(&q, 0);
    if (call(s, &q, &n, err)) { printf("sendCode %s: %s\n", phone, err); return 1; }
    const ngtl_node *hash = ngtl_get(n, "phone_code_hash");
    const ngtl_node *type = ngtl_get(n, "type");
    printf("auth.sendCode %s -> %s, type %s\n", phone, n->ctor, type ? type->ctor : "?");
    const ngtl_node *length = type ? ngtl_get(type, "length") : NULL;
    char code[16] = {0};
    int len = length ? (int)length->i : 5;
    if (getenv("NG_CODE_LEN")) len = atoi(getenv("NG_CODE_LEN"));
    for (int i = 0; i < len && i < 15; i++) code[i] = (char)('0' + dc);   /* the DC, repeated */
    printf("code length %d -> %s, hash %zu bytes [%s]\n", len, code, hash ? hash->len : 0, hash ? (char *)hash->bytes : "");
    char code_hash[256];
    snprintf(code_hash, sizeof(code_hash), "%s", hash ? (char *)hash->bytes : "");
    ngtl_free(n);

    q.len = 0;
    ngmt_put_int(&q, 0x8d52a951); ngmt_put_int(&q, 1); ngmt_put_cstring(&q, phone);
    ngmt_put_cstring(&q, code_hash); ngmt_put_cstring(&q, code);
    if (call(s, &q, &n, err)) { printf("signIn: %s\n", err); return 1; }
    printf("auth.signIn -> %s\n", n->ctor);
    if (strcmp(n->ctor, "auth.authorizationSignUpRequired") == 0) {
        ngtl_free(n);
        q.len = 0;
        ngmt_put_int(&q, 0xaac7b717); ngmt_put_int(&q, 0); ngmt_put_cstring(&q, phone);
        ngmt_put_cstring(&q, code_hash); ngmt_put_cstring(&q, "Nogram"); ngmt_put_cstring(&q, "Test");
        if (call(s, &q, &n, err)) { printf("signUp: %s\n", err); return 1; }
        printf("auth.signUp -> %s\n", n->ctor);
    }
    const ngtl_node *user = ngtl_get(n, "user");
    printf("signed in as %s (id %lld)\n", user ? (char *)ngtl_get(user, "first_name")->bytes : "?", user ? (long long)ngtl_get(user, "id")->i : 0);
    ngtl_free(n);

    q.len = 0;
    ngmt_put_int(&q, 0xa0f4cb4f); ngmt_put_int(&q, 0); ngmt_put_int(&q, 0); ngmt_put_int(&q, 0);
    ngmt_put_int(&q, 0x7f3b18ea); ngmt_put_int(&q, 100); ngmt_put_long(&q, 0);
    if (call(s, &q, &n, err)) { printf("getDialogs: %s\n", err); return 1; }
    printf("messages.getDialogs -> %s: %d dialogs, %d messages, %d users\n", n->ctor,
           ngtl_get(n, "dialogs")->count, ngtl_get(n, "messages")->count, ngtl_get(n, "users")->count);
    ngtl_free(n);

    q.len = 0;
    ngmt_put_int(&q, 0x5dd69e12); ngmt_put_long(&q, 0);
    if (call(s, &q, &n, err)) { printf("getContacts: %s\n", err); return 1; }
    printf("contacts.getContacts -> %s\n", n->ctor);
    ngtl_free(n);
    ngmt_buf_free(&q);
    ngmt_session_free(s);
    return 0;
}
