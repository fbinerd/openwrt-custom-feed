#ifndef MR80X_BASE64_H
#define MR80X_BASE64_H

#include <stddef.h>

/*
 * Decodes a NUL-terminated standard base64 string (RFC 4648, '+'/'/'
 * alphabet, '=' padding) into out (caller-allocated, at least
 * strlen(in) * 3 / 4 + 3 bytes). Returns the decoded length, or -1 on
 * any invalid character/padding.
 */
long base64_decode(const char *in, unsigned char *out, size_t out_cap);

#endif
