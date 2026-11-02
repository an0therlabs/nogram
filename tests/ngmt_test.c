/* Host test for the MTProto core: checks the bignum and AES-IGE against
 * OpenSSL, then creates a real auth key on Telegram's test DC 2 and pings.
 * Build: cc -O2 -I../Sources/mtproto ngmt_test.c -lssl -lcrypto -lz -o ngmt_test */
#include "../Sources/mtproto/ngmt.c"
#include <openssl/bn.h>
#include <assert.h>

static int check_modexp(void) {
    BN_CTX *ctx = BN_CTX_new();
    for (int t = 0; t < 40; t++) {
        uint8_t m[256], b[256], e[256];
        int mlen = t < 20 ? 256 : 128;
        ngmt_random(m, mlen); m[0] |= 0x80; m[mlen - 1] |= 1;
        ngmt_random(b, mlen); b[0] &= 0x7f;
        int elen = t % 2 ? 4 : mlen;
        ngmt_random(e, elen);
        bn bm, bb, be, br;
        bn_from_bytes(&bm, m, mlen); bn_from_bytes(&bb, b, mlen); bn_from_bytes(&be, e, elen);
        bn_modexp(&br, &bb, &be, &bm);
        uint8_t mine[256]; bn_to_bytes(&br, mine, mlen);
        BIGNUM *M = BN_bin2bn(m, mlen, NULL), *B = BN_bin2bn(b, mlen, NULL), *E = BN_bin2bn(e, elen, NULL), *R = BN_new();
        BN_mod_exp(R, B, E, M, ctx);
        uint8_t theirs[256]; BN_bn2binpad(R, theirs, mlen);
        if (memcmp(mine, theirs, mlen)) { printf("modexp mismatch at %d\n", t); return 1; }
        BN_free(M); BN_free(B); BN_free(E); BN_free(R);
    }
    BN_CTX_free(ctx);
    printf("modexp: 40 random cases match OpenSSL\n");
    return 0;
}

static int check_ige(void) {
    uint8_t key[32], iv[32], in[64], out[64], back[64], ref[64];
    ngmt_random(key, 32); ngmt_random(iv, 32); ngmt_random(in, 64);
    ngmt_aes_ige(in, out, 64, key, iv, 1);
    AES_KEY k; AES_set_encrypt_key(key, 256, &k);
    uint8_t iv2[32]; memcpy(iv2, iv, 32);
    AES_ige_encrypt(in, ref, 64, &k, iv2, AES_ENCRYPT);
    if (memcmp(out, ref, 64)) { printf("IGE encrypt mismatch\n"); return 1; }
    ngmt_aes_ige(out, back, 64, key, iv, 0);
    if (memcmp(back, in, 64)) { printf("IGE decrypt mismatch\n"); return 1; }
    printf("AES-256-IGE: matches OpenSSL, round-trips\n");
    return 0;
}

int main(void) {
    if (check_modexp() || check_ige()) return 1;
    uint64_t pq = 1724114033281923457ULL;   /* example pq from the MTProto docs */
    uint64_t p = factorize(pq);
    printf("factorize(%llu) = %llu * %llu\n", (unsigned long long)pq, (unsigned long long)p, (unsigned long long)(pq / p));

    ngmt_session *s = ngmt_session_new();
    /* NGMT_HTTP=1: MTProto's HTTP transport (where raw MTProto TCP is blocked). */
    int rc;
    if (getenv("NGMT_HTTP")) {
        rc = ngmt_connect_http(s, "149.154.167.40", 80, 2, 1, NULL, 0);
    } else {
        rc = ngmt_connect(s, "149.154.167.40", 443, 2, 1);
    }
    if (rc) { printf("connect: %s\n", ngmt_last_error(s)); return 1; }
    if (ngmt_create_auth_key(s)) { printf("auth key: %s\n", ngmt_last_error(s)); return 1; }
    printf("auth key created on test DC 2, salt %016llx\n", (unsigned long long)ngmt_server_salt(s));
    if (ngmt_ping(s)) { printf("ping: %s\n", ngmt_last_error(s)); return 1; }
    printf("encrypted ping/pong OK\n");
    {
        ngmt_buf q = {0}, res = {0};
        ngmt_put_int(&q, 0xda9b0d0d); ngmt_put_int(&q, 232);
        ngmt_put_int(&q, 0xc1cd5ea9); ngmt_put_int(&q, 0); ngmt_put_int(&q, 0);
        ngmt_put_cstring(&q, "test"); ngmt_put_cstring(&q, "Linux"); ngmt_put_cstring(&q, "0.1");
        ngmt_put_cstring(&q, "en"); ngmt_put_cstring(&q, ""); ngmt_put_cstring(&q, "en");
        ngmt_put_int(&q, 0xc4f9186b);   /* help.getConfig */
        int code = 0; char msg[128] = {0};
        int rc = ngmt_call(s, q.data, q.len, &res, &code, msg, sizeof(msg));
        if (rc == NGMT_RPC_ERROR) printf("initConnection(help.getConfig) with api_id 0 -> rpc_error %d %s\n", code, msg);
        else if (rc == NGMT_OK) printf("help.getConfig -> %zu bytes, constructor %02x%02x%02x%02x\n", res.len, res.data[3], res.data[2], res.data[1], res.data[0]);
        else { printf("call: %s\n", ngmt_last_error(s)); return 1; }
    }
    ngmt_session_free(s);
    return 0;
}
