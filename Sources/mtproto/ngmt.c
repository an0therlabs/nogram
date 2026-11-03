#include "ngmt.h"

#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>

#ifdef __APPLE__
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <Security/SecRandom.h>
#else
#include <openssl/aes.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#endif

/* ===================================================================== */
/* Crypto primitives                                                      */
/* ===================================================================== */

static void ngmt_sha1(const void *data, size_t len, uint8_t out[20]) {
#ifdef __APPLE__
    CC_SHA1(data, (CC_LONG)len, out);
#else
    SHA1((const unsigned char *)data, len, out);
#endif
}

static void ngmt_sha256(const void *data, size_t len, uint8_t out[32]) {
#ifdef __APPLE__
    CC_SHA256(data, (CC_LONG)len, out);
#else
    SHA256((const unsigned char *)data, len, out);
#endif
}

static void ngmt_random(void *out, size_t len) {
#ifdef __APPLE__
    if (SecRandomCopyBytes(kSecRandomDefault, len, (uint8_t *)out) == 0) return;
#else
    if (RAND_bytes((unsigned char *)out, (int)len) == 1) return;
#endif
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        size_t got = fread(out, 1, len, f);
        (void)got;
        fclose(f);
    }
}

/* AES-256 in IGE mode, built on a single-block ECB primitive. */
typedef struct {
#ifdef __APPLE__
    CCCryptorRef cryptor;
#else
    AES_KEY key;
#endif
    int encrypt;
} ngmt_aes;

static void ngmt_aes_init(ngmt_aes *a, const uint8_t key[32], int encrypt) {
    a->encrypt = encrypt;
#ifdef __APPLE__
    CCCryptorCreate(encrypt ? kCCEncrypt : kCCDecrypt, kCCAlgorithmAES128, kCCOptionECBMode, key, 32, NULL, &a->cryptor);
#else
    if (encrypt) AES_set_encrypt_key(key, 256, &a->key);
    else AES_set_decrypt_key(key, 256, &a->key);
#endif
}

static void ngmt_aes_block(ngmt_aes *a, const uint8_t in[16], uint8_t out[16]) {
#ifdef __APPLE__
    size_t moved = 0;
    CCCryptorUpdate(a->cryptor, in, 16, out, 16, &moved);
#else
    if (a->encrypt) AES_encrypt(in, out, &a->key);
    else AES_decrypt(in, out, &a->key);
#endif
}

static void ngmt_aes_free(ngmt_aes *a) {
#ifdef __APPLE__
    CCCryptorRelease(a->cryptor);
#else
    (void)a;
#endif
}

/* iv: 32 bytes, iv1 (previous ciphertext) then iv2 (previous plaintext). */
static void ngmt_aes_ige(const uint8_t *in, uint8_t *out, size_t len, const uint8_t key[32], const uint8_t iv[32], int encrypt) {
    ngmt_aes aes;
    ngmt_aes_init(&aes, key, encrypt);
    uint8_t x[16], y[16], tmp[16], block[16];
    /* encrypt: x = previous ciphertext (iv1), y = previous plaintext (iv2)
       decrypt: x = previous plaintext (iv2), y = previous ciphertext (iv1) */
    if (encrypt) {
        memcpy(x, iv, 16);
        memcpy(y, iv + 16, 16);
    } else {
        memcpy(x, iv + 16, 16);
        memcpy(y, iv, 16);
    }
    for (size_t off = 0; off < len; off += 16) {
        memcpy(block, in + off, 16);
        for (int i = 0; i < 16; i++) tmp[i] = block[i] ^ x[i];
        ngmt_aes_block(&aes, tmp, tmp);
        for (int i = 0; i < 16; i++) tmp[i] ^= y[i];
        memcpy(out + off, tmp, 16);
        memcpy(x, tmp, 16);
        memcpy(y, block, 16);
    }
    ngmt_aes_free(&aes);
}

/* ===================================================================== */
/* Big integers (Montgomery modexp, 32-bit limbs, little-endian limbs)    */
/* ===================================================================== */

#define BN_MAX 72   /* 2304 bits: enough for 2048-bit moduli plus headroom */

typedef struct {
    uint32_t d[BN_MAX];
    int n;   /* used limbs */
} bn;

static void bn_from_bytes(bn *r, const uint8_t *p, size_t len) {
    memset(r, 0, sizeof(*r));
    int limb = 0, shift = 0;
    for (size_t i = len; i-- > 0;) {
        r->d[limb] |= (uint32_t)p[i] << shift;
        shift += 8;
        if (shift == 32) { shift = 0; limb++; if (limb >= BN_MAX) break; }
    }
    r->n = BN_MAX;
    while (r->n > 0 && r->d[r->n - 1] == 0) r->n--;
}

/* Big-endian, left-padded with zeros to len bytes. */
static void bn_to_bytes(const bn *a, uint8_t *p, size_t len) {
    memset(p, 0, len);
    for (size_t i = 0; i < len; i++) {
        size_t limb = i / 4, shift = (i % 4) * 8;
        if (limb < BN_MAX) p[len - 1 - i] = (uint8_t)(a->d[limb] >> shift);
    }
}

static int bn_cmp(const bn *a, const bn *b) {
    for (int i = BN_MAX - 1; i >= 0; i--) {
        if (a->d[i] != b->d[i]) return a->d[i] > b->d[i] ? 1 : -1;
    }
    return 0;
}

/* r = a - b, assuming a >= b, over k limbs. */
static void bn_sub_k(uint32_t *r, const uint32_t *a, const uint32_t *b, int k) {
    uint64_t borrow = 0;
    for (int i = 0; i < k; i++) {
        uint64_t t = (uint64_t)a[i] - b[i] - borrow;
        r[i] = (uint32_t)t;
        borrow = (t >> 63) & 1;
    }
}

/* Montgomery multiplication: r = a * b * R^-1 mod m, k limbs, m odd. */
static void bn_mont_mul(uint32_t *r, const uint32_t *a, const uint32_t *b, const uint32_t *m, uint32_t m0inv, int k) {
    uint32_t t[BN_MAX + 2];
    memset(t, 0, sizeof(uint32_t) * (size_t)(k + 2));
    for (int i = 0; i < k; i++) {
        uint64_t carry = 0;
        for (int j = 0; j < k; j++) {
            uint64_t s = (uint64_t)a[j] * b[i] + t[j] + carry;
            t[j] = (uint32_t)s;
            carry = s >> 32;
        }
        uint64_t s = (uint64_t)t[k] + carry;
        t[k] = (uint32_t)s;
        t[k + 1] = (uint32_t)(s >> 32);

        uint32_t u = t[0] * m0inv;
        carry = ((uint64_t)u * m[0] + t[0]) >> 32;
        for (int j = 1; j < k; j++) {
            uint64_t s2 = (uint64_t)u * m[j] + t[j] + carry;
            t[j - 1] = (uint32_t)s2;
            carry = s2 >> 32;
        }
        s = (uint64_t)t[k] + carry;
        t[k - 1] = (uint32_t)s;
        t[k] = t[k + 1] + (uint32_t)(s >> 32);
        t[k + 1] = 0;
    }
    /* if t >= m: t -= m */
    int ge = t[k] != 0;
    if (!ge) {
        ge = 1;
        for (int i = k - 1; i >= 0; i--) {
            if (t[i] != m[i]) { ge = t[i] > m[i]; break; }
        }
    }
    if (ge) bn_sub_k(r, t, m, k);
    else memcpy(r, t, sizeof(uint32_t) * (size_t)k);
}

