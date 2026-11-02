#include "ngtl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const uint8_t *p;
    size_t len, pos;
    char *error;
    size_t error_cap;
    int failed;
} reader;

static void fail(reader *r, const char *fmt, const char *arg, uint32_t id) {
    if (r->failed) return;
    r->failed = 1;
    if (r->error && r->error_cap) snprintf(r->error, r->error_cap, fmt, arg ? arg : "", id);
}

static uint32_t rd_int(reader *r) {
    if (r->pos + 4 > r->len) { fail(r, "truncated%s %u", NULL, 0); return 0; }
    const uint8_t *p = r->p + r->pos;
    r->pos += 4;
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t rd_long(reader *r) {
    uint64_t lo = rd_int(r), hi = rd_int(r);
    return lo | (hi << 32);
}

static ngtl_node *node_new(ngtl_kind kind) {
    ngtl_node *n = (ngtl_node *)calloc(1, sizeof(ngtl_node));
    n->kind = kind;
    return n;
}

static void node_add(ngtl_node *parent, ngtl_node *child) {
    if (parent->count == parent->cap) {
        parent->cap = parent->cap ? parent->cap * 2 : 8;
        parent->items = (ngtl_node **)realloc(parent->items, sizeof(ngtl_node *) * (size_t)parent->cap);
    }
    parent->items[parent->count++] = child;
}

void ngtl_free(ngtl_node *n) {
    if (!n) return;
    for (int i = 0; i < n->count; i++) ngtl_free(n->items[i]);
    free(n->items);
    free(n->bytes);
    free(n->key);
    free(n);
}

const ngtl_node *ngtl_get(const ngtl_node *o, const char *key) {
    if (!o || o->kind != NGTL_OBJECT) return NULL;
    for (int i = 0; i < o->count; i++) {
        if (o->items[i]->key && strcmp(o->items[i]->key, key) == 0) return o->items[i];
    }
    return NULL;
}

const ngtl_constructor *ngtl_find(uint32_t id) {
    int lo = 0, hi = ngtl_constructor_count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        uint32_t v = ngtl_constructors[mid].id;
        if (v == id) return &ngtl_constructors[mid];
        if (v < id) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

static ngtl_node *decode_boxed(reader *r, int depth);

static ngtl_node *rd_bytes(reader *r) {
    if (r->pos + 1 > r->len) { fail(r, "truncated string%s %u", NULL, 0); return NULL; }
    size_t len, header;
    uint8_t first = r->p[r->pos];
    if (first < 254) {
        len = first;
        header = 1;
    } else {
        if (r->pos + 4 > r->len) { fail(r, "truncated string%s %u", NULL, 0); return NULL; }
        len = (size_t)r->p[r->pos + 1] | ((size_t)r->p[r->pos + 2] << 8) | ((size_t)r->p[r->pos + 3] << 16);
        header = 4;
    }
    size_t padded = (header + len + 3) & ~(size_t)3;
    if (r->pos + padded > r->len) { fail(r, "truncated string%s %u", NULL, 0); return NULL; }
    ngtl_node *n = node_new(NGTL_BYTES);
    n->bytes = (uint8_t *)malloc(len + 1);
    memcpy(n->bytes, r->p + r->pos + header, len);
    n->bytes[len] = 0;
    n->len = len;
    r->pos += padded;
    return n;
}

/* Reads one value of the given field type (no flags condition). */
static ngtl_node *decode_type(reader *r, const char *type, size_t tlen, int depth) {
    if (depth > 64) { fail(r, "too deep%s %u", NULL, 0); return NULL; }
#define IS(s) (tlen == sizeof(s) - 1 && memcmp(type, s, tlen) == 0)
    if (IS("int") || IS("#")) {
        ngtl_node *n = node_new(NGTL_INT);
        n->i = (int32_t)rd_int(r);
        return n;
    }
    if (IS("long")) {
        ngtl_node *n = node_new(NGTL_LONG);
        n->i = (int64_t)rd_long(r);
        return n;
    }
    if (IS("double")) {
        ngtl_node *n = node_new(NGTL_DOUBLE);
        uint64_t bits = rd_long(r);
        memcpy(&n->d, &bits, 8);
        return n;
    }
    if (IS("string") || IS("bytes")) return rd_bytes(r);
    if (IS("int128") || IS("int256")) {
        size_t n = IS("int128") ? 16 : 32;
        if (r->pos + n > r->len) { fail(r, "truncated%s %u", NULL, 0); return NULL; }
        ngtl_node *b = node_new(NGTL_BYTES);
        b->bytes = (uint8_t *)malloc(n + 1);
        memcpy(b->bytes, r->p + r->pos, n);
        b->len = n;
        r->pos += n;
        return b;
    }
    if (IS("Bool")) {
        uint32_t id = rd_int(r);
        ngtl_node *n = node_new(NGTL_BOOL);
        if (id == 0x997275b5u) n->i = 1;
        else if (id == 0xbc799737u) n->i = 0;
        else fail(r, "bad Bool%s %08x", NULL, id);
        return n;
    }
    if (tlen > 7 && (memcmp(type, "Vector<", 7) == 0 || memcmp(type, "vector<", 7) == 0)) {
        int boxed = type[0] == 'V';
        if (boxed) {
            uint32_t id = rd_int(r);
            if (id != 0x1cb5c415u) { fail(r, "expected vector%s %08x", NULL, id); return NULL; }
        }
        uint32_t count = rd_int(r);
        if (count > 1000000) { fail(r, "vector too long%s %u", NULL, count); return NULL; }
        ngtl_node *v = node_new(NGTL_VECTOR);
        const char *inner = type + 7;
        size_t ilen = tlen - 8;   /* strip "Vector<" and ">" */
        for (uint32_t i = 0; i < count && !r->failed; i++) {
            ngtl_node *e = decode_type(r, inner, ilen, depth + 1);
            if (!e) break;
            node_add(v, e);
        }
        return v;
    }
#undef IS
    /* Any other type is boxed: a constructor id, then its fields. */
    return decode_boxed(r, depth + 1);
}

static ngtl_node *decode_boxed(reader *r, int depth) {
    uint32_t id = rd_int(r);
    if (r->failed) return NULL;
    const ngtl_constructor *c = ngtl_find(id);
    if (!c) { fail(r, "unknown constructor%s %08x", NULL, id); return NULL; }
    ngtl_node *obj = node_new(NGTL_OBJECT);
    obj->ctor = c->name;
    const char *f = c->fields;
    while (*f && !r->failed) {
        while (*f == ' ') f++;
        if (!*f) break;
        const char *end = strchr(f, ' ');
        size_t flen = end ? (size_t)(end - f) : strlen(f);
        const char *colon = memchr(f, ':', flen);
        size_t nlen = (size_t)(colon - f);
        const char *type = colon + 1;
        size_t tlen = flen - nlen - 1;

        /* flags.N?Type / flags2.N?Type */
        const char *q = memchr(type, '?', tlen);
        int present = 1, is_true = 0;
        if (q) {
            const char *dot = memchr(type, '.', (size_t)(q - type));
            char flagname[16] = {0};
            size_t fnl = (size_t)(dot - type);
            if (fnl >= sizeof(flagname)) fnl = sizeof(flagname) - 1;
            memcpy(flagname, type, fnl);
            int bit = atoi(dot + 1);
            const ngtl_node *flags = ngtl_get(obj, flagname);
            present = flags && ((uint32_t)flags->i >> bit) & 1;
            tlen -= (size_t)(q + 1 - type);
            type = q + 1;
            is_true = tlen == 4 && memcmp(type, "true", 4) == 0;
        }
        ngtl_node *value = NULL;
        if (is_true) {
            value = node_new(NGTL_BOOL);
            value->i = present;
        } else if (present) {
            value = decode_type(r, type, tlen, depth);
        }
        if (value) {
            value->key = (char *)malloc(nlen + 1);
            memcpy(value->key, f, nlen);
            value->key[nlen] = 0;
            node_add(obj, value);
        }
        f += flen;
    }
    if (r->failed && !strstr(r->error ? r->error : "", " in ")) {
        size_t used = r->error ? strlen(r->error) : 0;
        if (r->error && used + 8 < r->error_cap) snprintf(r->error + used, r->error_cap - used, " in %s", c->name);
    }
    return obj;
}

ngtl_node *ngtl_decode(const uint8_t *data, size_t len, char *error, size_t error_cap) {
    reader r = { data, len, 0, error, error_cap, 0 };
    if (error && error_cap) error[0] = 0;
    ngtl_node *n = decode_boxed(&r, 0);
    if (r.failed) { ngtl_free(n); return NULL; }
    return n;
}
