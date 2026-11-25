/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

/* elf/abi/sha256.h -- SHA-256 (FIPS 180-4), one-shot and streaming. */
#ifndef VANISH_SHA256_H
#define VANISH_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define SHA256_DIGEST_SIZE 32u

typedef struct {
  uint32_t state[8];
  uint64_t bitlen;
  uint8_t data[64];
  size_t datalen;
} sha256_ctx;

void sha256_init(sha256_ctx *ctx);
void sha256_update(sha256_ctx *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx *ctx, uint8_t out[SHA256_DIGEST_SIZE]);

/* One-shot digest. */
void sha256(const uint8_t *data, size_t len, uint8_t out[SHA256_DIGEST_SIZE]);

/* Hex-encode a digest (64 chars plus NUL). `hex` needs 65 bytes. */
void sha256_hex(const uint8_t digest[SHA256_DIGEST_SIZE], char hex[65]);

#endif /* VANISH_SHA256_H */