/* r = base^exp mod m (m odd). */
static void bn_modexp(bn *r, const bn *base, const bn *exp, const bn *m) {
    int k = m->n;
    uint32_t m0inv = 1;   /* -m^-1 mod 2^32 via Newton */
    for (int i = 0; i < 5; i++) m0inv *= 2 - m->d[0] * m0inv;
    m0inv = (uint32_t)(0 - m0inv);

    /* R mod m and R^2 mod m by doubling. */
    uint32_t one_m[BN_MAX] = {0}, rr[BN_MAX] = {0};
    /* start from 1, double 32*k times mod m -> R mod m */
    uint32_t x[BN_MAX + 1];
    memset(x, 0, sizeof(x));
    x[0] = 1;
    for (int step = 0; step < 64 * k; step++) {
        uint32_t carry = 0;
        for (int i = 0; i <= k; i++) {
            uint32_t nv = (x[i] << 1) | carry;
            carry = x[i] >> 31;
            x[i] = nv;
        }
        int ge = x[k] != 0;
        if (!ge) {
            ge = 1;
            for (int i = k - 1; i >= 0; i--) {
                if (x[i] != m->d[i]) { ge = x[i] > m->d[i]; break; }
            }
        }
        if (ge) {
            uint64_t borrow = 0;
            for (int i = 0; i < k; i++) {
                uint64_t t = (uint64_t)x[i] - m->d[i] - borrow;
                x[i] = (uint32_t)t;
                borrow = (t >> 63) & 1;
            }
            x[k] -= (uint32_t)borrow;
        }
        if (step == 32 * k - 1) memcpy(one_m, x, sizeof(uint32_t) * (size_t)k);
    }
    memcpy(rr, x, sizeof(uint32_t) * (size_t)k);   /* R^2 mod m */

    /* base mod m: reduce via Montgomery (base * R^2 * R^-1 = base * R), base must be < m */
    uint32_t b[BN_MAX] = {0}, acc[BN_MAX];
    bn base_red = *base;
    while (bn_cmp(&base_red, m) >= 0) {
        bn_sub_k(base_red.d, base_red.d, m->d, BN_MAX);
    }
    bn_mont_mul(b, base_red.d, rr, m->d, m0inv, k);
    memcpy(acc, one_m, sizeof(uint32_t) * (size_t)k);

    int top = exp->n * 32 - 1;
    for (int bit = top; bit >= 0; bit--) {
        bn_mont_mul(acc, acc, acc, m->d, m0inv, k);
        if ((exp->d[bit / 32] >> (bit % 32)) & 1) bn_mont_mul(acc, acc, b, m->d, m0inv, k);
    }
    uint32_t one[BN_MAX] = {0};
    one[0] = 1;
    bn_mont_mul(acc, acc, one, m->d, m0inv, k);
    memset(r, 0, sizeof(*r));
    memcpy(r->d, acc, sizeof(uint32_t) * (size_t)k);
    r->n = k;
    while (r->n > 0 && r->d[r->n - 1] == 0) r->n--;
}

/* ===================================================================== */
/* pq factorization (Pollard-Brent over 64 bits)                          */
/* ===================================================================== */

static uint64_t mulmod64(uint64_t a, uint64_t b, uint64_t m) {
    uint64_t r = 0;
    a %= m;
    while (b) {
        if (b & 1) { r += a; if (r >= m || r < a) r -= m; }
        uint64_t a2 = a << 1;
        if (a2 >= m || a2 < a) a2 -= m;
        a = a2;
        b >>= 1;
    }
    return r;
}

static uint64_t gcd64(uint64_t a, uint64_t b) {
    while (b) { uint64_t t = a % b; a = b; b = t; }
    return a;
}

static uint64_t factorize(uint64_t pq) {
    if (pq % 2 == 0) return 2;
    for (uint64_t c = 1; c < 50; c++) {
        uint64_t y = 2, x = 2, d = 1, q = 1, ys = 2, r = 1;
        uint64_t m = 64;
        do {
            x = y;
            for (uint64_t i = 0; i < r; i++) y = (mulmod64(y, y, pq) + c) % pq;
            uint64_t k = 0;
            do {
                ys = y;
                for (uint64_t i = 0; i < m && i < r - k; i++) {
                    y = (mulmod64(y, y, pq) + c) % pq;
                    q = mulmod64(q, x > y ? x - y : y - x, pq);
                }
                d = gcd64(q, pq);
                k += m;
            } while (k < r && d == 1);
            r *= 2;
        } while (d == 1);
        if (d == pq) {
            do {
                ys = (mulmod64(ys, ys, pq) + c) % pq;
                d = gcd64(x > ys ? x - ys : ys - x, pq);
            } while (d == 1);
        }
        if (d != pq && d != 1) return d;
    }
    return 0;
}

/* ===================================================================== */
/* Buffers and TL                                                         */
/* ===================================================================== */

