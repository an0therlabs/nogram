/* ngtl — a schema-driven TL decoder: reads any boxed object of the API
 * schema (ngtl_schema.c, generated from swift_scheme.tl) into a tree. */
#ifndef NGTL_H
#define NGTL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t id;
    const char *name;
    const char *fields;   /* "name:type name:type …" */
} ngtl_constructor;

extern const ngtl_constructor ngtl_constructors[];
extern const int ngtl_constructor_count;

typedef enum {
    NGTL_INT, NGTL_LONG, NGTL_DOUBLE, NGTL_BYTES, NGTL_BOOL, NGTL_OBJECT, NGTL_VECTOR,
} ngtl_kind;

typedef struct ngtl_node {
    ngtl_kind kind;
    char *key;            /* field name inside an object */
    const char *ctor;     /* constructor name of an object */
    int64_t i;            /* int, long, bool */
    double d;
    uint8_t *bytes;       /* string / bytes, NUL-terminated copy */
    size_t len;
    struct ngtl_node **items;   /* object fields or vector elements */
    int count, cap;
} ngtl_node;

/* Decodes one boxed object; NULL (with *error set) on failure. */
ngtl_node *ngtl_decode(const uint8_t *data, size_t len, char *error, size_t error_cap);
void ngtl_free(ngtl_node *node);
const ngtl_node *ngtl_get(const ngtl_node *object, const char *key);
const ngtl_constructor *ngtl_find(uint32_t id);

#ifdef __cplusplus
}
#endif

#endif
