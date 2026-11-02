/*
 * ngmt — a small MTProto 2.0 client core in portable C.
 *
 * Transport: TCP, "intermediate" framing (0xeeeeeeee, then length-prefixed
 * packets). Auth key: the DH exchange of core.telegram.org/mtproto/auth_key
 * with RSA_PAD. Messages: MTProto 2.0 (SHA-256 msg_key, AES-256-IGE).
 * Calls are synchronous; run them off the main thread.
 *
 * Crypto comes from CommonCrypto/Security on Apple platforms and from
 * OpenSSL elsewhere (which is what the host tests link against).
 */
#ifndef NGMT_H
#define NGMT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- growable byte buffer + TL writer ---- */
typedef struct {
    uint8_t *data;
    size_t len, cap;
} ngmt_buf;

void ngmt_buf_free(ngmt_buf *b);
void ngmt_put_bytes_raw(ngmt_buf *b, const void *p, size_t n);
void ngmt_put_int(ngmt_buf *b, uint32_t v);
void ngmt_put_long(ngmt_buf *b, uint64_t v);
void ngmt_put_string(ngmt_buf *b, const void *p, size_t n);   /* TL bytes/string */
void ngmt_put_cstring(ngmt_buf *b, const char *s);

/* ---- TL reader ---- */
typedef struct {
    const uint8_t *p;
    size_t len, pos;
    int error;
} ngmt_reader;

uint32_t ngmt_get_int(ngmt_reader *r);
uint64_t ngmt_get_long(ngmt_reader *r);
void ngmt_get_raw(ngmt_reader *r, void *out, size_t n);
/* Returns a pointer into the reader's data; *n receives the length. */
const uint8_t *ngmt_get_string(ngmt_reader *r, size_t *n);

/* ---- session ---- */
typedef struct ngmt_session ngmt_session;

ngmt_session *ngmt_session_new(void);
void ngmt_session_free(ngmt_session *s);

/* dc_id is the logical DC (1..5); test selects the test servers. */
int ngmt_connect(ngmt_session *s, const char *host, int port, int dc_id, int test);
void ngmt_disconnect(ngmt_session *s);

/* MTProto's HTTP transport instead of TCP: each packet is a POST to
 * http://host:port/api, sent through an HTTP proxy when proxy_host is set.
 * Used where raw TCP to the DCs is not available. */
int ngmt_connect_http(ngmt_session *s, const char *host, int port, int dc_id, int test,
                      const char *proxy_host, int proxy_port);

/* Generates a permanent auth key on the connected DC. */
int ngmt_create_auth_key(ngmt_session *s);
/* Installs a key generated earlier (256 bytes) and its server salt. */
void ngmt_set_auth_key(ngmt_session *s, const uint8_t key[256], uint64_t salt);
int ngmt_has_auth_key(const ngmt_session *s);
const uint8_t *ngmt_auth_key(const ngmt_session *s);
uint64_t ngmt_server_salt(const ngmt_session *s);

/* Sends an RPC and waits for its rpc_result. On success returns 0 and the
 * result object (constructor first, gzip unpacked) in *result. On an
 * rpc_error returns NGMT_RPC_ERROR with code/message filled. */
#define NGMT_OK 0
#define NGMT_ERR_IO (-1)
#define NGMT_ERR_PROTO (-2)
#define NGMT_RPC_ERROR (-3)
int ngmt_call(ngmt_session *s, const uint8_t *body, size_t len, ngmt_buf *result,
              int *error_code, char *error_message, size_t error_cap);

/* ping/pong over the encrypted channel: checks the key and the crypto. */
int ngmt_ping(ngmt_session *s);

/* Diagnostics: the last failure, human-readable. */
const char *ngmt_last_error(const ngmt_session *s);

#ifdef __cplusplus
}
#endif

#endif