void ngmt_buf_free(ngmt_buf *b) {
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

void ngmt_put_bytes_raw(ngmt_buf *b, const void *p, size_t n) {
    if (b->len + n > b->cap) {
        size_t cap = b->cap ? b->cap * 2 : 256;
        while (cap < b->len + n) cap *= 2;
        b->data = (uint8_t *)realloc(b->data, cap);
        b->cap = cap;
    }
    memcpy(b->data + b->len, p, n);
    b->len += n;
}

void ngmt_put_int(ngmt_buf *b, uint32_t v) {
    uint8_t x[4] = { (uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24) };
    ngmt_put_bytes_raw(b, x, 4);
}

void ngmt_put_long(ngmt_buf *b, uint64_t v) {
    ngmt_put_int(b, (uint32_t)v);
    ngmt_put_int(b, (uint32_t)(v >> 32));
}

void ngmt_put_string(ngmt_buf *b, const void *p, size_t n) {
    size_t header;
    if (n < 254) {
        uint8_t l = (uint8_t)n;
        ngmt_put_bytes_raw(b, &l, 1);
        header = 1;
    } else {
        uint8_t h[4] = { 254, (uint8_t)n, (uint8_t)(n >> 8), (uint8_t)(n >> 16) };
        ngmt_put_bytes_raw(b, h, 4);
        header = 4;
    }
    ngmt_put_bytes_raw(b, p, n);
    static const uint8_t zero[4] = {0};
    size_t total = header + n;
    if (total % 4) ngmt_put_bytes_raw(b, zero, 4 - total % 4);
}

void ngmt_put_cstring(ngmt_buf *b, const char *s) {
    ngmt_put_string(b, s, strlen(s));
}

uint32_t ngmt_get_int(ngmt_reader *r) {
    if (r->pos + 4 > r->len) { r->error = 1; return 0; }
    const uint8_t *p = r->p + r->pos;
    r->pos += 4;
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint64_t ngmt_get_long(ngmt_reader *r) {
    uint64_t lo = ngmt_get_int(r);
    uint64_t hi = ngmt_get_int(r);
    return lo | (hi << 32);
}

void ngmt_get_raw(ngmt_reader *r, void *out, size_t n) {
    if (r->pos + n > r->len) { r->error = 1; memset(out, 0, n); return; }
    memcpy(out, r->p + r->pos, n);
    r->pos += n;
}

const uint8_t *ngmt_get_string(ngmt_reader *r, size_t *n) {
    if (r->pos + 1 > r->len) { r->error = 1; *n = 0; return NULL; }
    size_t len, header;
    uint8_t first = r->p[r->pos];
    if (first < 254) {
        len = first;
        header = 1;
    } else {
        if (r->pos + 4 > r->len) { r->error = 1; *n = 0; return NULL; }
        len = (size_t)r->p[r->pos + 1] | ((size_t)r->p[r->pos + 2] << 8) | ((size_t)r->p[r->pos + 3] << 16);
        header = 4;
    }
    size_t total = header + len;
    size_t padded = (total + 3) & ~(size_t)3;
    if (r->pos + padded > r->len) { r->error = 1; *n = 0; return NULL; }
    const uint8_t *data = r->p + r->pos + header;
    r->pos += padded;
    *n = len;
    return data;
}

/* ===================================================================== */
/* Session                                                                */
/* ===================================================================== */

struct ngmt_session {
    int fd;
    int http;                 /* HTTP transport */
    char http_host[64];
    int http_port;
    char proxy_host[64];
    int proxy_port;
    ngmt_buf http_pending;    /* the last response body, not yet read */
    int http_has_pending;
    int dc_id, test;
    uint8_t auth_key[256];
    int has_key;
    uint64_t auth_key_id;
    uint64_t salt;
    uint64_t session_id;
    uint32_t seq;
    /* Content-related messages from the server not yet acknowledged; sent as
       msgs_ack in the same container as the next request. */
    uint64_t pending_acks[128];
    int pending_ack_count;
    uint64_t last_msg_id;
    int64_t time_offset;
    char error[256];
};

static void set_error(ngmt_session *s, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(s->error, sizeof(s->error), fmt, ap);
    va_end(ap);
}

const char *ngmt_last_error(const ngmt_session *s) { return s->error; }

ngmt_session *ngmt_session_new(void) {
    ngmt_session *s = (ngmt_session *)calloc(1, sizeof(ngmt_session));
    s->fd = -1;
    ngmt_random(&s->session_id, 8);
    return s;
}

void ngmt_session_free(ngmt_session *s) {
    if (!s) return;
    ngmt_disconnect(s);
    memset(s->auth_key, 0, sizeof(s->auth_key));
    free(s);
}

static uint64_t next_msg_id(ngmt_session *s) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t sec = (uint64_t)((int64_t)tv.tv_sec + s->time_offset);
    uint64_t id = (sec << 32) | ((uint64_t)tv.tv_usec * 4294u & 0xfffffffcu);
    id &= ~(uint64_t)3;
    if (id <= s->last_msg_id) id = s->last_msg_id + 4;
    s->last_msg_id = id;
    return id;
}

static int write_all(int fd, const uint8_t *p, size_t n) {
    while (n) {
        ssize_t w = send(fd, p, n, 0);
        if (w <= 0) { if (w < 0 && errno == EINTR) continue; return -1; }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

static int read_all(int fd, uint8_t *p, size_t n) {
    while (n) {
        ssize_t r = recv(fd, p, n, 0);
        if (r <= 0) { if (r < 0 && errno == EINTR) continue; return -1; }
        p += r;
        n -= (size_t)r;
    }
    return 0;
}

int ngmt_connect(ngmt_session *s, const char *host, int port, int dc_id, int test) {
    ngmt_disconnect(s);
    s->dc_id = dc_id;
    s->test = test;
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[8];
    snprintf(portstr, sizeof(portstr), "%d", port);
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
        set_error(s, "cannot resolve %s", host);
        return NGMT_ERR_IO;
    }
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) { freeaddrinfo(res); set_error(s, "socket: %s", strerror(errno)); return NGMT_ERR_IO; }
    struct timeval tv = { 15, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    if (connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
        set_error(s, "connect %s:%d: %s", host, port, strerror(errno));
        close(fd);
        freeaddrinfo(res);
        return NGMT_ERR_IO;
    }
    freeaddrinfo(res);
    s->fd = fd;
    static const uint8_t intermediate[4] = { 0xee, 0xee, 0xee, 0xee };
    if (write_all(fd, intermediate, 4) != 0) { set_error(s, "send failed"); return NGMT_ERR_IO; }
    return NGMT_OK;
}

void ngmt_disconnect(ngmt_session *s) {
    if (s->fd >= 0) close(s->fd);
    s->fd = -1;
    s->http = 0;
    ngmt_buf_free(&s->http_pending);
    s->http_has_pending = 0;
}

int ngmt_connect_http(ngmt_session *s, const char *host, int port, int dc_id, int test,
                      const char *proxy_host, int proxy_port) {
    ngmt_disconnect(s);
    s->dc_id = dc_id;
    s->test = test;
    s->http = 1;
    snprintf(s->http_host, sizeof(s->http_host), "%s", host);
    s->http_port = port;
    snprintf(s->proxy_host, sizeof(s->proxy_host), "%s", proxy_host ? proxy_host : "");
    s->proxy_port = proxy_port;
    return NGMT_OK;
}

static int open_tcp(ngmt_session *s, const char *host, int port) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[8];
    snprintf(portstr, sizeof(portstr), "%d", port);
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) { set_error(s, "cannot resolve %s", host); return -1; }
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    struct timeval tv = { 20, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    if (fd < 0 || connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
        set_error(s, "connect %s:%d: %s", host, port, strerror(errno));
        if (fd >= 0) close(fd);
        freeaddrinfo(res);
        return -1;
    }
    freeaddrinfo(res);
    return fd;
}

/* One POST per packet; the response body is the next packet to read. */
static int http_exchange(ngmt_session *s, const uint8_t *p, size_t n) {
    int direct = s->proxy_host[0] == 0;
    int fd = direct ? open_tcp(s, s->http_host, s->http_port) : open_tcp(s, s->proxy_host, s->proxy_port);
    if (fd < 0) return NGMT_ERR_IO;
    char head[256];
    int hl = direct
        ? snprintf(head, sizeof(head), "POST /api HTTP/1.1\r\nHost: %s:%d\r\nContent-Length: %u\r\nConnection: close\r\n\r\n", s->http_host, s->http_port, (unsigned)n)
        : snprintf(head, sizeof(head), "POST http://%s:%d/api HTTP/1.1\r\nHost: %s:%d\r\nContent-Length: %u\r\nConnection: close\r\n\r\n", s->http_host, s->http_port, s->http_host, s->http_port, (unsigned)n);
    if (write_all(fd, (const uint8_t *)head, (size_t)hl) || write_all(fd, p, n)) { close(fd); set_error(s, "http send failed"); return NGMT_ERR_IO; }
    ngmt_buf raw = {0};
    uint8_t chunk[8192];
    for (;;) {
        ssize_t r = recv(fd, chunk, sizeof(chunk), 0);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        ngmt_put_bytes_raw(&raw, chunk, (size_t)r);
    }
    close(fd);
    size_t hdr_end = 0;
    for (size_t i = 0; i + 3 < raw.len; i++) {
        if (raw.data[i] == '\r' && raw.data[i + 1] == '\n' && raw.data[i + 2] == '\r' && raw.data[i + 3] == '\n') { hdr_end = i + 4; break; }
    }
    if (!hdr_end || raw.len < 12 || memcmp(raw.data + 9, "200", 3)) {
        set_error(s, "http error %.*s", raw.len > 12 ? 3 : 0, raw.len > 12 ? (const char *)raw.data + 9 : "");
        ngmt_buf_free(&raw);
        return NGMT_ERR_IO;
    }
    ngmt_buf_free(&s->http_pending);
    ngmt_put_bytes_raw(&s->http_pending, raw.data + hdr_end, raw.len - hdr_end);
    s->http_has_pending = 1;
    ngmt_buf_free(&raw);
    return NGMT_OK;
}

static int send_packet(ngmt_session *s, const uint8_t *p, size_t n) {
    if (s->http) return http_exchange(s, p, n);
    uint8_t len[4] = { (uint8_t)n, (uint8_t)(n >> 8), (uint8_t)(n >> 16), (uint8_t)(n >> 24) };
    if (write_all(s->fd, len, 4) || write_all(s->fd, p, n)) { set_error(s, "send failed"); return NGMT_ERR_IO; }
    return NGMT_OK;
}

static int recv_packet(ngmt_session *s, ngmt_buf *out) {
    if (s->http) {
        if (!s->http_has_pending) {
            /* nothing queued: poll with an empty container-less http_wait */
            ngmt_buf w = {0};
            ngmt_put_int(&w, 0x9299359f);   /* http_wait max_delay:int wait_after:int max_wait:int */
            ngmt_put_int(&w, 0); ngmt_put_int(&w, 0); ngmt_put_int(&w, 15000);
            extern int ngmt__send_service(ngmt_session *, const uint8_t *, size_t);
            int rc = ngmt__send_service(s, w.data, w.len);
            ngmt_buf_free(&w);
            if (rc) return rc;
        }
        s->http_has_pending = 0;
        out->len = 0;
        ngmt_put_bytes_raw(out, s->http_pending.data, s->http_pending.len);
        if (out->len == 0) { set_error(s, "empty http response"); return NGMT_ERR_IO; }
        return NGMT_OK;
    }
    uint8_t len[4];
    if (read_all(s->fd, len, 4)) { set_error(s, "receive failed"); return NGMT_ERR_IO; }
    uint32_t n = (uint32_t)len[0] | ((uint32_t)len[1] << 8) | ((uint32_t)len[2] << 16) | ((uint32_t)len[3] << 24);
    if (n > 16 * 1024 * 1024) { set_error(s, "packet too large"); return NGMT_ERR_PROTO; }
    out->len = 0;
    uint8_t *tmp = (uint8_t *)malloc(n ? n : 1);
    if (read_all(s->fd, tmp, n)) { free(tmp); set_error(s, "receive failed"); return NGMT_ERR_IO; }
    ngmt_put_bytes_raw(out, tmp, n);
    free(tmp);
    if (n == 4) {
        int32_t code = (int32_t)((uint32_t)out->data[0] | ((uint32_t)out->data[1] << 8) | ((uint32_t)out->data[2] << 16) | ((uint32_t)out->data[3] << 24));
        set_error(s, "transport error %d", code);
        return NGMT_ERR_PROTO;
    }
    return NGMT_OK;
}

/* ---- unencrypted messages (key exchange) ---- */

static int send_plain(ngmt_session *s, const ngmt_buf *body) {
    ngmt_buf p = {0};
    ngmt_put_long(&p, 0);
    ngmt_put_long(&p, next_msg_id(s));
    ngmt_put_int(&p, (uint32_t)body->len);
    ngmt_put_bytes_raw(&p, body->data, body->len);
    int rc = send_packet(s, p.data, p.len);
    ngmt_buf_free(&p);
    return rc;
}

static int recv_plain(ngmt_session *s, ngmt_buf *body) {
    ngmt_buf p = {0};
    int rc = recv_packet(s, &p);
    if (rc) { ngmt_buf_free(&p); return rc; }
    ngmt_reader r = { p.data, p.len, 0, 0 };
    uint64_t key_id = ngmt_get_long(&r);
    ngmt_get_long(&r);
    uint32_t len = ngmt_get_int(&r);
    if (r.error || key_id != 0 || r.pos + len > p.len) { ngmt_buf_free(&p); set_error(s, "bad plain message"); return NGMT_ERR_PROTO; }
    body->len = 0;
    ngmt_put_bytes_raw(body, p.data + r.pos, len);
    ngmt_buf_free(&p);
    return NGMT_OK;
}

/* ---- server RSA keys (MtProtoKit's MTDatacenterAuthMessageService) ---- */

typedef struct {
    const char *pem_base64;   /* PKCS#1 RSAPublicKey, base64 of the PEM body */
    int test;
} ngmt_rsa_key;

/* Copied verbatim from MtProtoKit's MTDatacenterAuthMessageService.m:
   the first is its testing key, the second its production key. */
static const ngmt_rsa_key ngmt_keys[] = {
    { "MIIBCgKCAQEAyMEdY1aR+sCR3ZSJrtztKTKqigvO/vBfqACJLZtS7QMgCGXJ6XIRyy7mx66W0/sOFa7/1mAZtEoIokDP3ShoqF4fVNb6XeqgQfaUHd8wJpDWHcR2OFwvplUUI1PLTktZ9uW2WE23b+ixNwJjJGwBDJPQEQFBE+vfmH0JP503wr5INS1poWg/j25sIWeYPHYeOrFp/eXaqhISP6G+q2IeTaWTXpwZj4LzXq5YOpk4bYEQ6mvRq7D1aHWfYmlEGepfaYR8Q0YqvvhYtMte3ITnuSJs171+GDqpdKcSwHnd6FudwGO4pcCOj4WcDuXc2CTHgH8gFTNhp/Y8/SpDOhvn9QIDAQAB", 1 },
    { "MIIBCgKCAQEA6LszBcC1LGzyr992NzE0ieY+BSaOW622Aa9Bd4ZHLl+TuFQ4lo4g5nKaMBwK/BIb9xUfg0Q29/2mgIR6Zr9krM7HjuIcCzFvDtr+L0GQjae9H0pRB2OO62cECs5HKhT5DZ98K33vmWiLowc621dQuwKWSQKjWf50XYFw42h21P2KXUGyp2y/+aEyZ+uVgLLQbRA1dEjSDZ2iGRy12Mk5gpYc397aYp438fsJoHIgJ2lgMv5h7WY9t6N/byY9Nw9p21Og3AoXSL2q/2IJ1WRUhebgAdGVMlV1fkuOQoEzR7EdpqtQD9Cs5+bfo3Nhmcyvk5ftB0WkJ9z6bNZ7yxrP8wIDAQAB", 0 },
};

static int b64val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static size_t base64_decode(const char *in, uint8_t *out, size_t cap) {
    size_t n = 0;
    uint32_t acc = 0;
    int bits = 0;
    for (const char *c = in; *c; c++) {
        int v = b64val(*c);
        if (v < 0) continue;
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n < cap) out[n++] = (uint8_t)(acc >> bits);
        }
    }
    return n;
}

