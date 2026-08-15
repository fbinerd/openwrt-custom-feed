/*
 * sha256.h
 * Public domain implementation, based on Brad Conte's crypto-algorithms
 * (https://github.com/B-Con/crypto-algorithms, public domain). Vendored
 * because this tool runs on-router and has no other reason to depend on
 * a full crypto library for one hash function - same rationale as
 * appsbl's own scripts/tplink-cloud-sign-crosscheck/md5_min.h.
 */

#ifndef MR80X_SHA256_H
#define MR80X_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define SHA256_BLOCK_SIZE 32

typedef struct {
	uint8_t data[64];
	uint32_t datalen;
	unsigned long long bitlen;
	uint32_t state[8];
} SHA256_CTX;

void sha256_init(SHA256_CTX *ctx);
void sha256_update(SHA256_CTX *ctx, const uint8_t data[], size_t len);
void sha256_final(SHA256_CTX *ctx, uint8_t hash[]);

#endif
