/* Host test for the schema-driven TL decoder.
 * Build: cc -O2 -I../Sources/mtproto ngtl_test.c ../Sources/mtproto/ngtl.c ../Sources/mtproto/ngtl_schema.c ../Sources/mtproto/ngmt.c -lssl -lcrypto -lz */
#include "ngmt.h"
#include "ngtl.h"
#include <stdio.h>
#include <string.h>

int main(void) {
    ngmt_buf b = {0};
    ngmt_put_int(&b, 0x15ba6c40);            /* messages.dialogs */
    ngmt_put_int(&b, 0x1cb5c415); ngmt_put_int(&b, 0);   /* dialogs: [] */
    ngmt_put_int(&b, 0x1cb5c415); ngmt_put_int(&b, 0);   /* messages: [] */
    ngmt_put_int(&b, 0x1cb5c415); ngmt_put_int(&b, 0);   /* chats: [] */
    ngmt_put_int(&b, 0x1cb5c415); ngmt_put_int(&b, 1);   /* users: [user] */
    ngmt_put_int(&b, 0xb1b8cc83);
    ngmt_put_int(&b, (1u << 0) | (1u << 1) | (1u << 4) | (1u << 6) | (1u << 10));   /* access_hash, first_name, phone, status, self */
    ngmt_put_int(&b, 0);                     /* flags2 */
    ngmt_put_long(&b, 777000);
    ngmt_put_long(&b, 0x1122334455667788ull);
    ngmt_put_cstring(&b, "Иван");
    ngmt_put_cstring(&b, "79991234567");
    ngmt_put_int(&b, 0xedb93949); ngmt_put_int(&b, 1700000000);   /* userStatusOnline */
    char err[128];
    ngtl_node *n = ngtl_decode(b.data, b.len, err, sizeof(err));
    if (!n) { printf("decode failed: %s\n", err); return 1; }
    const ngtl_node *users = ngtl_get(n, "users");
    const ngtl_node *u = users && users->count ? users->items[0] : NULL;
    const ngtl_node *status = ngtl_get(u, "status");
    printf("%s users=%d user=%s id=%lld first_name=%s phone=%s self=%lld status=%s expires=%lld consumed=%s\n",
           n->ctor, users ? users->count : -1, u ? u->ctor : "-", (long long)ngtl_get(u, "id")->i,
           ngtl_get(u, "first_name")->bytes, ngtl_get(u, "phone")->bytes, (long long)ngtl_get(u, "self")->i,
           status ? status->ctor : "-", status ? (long long)ngtl_get(status, "expires")->i : -1, "ok");
    int ok = strcmp(n->ctor, "messages.dialogs") == 0 && u && ngtl_get(u, "id")->i == 777000 && status && ngtl_get(u, "last_name") == NULL;
    ngtl_free(n);
    /* truncated input must fail cleanly */
    n = ngtl_decode(b.data, b.len - 6, err, sizeof(err));
    printf("truncated -> %s (%s)\n", n ? "decoded?!" : "rejected", err);
    ngmt_buf_free(&b);
    return ok && !n ? 0 : 1;
}