static size_t der_length(const uint8_t *p, size_t *pos) {
    size_t len = p[(*pos)++];
    if (len & 0x80) {
        int count = (int)(len & 0x7f);
        len = 0;
        while (count--) len = (len << 8) | p[(*pos)++];
    }
    return len;
}

/* RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER } */
static int parse_rsa_key(const char *pem_base64, uint8_t n[256], size_t *nlen, uint32_t *e) {
    uint8_t der[512];
    size_t len = base64_decode(pem_base64, der, sizeof(der)), pos = 0;
    if (len < 16 || der[pos++] != 0x30) return -1;
    der_length(der, &pos);
    if (der[pos++] != 0x02) return -1;
    size_t ml = der_length(der, &pos);
    while (ml > 0 && der[pos] == 0) { pos++; ml--; }
    if (ml > 256) return -1;
    memcpy(n, der + pos, ml);
    *nlen = ml;
    pos += ml;
    if (der[pos++] != 0x02) return -1;
    size_t el = der_length(der, &pos);
    *e = 0;
    while (el--) *e = (*e << 8) | der[pos++];
    return 0;
}

static uint64_t key_fingerprint(const uint8_t *n, size_t nlen, uint32_t e) {
    ngmt_buf b = {0};
    ngmt_put_string(&b, n, nlen);
    uint8_t ebytes[3] = { (uint8_t)(e >> 16), (uint8_t)(e >> 8), (uint8_t)e };
    ngmt_put_string(&b, ebytes, 3);
    uint8_t h[20];
    ngmt_sha1(b.data, b.len, h);
    ngmt_buf_free(&b);
    uint64_t fp = 0;
    for (int i = 0; i < 8; i++) fp |= (uint64_t)h[12 + i] << (8 * i);
    return fp;
}

/* RSA_PAD (core.telegram.org/mtproto/auth_key, step 4) */
static int rsa_pad_encrypt(const uint8_t *data, size_t len, const uint8_t *n, size_t nlen, uint32_t e, uint8_t out[256]) {
    if (len > 144) return -1;
    uint8_t padded[192];
    memcpy(padded, data, len);
    ngmt_random(padded + len, 192 - len);
    bn mod;
    bn_from_bytes(&mod, n, nlen);
    for (int attempt = 0; attempt < 32; attempt++) {
        uint8_t temp_key[32];
        ngmt_random(temp_key, 32);
        uint8_t data_with_hash[224];
        for (int i = 0; i < 192; i++) data_with_hash[i] = padded[191 - i];
        uint8_t hbuf[32 + 192];
        memcpy(hbuf, temp_key, 32);
        memcpy(hbuf + 32, padded, 192);
        ngmt_sha256(hbuf, sizeof(hbuf), data_with_hash + 192);
        uint8_t aes_encrypted[224];
        uint8_t zero_iv[32] = {0};
        ngmt_aes_ige(data_with_hash, aes_encrypted, 224, temp_key, zero_iv, 1);
        uint8_t h[32];
        ngmt_sha256(aes_encrypted, 224, h);
        uint8_t key_aes_encrypted[256];
        for (int i = 0; i < 32; i++) key_aes_encrypted[i] = temp_key[i] ^ h[i];
        memcpy(key_aes_encrypted + 32, aes_encrypted, 224);
        bn m;
        bn_from_bytes(&m, key_aes_encrypted, 256);
        if (bn_cmp(&m, &mod) >= 0) continue;
        bn ebn, r;
        uint8_t ebytes[4] = { (uint8_t)(e >> 24), (uint8_t)(e >> 16), (uint8_t)(e >> 8), (uint8_t)e };
        bn_from_bytes(&ebn, ebytes, 4);
        bn_modexp(&r, &m, &ebn, &mod);
        bn_to_bytes(&r, out, 256);
        return 0;
    }
    return -1;
}

static void tmp_aes_params(const uint8_t new_nonce[32], const uint8_t server_nonce[16], uint8_t key[32], uint8_t iv[32]) {
    uint8_t buf[64], h1[20], h2[20], h3[20];
    memcpy(buf, new_nonce, 32); memcpy(buf + 32, server_nonce, 16);
    ngmt_sha1(buf, 48, h1);
    memcpy(buf, server_nonce, 16); memcpy(buf + 16, new_nonce, 32);
    ngmt_sha1(buf, 48, h2);
    memcpy(buf, new_nonce, 32); memcpy(buf + 32, new_nonce, 32);
    ngmt_sha1(buf, 64, h3);
    memcpy(key, h1, 20); memcpy(key + 20, h2, 12);
    memcpy(iv, h2 + 12, 8); memcpy(iv + 8, h3, 20); memcpy(iv + 28, new_nonce, 4);
}

int ngmt_create_auth_key(ngmt_session *s) {
    int rc;
    ngmt_buf body = {0}, resp = {0};
    uint8_t nonce[16], server_nonce[16], new_nonce[32];
    ngmt_random(nonce, 16);

    /* req_pq_multi */
    ngmt_put_int(&body, 0xbe7e8ef1);
    ngmt_put_bytes_raw(&body, nonce, 16);
    if ((rc = send_plain(s, &body)) || (rc = recv_plain(s, &resp))) goto done;
    {
        ngmt_reader r = { resp.data, resp.len, 0, 0 };
        if (ngmt_get_int(&r) != 0x05162463) { set_error(s, "expected resPQ"); rc = NGMT_ERR_PROTO; goto done; }
        uint8_t got_nonce[16];
        ngmt_get_raw(&r, got_nonce, 16);
        ngmt_get_raw(&r, server_nonce, 16);
        if (memcmp(got_nonce, nonce, 16)) { set_error(s, "nonce mismatch"); rc = NGMT_ERR_PROTO; goto done; }
        size_t pqlen;
        const uint8_t *pqb = ngmt_get_string(&r, &pqlen);
        uint64_t pq = 0;
        for (size_t i = 0; i < pqlen; i++) pq = (pq << 8) | pqb[i];
        ngmt_get_int(&r);   /* vector */
        uint32_t count = ngmt_get_int(&r);
        int found = 0;
        uint8_t nbytes[256];
        size_t nlen = 0;
        uint32_t exponent = 0;
        uint64_t fingerprint = 0;
        for (uint32_t i = 0; i < count && !found; i++) {
            uint64_t fp = ngmt_get_long(&r);
            for (size_t k = 0; k < sizeof(ngmt_keys) / sizeof(ngmt_keys[0]); k++) {
                size_t l;
                uint32_t e;
                if (parse_rsa_key(ngmt_keys[k].pem_base64, nbytes, &l, &e)) continue;
                if (key_fingerprint(nbytes, l, e) == fp) { found = 1; nlen = l; exponent = e; fingerprint = fp; break; }
            }
        }
        if (r.error || !found) { set_error(s, "no known server key"); rc = NGMT_ERR_PROTO; goto done; }

        uint64_t p = factorize(pq), q = p ? pq / p : 0;
        if (p > q) { uint64_t t = p; p = q; q = t; }
        uint8_t pb[4] = { (uint8_t)(p >> 24), (uint8_t)(p >> 16), (uint8_t)(p >> 8), (uint8_t)p };
        uint8_t qb[4] = { (uint8_t)(q >> 24), (uint8_t)(q >> 16), (uint8_t)(q >> 8), (uint8_t)q };

        ngmt_random(new_nonce, 32);
        ngmt_buf inner = {0};
        ngmt_put_int(&inner, 0xa9f55f95);   /* p_q_inner_data_dc */
        ngmt_put_string(&inner, pqb, pqlen);
        ngmt_put_string(&inner, pb, 4);
        ngmt_put_string(&inner, qb, 4);
        ngmt_put_bytes_raw(&inner, nonce, 16);
        ngmt_put_bytes_raw(&inner, server_nonce, 16);
        ngmt_put_bytes_raw(&inner, new_nonce, 32);
        ngmt_put_int(&inner, (uint32_t)(s->test ? 10000 + s->dc_id : s->dc_id));
        uint8_t encrypted[256];
        int bad = rsa_pad_encrypt(inner.data, inner.len, nbytes, nlen, exponent, encrypted);
        ngmt_buf_free(&inner);
        if (bad) { set_error(s, "RSA_PAD failed"); rc = NGMT_ERR_PROTO; goto done; }

        body.len = 0;
        ngmt_put_int(&body, 0xd712e4be);   /* req_DH_params */
        ngmt_put_bytes_raw(&body, nonce, 16);
        ngmt_put_bytes_raw(&body, server_nonce, 16);
        ngmt_put_string(&body, pb, 4);
        ngmt_put_string(&body, qb, 4);
        ngmt_put_long(&body, fingerprint);
        ngmt_put_string(&body, encrypted, 256);
    }
    if ((rc = send_plain(s, &body)) || (rc = recv_plain(s, &resp))) goto done;
    {
        ngmt_reader r = { resp.data, resp.len, 0, 0 };
        uint32_t ctor = ngmt_get_int(&r);
        if (ctor != 0xd0e8075c) { set_error(s, "server_DH_params_fail (%08x)", ctor); rc = NGMT_ERR_PROTO; goto done; }
        uint8_t skip[32];
        ngmt_get_raw(&r, skip, 32);
        size_t elen;
        const uint8_t *enc = ngmt_get_string(&r, &elen);
        if (r.error || elen % 16) { set_error(s, "bad encrypted_answer"); rc = NGMT_ERR_PROTO; goto done; }
        uint8_t tkey[32], tiv[32];
        tmp_aes_params(new_nonce, server_nonce, tkey, tiv);
        uint8_t *answer = (uint8_t *)malloc(elen);
        ngmt_aes_ige(enc, answer, elen, tkey, tiv, 0);

        ngmt_reader a = { answer + 20, elen - 20, 0, 0 };
        if (ngmt_get_int(&a) != 0xb5890dba) { free(answer); set_error(s, "expected server_DH_inner_data"); rc = NGMT_ERR_PROTO; goto done; }
        ngmt_get_raw(&a, skip, 32);
        uint32_t g = ngmt_get_int(&a);
        size_t plen, galen;
        const uint8_t *dh_prime = ngmt_get_string(&a, &plen);
        const uint8_t *g_a = ngmt_get_string(&a, &galen);
        int32_t server_time = (int32_t)ngmt_get_int(&a);
        uint8_t check[20];
        ngmt_sha1(answer + 20, a.pos, check);
        if (a.error || memcmp(check, answer, 20)) { free(answer); set_error(s, "server_DH_inner_data hash mismatch"); rc = NGMT_ERR_PROTO; goto done; }
        s->time_offset = (int64_t)server_time - (int64_t)time(NULL);

        bn p, ga, gbn, b, gb, key;
        bn_from_bytes(&p, dh_prime, plen);
        bn_from_bytes(&ga, g_a, galen);
        uint8_t gbytes[4] = { (uint8_t)(g >> 24), (uint8_t)(g >> 16), (uint8_t)(g >> 8), (uint8_t)g };
        bn_from_bytes(&gbn, gbytes, 4);
        uint8_t bbytes[256];
        ngmt_random(bbytes, 256);
        bn_from_bytes(&b, bbytes, 256);
        bn_modexp(&gb, &gbn, &b, &p);
        bn_modexp(&key, &ga, &b, &p);
        free(answer);

        uint8_t gb_bytes[256];
        bn_to_bytes(&gb, gb_bytes, 256);
        bn_to_bytes(&key, s->auth_key, 256);

        ngmt_buf inner = {0};
        ngmt_put_int(&inner, 0x6643b654);   /* client_DH_inner_data */
        ngmt_put_bytes_raw(&inner, nonce, 16);
        ngmt_put_bytes_raw(&inner, server_nonce, 16);
        ngmt_put_long(&inner, 0);
        ngmt_put_string(&inner, gb_bytes, 256);
        ngmt_buf withhash = {0};
        uint8_t h[20];
        ngmt_sha1(inner.data, inner.len, h);
        ngmt_put_bytes_raw(&withhash, h, 20);
        ngmt_put_bytes_raw(&withhash, inner.data, inner.len);
        while (withhash.len % 16) { uint8_t z; ngmt_random(&z, 1); ngmt_put_bytes_raw(&withhash, &z, 1); }
        uint8_t *encd = (uint8_t *)malloc(withhash.len);
        ngmt_aes_ige(withhash.data, encd, withhash.len, tkey, tiv, 1);

        body.len = 0;
        ngmt_put_int(&body, 0xf5045f1f);   /* set_client_DH_params */
        ngmt_put_bytes_raw(&body, nonce, 16);
        ngmt_put_bytes_raw(&body, server_nonce, 16);
        ngmt_put_string(&body, encd, withhash.len);
        free(encd);
        ngmt_buf_free(&inner);
        ngmt_buf_free(&withhash);
    }
    if ((rc = send_plain(s, &body)) || (rc = recv_plain(s, &resp))) goto done;
    {
        ngmt_reader r = { resp.data, resp.len, 0, 0 };
        uint32_t ctor = ngmt_get_int(&r);
        if (ctor != 0x3bcbf734) { set_error(s, "dh_gen not ok (%08x)", ctor); rc = NGMT_ERR_PROTO; goto done; }
        uint8_t skip[32], hash1[16];
        ngmt_get_raw(&r, skip, 32);
        ngmt_get_raw(&r, hash1, 16);
        uint8_t kh[20];
        ngmt_sha1(s->auth_key, 256, kh);
        uint8_t buf[41];
        memcpy(buf, new_nonce, 32);
        buf[32] = 1;
        memcpy(buf + 33, kh, 8);
        uint8_t nh[20];
        ngmt_sha1(buf, 41, nh);
        if (memcmp(nh + 4, hash1, 16)) { set_error(s, "new_nonce_hash1 mismatch"); rc = NGMT_ERR_PROTO; goto done; }
        s->auth_key_id = 0;
        for (int i = 0; i < 8; i++) s->auth_key_id |= (uint64_t)kh[12 + i] << (8 * i);
        s->salt = 0;
        for (int i = 0; i < 8; i++) s->salt |= (uint64_t)(new_nonce[i] ^ server_nonce[i]) << (8 * i);
        s->has_key = 1;
        rc = NGMT_OK;
    }
done:
    ngmt_buf_free(&body);
    ngmt_buf_free(&resp);
    return rc;
}

void ngmt_set_auth_key(ngmt_session *s, const uint8_t key[256], uint64_t salt) {
    memcpy(s->auth_key, key, 256);
    uint8_t kh[20];
    ngmt_sha1(key, 256, kh);
    s->auth_key_id = 0;
    for (int i = 0; i < 8; i++) s->auth_key_id |= (uint64_t)kh[12 + i] << (8 * i);
    s->salt = salt;
    s->has_key = 1;
}

int ngmt_has_auth_key(const ngmt_session *s) { return s->has_key; }
const uint8_t *ngmt_auth_key(const ngmt_session *s) { return s->auth_key; }
uint64_t ngmt_server_salt(const ngmt_session *s) { return s->salt; }

/* ---- encrypted messages (MTProto 2.0) ---- */

static void msg_key_params(const uint8_t *auth_key, const uint8_t msg_key[16], int x, uint8_t key[32], uint8_t iv[32]) {
    uint8_t buf[52], a[32], b[32];
    memcpy(buf, msg_key, 16); memcpy(buf + 16, auth_key + x, 36);
    ngmt_sha256(buf, 52, a);
    memcpy(buf, auth_key + 40 + x, 36); memcpy(buf + 36, msg_key, 16);
    ngmt_sha256(buf, 52, b);
    memcpy(key, a, 8); memcpy(key + 8, b + 8, 16); memcpy(key + 24, a + 24, 8);
    memcpy(iv, b, 8); memcpy(iv + 8, a + 8, 16); memcpy(iv + 24, b + 24, 8);
}

static int send_encrypted(ngmt_session *s, const uint8_t *body, size_t len, uint64_t msg_id, int content_related) {
    ngmt_buf plain = {0};
    ngmt_put_long(&plain, s->salt);
    ngmt_put_long(&plain, s->session_id);
    ngmt_put_long(&plain, msg_id);
    uint32_t seq = content_related ? s->seq * 2 + 1 : s->seq * 2;
    if (content_related) s->seq++;
    ngmt_put_int(&plain, seq);
    ngmt_put_int(&plain, (uint32_t)len);
    ngmt_put_bytes_raw(&plain, body, len);
    uint8_t pad[1024];
    size_t padlen = 12 + (16 - (plain.len + 12) % 16) % 16;
    ngmt_random(pad, padlen);
    ngmt_put_bytes_raw(&plain, pad, padlen);

    uint8_t *hbuf = (uint8_t *)malloc(32 + plain.len);
    memcpy(hbuf, s->auth_key + 88, 32);
    memcpy(hbuf + 32, plain.data, plain.len);
    uint8_t large[32];
    ngmt_sha256(hbuf, 32 + plain.len, large);
    free(hbuf);
    uint8_t msg_key[16];
    memcpy(msg_key, large + 8, 16);
    uint8_t key[32], iv[32];
    msg_key_params(s->auth_key, msg_key, 0, key, iv);

    ngmt_buf packet = {0};
    ngmt_put_long(&packet, s->auth_key_id);
    ngmt_put_bytes_raw(&packet, msg_key, 16);
    size_t off = packet.len;
    ngmt_put_bytes_raw(&packet, plain.data, plain.len);
    ngmt_aes_ige(plain.data, packet.data + off, plain.len, key, iv, 1);
    int rc = send_packet(s, packet.data, packet.len);
    ngmt_buf_free(&plain);
    ngmt_buf_free(&packet);
    return rc;
}

/* Receives one encrypted message; *body gets the message body. */
static int recv_encrypted(ngmt_session *s, ngmt_buf *body, uint64_t *msg_id_out, uint32_t *seq_out) {
    ngmt_buf p = {0};
    int rc = recv_packet(s, &p);
    if (rc) { ngmt_buf_free(&p); return rc; }
    if (p.len < 24 + 32 || (p.len - 24) % 16) { ngmt_buf_free(&p); set_error(s, "short encrypted packet"); return NGMT_ERR_PROTO; }
    uint8_t msg_key[16];
    memcpy(msg_key, p.data + 8, 16);
    uint8_t key[32], iv[32];
    msg_key_params(s->auth_key, msg_key, 8, key, iv);
    size_t elen = p.len - 24;
    uint8_t *plain = (uint8_t *)malloc(elen);
    ngmt_aes_ige(p.data + 24, plain, elen, key, iv, 0);
    ngmt_buf_free(&p);

    uint8_t *hbuf = (uint8_t *)malloc(32 + elen);
    memcpy(hbuf, s->auth_key + 88 + 8, 32);
    memcpy(hbuf + 32, plain, elen);
    uint8_t large[32];
    ngmt_sha256(hbuf, 32 + elen, large);
    free(hbuf);
    if (memcmp(large + 8, msg_key, 16)) { free(plain); set_error(s, "msg_key mismatch"); return NGMT_ERR_PROTO; }

    ngmt_reader r = { plain, elen, 0, 0 };
    ngmt_get_long(&r);   /* salt */
    ngmt_get_long(&r);   /* session */
    uint64_t msg_id = ngmt_get_long(&r);
    uint32_t seq = ngmt_get_int(&r);
    if (seq_out) *seq_out = seq;
    uint32_t len = ngmt_get_int(&r);
    if (r.error || len > elen - 32) { free(plain); set_error(s, "bad message length"); return NGMT_ERR_PROTO; }
    body->len = 0;
    ngmt_put_bytes_raw(body, plain + 32, len);
    free(plain);
    if (msg_id_out) *msg_id_out = msg_id;
    return NGMT_OK;
}

int ngmt__send_service(ngmt_session *s, const uint8_t *body, size_t len) {
    return send_encrypted(s, body, len, next_msg_id(s), 0);
}

static void queue_ack(ngmt_session *s, uint64_t msg_id) {
    for (int i = 0; i < s->pending_ack_count; i++) if (s->pending_acks[i] == msg_id) return;
    if (s->pending_ack_count == (int)(sizeof(s->pending_acks) / sizeof(s->pending_acks[0]))) {
        memmove(s->pending_acks, s->pending_acks + 1, sizeof(uint64_t) * (size_t)(s->pending_ack_count - 1));
        s->pending_ack_count--;
    }
    s->pending_acks[s->pending_ack_count++] = msg_id;
}

/* Sends a content-related request, together with the pending acks in one
   msg_container when there are any (as the official clients do). */
static int send_request(ngmt_session *s, const uint8_t *body, size_t len, uint64_t *msg_id_out) {
    if (s->pending_ack_count == 0) {
        uint64_t id = next_msg_id(s);
        *msg_id_out = id;
        return send_encrypted(s, body, len, id, 1);
    }
    ngmt_buf ack = {0};
    ngmt_put_int(&ack, 0x62d6b459);   /* msgs_ack */
    ngmt_put_int(&ack, 0x1cb5c415);
    ngmt_put_int(&ack, (uint32_t)s->pending_ack_count);
    for (int i = 0; i < s->pending_ack_count; i++) ngmt_put_long(&ack, s->pending_acks[i]);
    uint64_t ack_id = next_msg_id(s), req_id = next_msg_id(s);
    ngmt_buf c = {0};
    ngmt_put_int(&c, 0x73f1f8dc);     /* msg_container */
    ngmt_put_int(&c, 2);
    ngmt_put_long(&c, ack_id);
    ngmt_put_int(&c, s->seq * 2);     /* not content-related */
    ngmt_put_int(&c, (uint32_t)ack.len);
    ngmt_put_bytes_raw(&c, ack.data, ack.len);
    ngmt_put_long(&c, req_id);
    ngmt_put_int(&c, s->seq * 2 + 1); /* content-related */
    s->seq++;
    ngmt_put_int(&c, (uint32_t)len);
    ngmt_put_bytes_raw(&c, body, len);
    int rc = send_encrypted(s, c.data, c.len, next_msg_id(s), 0);
    ngmt_buf_free(&ack);
    ngmt_buf_free(&c);
    if (rc == NGMT_OK) s->pending_ack_count = 0;
    *msg_id_out = req_id;
    return rc;
}

static int gunzip(const uint8_t *in, size_t len, ngmt_buf *out) {
    z_stream z;
    memset(&z, 0, sizeof(z));
    if (inflateInit2(&z, 15 + 32) != Z_OK) return -1;
    z.next_in = (Bytef *)in;
    z.avail_in = (uInt)len;
    uint8_t chunk[16384];
    int ret;
    do {
        z.next_out = chunk;
        z.avail_out = sizeof(chunk);
        ret = inflate(&z, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END) { inflateEnd(&z); return -1; }
        ngmt_put_bytes_raw(out, chunk, sizeof(chunk) - z.avail_out);
    } while (ret != Z_STREAM_END);
    inflateEnd(&z);
    return 0;
}

/* Result of looking at one incoming object while waiting for req_msg_id. */
enum { WAIT_MORE = 0, WAIT_DONE = 1, WAIT_RESEND = 2 };

static int handle_object(ngmt_session *s, ngmt_reader *r, size_t end, uint64_t req_msg_id, uint64_t msg_id,
                         ngmt_buf *result, int *rc, int *error_code, char *error_message, size_t error_cap) {
    uint32_t ctor = ngmt_get_int(r);
    switch (ctor) {
        case 0x73f1f8dc: {   /* msg_container */
            uint32_t count = ngmt_get_int(r);
            int state = WAIT_MORE;
            for (uint32_t i = 0; i < count && !r->error; i++) {
                uint64_t inner_id = ngmt_get_long(r);
                uint32_t seq = ngmt_get_int(r);
                uint32_t len = ngmt_get_int(r);
                size_t inner_end = r->pos + len;
                if (seq & 1) queue_ack(s, inner_id);
                int st = handle_object(s, r, inner_end, req_msg_id, inner_id, result, rc, error_code, error_message, error_cap);
                r->pos = inner_end;
                if (st != WAIT_MORE) state = st;
            }
            return state;
        }
        case 0xf35c6d01: {   /* rpc_result */
            uint64_t req = ngmt_get_long(r);
            if (req != req_msg_id) { r->pos = end; return WAIT_MORE; }
            size_t start = r->pos;
            uint32_t inner = ngmt_get_int(r);
            if (inner == 0x2144ca19) {   /* rpc_error */
                *error_code = (int)ngmt_get_int(r);
                size_t n;
                const uint8_t *msg = ngmt_get_string(r, &n);
                if (error_message && error_cap) {
                    size_t c = n < error_cap - 1 ? n : error_cap - 1;
                    memcpy(error_message, msg, c);
                    error_message[c] = 0;
                }
                *rc = NGMT_RPC_ERROR;
            } else if (inner == 0x3072cfa1) {   /* gzip_packed */
                size_t n;
                const uint8_t *packed = ngmt_get_string(r, &n);
                result->len = 0;
                *rc = gunzip(packed, n, result) ? NGMT_ERR_PROTO : NGMT_OK;
            } else {
                result->len = 0;
                ngmt_put_bytes_raw(result, r->p + start, end - start);
                *rc = NGMT_OK;
            }
            r->pos = end;
            return WAIT_DONE;
        }
        case 0xedab447b: {   /* bad_server_salt */
            uint64_t bad_id = ngmt_get_long(r);
            ngmt_get_int(r);
            ngmt_get_int(r);
            s->salt = ngmt_get_long(r);
            r->pos = end;
            return bad_id == req_msg_id ? WAIT_RESEND : WAIT_MORE;
        }
        case 0xa7eff811: {   /* bad_msg_notification */
            uint64_t bad_id = ngmt_get_long(r);
            ngmt_get_int(r);
            uint32_t code = ngmt_get_int(r);
            if (code == 16 || code == 17) {
                s->time_offset = (int64_t)(msg_id >> 32) - (int64_t)time(NULL);
                s->last_msg_id = 0;
            }
            r->pos = end;
            if (bad_id != req_msg_id) return WAIT_MORE;
            if (code == 16 || code == 17) return WAIT_RESEND;
            set_error(s, "bad_msg_notification %u", code);
            *rc = NGMT_ERR_PROTO;
            return WAIT_DONE;
        }
        case 0x9ec20908:   /* new_session_created */
            ngmt_get_long(r);
            ngmt_get_long(r);
            s->salt = ngmt_get_long(r);
            r->pos = end;
            return WAIT_MORE;
        case 0x347773c5: {   /* pong */
            uint64_t req = ngmt_get_long(r);
            r->pos = end;
            if (req == req_msg_id) { *rc = NGMT_OK; result->len = 0; return WAIT_DONE; }
            return WAIT_MORE;
        }
        default:
            r->pos = end;   /* updates, acks, … are not needed for the calls made here */
            return WAIT_MORE;
    }
}

static int call_raw(ngmt_session *s, const uint8_t *body, size_t len, ngmt_buf *result,
                    int *error_code, char *error_message, size_t error_cap) {
    if (!s->has_key) { set_error(s, "no auth key"); return NGMT_ERR_PROTO; }
    for (int attempt = 0; attempt < 3; attempt++) {
        uint64_t msg_id = 0;
        int rc = send_request(s, body, len, &msg_id);
        if (rc) return rc;
        for (;;) {
            ngmt_buf in = {0};
            uint64_t in_id = 0;
            uint32_t in_seq = 0;
            rc = recv_encrypted(s, &in, &in_id, &in_seq);
            if (rc) { ngmt_buf_free(&in); return rc; }
            if (in_seq & 1) queue_ack(s, in_id);
            ngmt_reader r = { in.data, in.len, 0, 0 };
            int call_rc = NGMT_ERR_PROTO;
            int st = handle_object(s, &r, in.len, msg_id, in_id, result, &call_rc, error_code, error_message, error_cap);
            ngmt_buf_free(&in);
            if (st == WAIT_DONE) return call_rc;
            if (st == WAIT_RESEND) break;
        }
    }
    set_error(s, "too many resends");
    return NGMT_ERR_PROTO;
}

int ngmt_call(ngmt_session *s, const uint8_t *body, size_t len, ngmt_buf *result,
              int *error_code, char *error_message, size_t error_cap) {
    int code = 0;
    if (!error_code) error_code = &code;
    return call_raw(s, body, len, result, error_code, error_message, error_cap);
}

int ngmt_ping(ngmt_session *s) {
    ngmt_buf b = {0}, result = {0};
    uint64_t ping_id;
    ngmt_random(&ping_id, 8);
    ngmt_put_int(&b, 0x7abe77ec);
    ngmt_put_long(&b, ping_id);
    int code = 0;
    int rc = call_raw(s, b.data, b.len, &result, &code, NULL, 0);
    ngmt_buf_free(&b);
    ngmt_buf_free(&result);
    return rc;
}
