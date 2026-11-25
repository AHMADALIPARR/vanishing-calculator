/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

/* elf/abi/verify.c -- Shared ELF image loading and verification. */
#include "verify.h"

#include "sha256.h"

#include <stdlib.h>
#include <string.h>

static int64_t rd64le(const uint8_t *p) {
  uint64_t v = (uint64_t)p[0] | ((uint64_t)p[1] << 8) |
               ((uint64_t)p[2] << 16) | ((uint64_t)p[3] << 24) |
               ((uint64_t)p[4] << 32) | ((uint64_t)p[5] << 40) |
               ((uint64_t)p[6] << 48) | ((uint64_t)p[7] << 56);
  return (int64_t)v;
}

static int check_note(const elf_file_t *f, char *err, size_t errsz) {
  const elf_section_t *note = elf_find(f, SEC_NOTE);
  const uint8_t *d;
  uint32_t namesz, descsz, type, version;
  if (!note) {
    snprintf(err, errsz, "missing %s section", SEC_NOTE);
    return -1;
  }
  if (note->type != 7 /* SHT_NOTE */ || note->size < 12 + NOTE_DESC_SIZE) {
    snprintf(err, errsz, "%s is malformed", SEC_NOTE);
    return -1;
  }
  d = note->data;
  namesz = (uint32_t)d[0] | ((uint32_t)d[1] << 8) | ((uint32_t)d[2] << 16) |
           ((uint32_t)d[3] << 24);
  descsz = (uint32_t)d[4] | ((uint32_t)d[5] << 8) | ((uint32_t)d[6] << 16) |
           ((uint32_t)d[7] << 24);
  type = (uint32_t)d[8] | ((uint32_t)d[9] << 8) | ((uint32_t)d[10] << 16) |
         ((uint32_t)d[11] << 24);
  if (namesz < 7 || descsz != NOTE_DESC_SIZE || type != NT_VANISH_ABI ||
      memcmp(d + 12, NOTE_NAME, 6) != 0) {
    snprintf(err, errsz, "%s has the wrong name or type", SEC_NOTE);
    return -1;
  }
  version = (uint32_t)d[20] | ((uint32_t)d[21] << 8) |
            ((uint32_t)d[22] << 16) | ((uint32_t)d[23] << 24);
  if (version != VANISH_ABI_VERSION) {
    snprintf(err, errsz, "unsupported vanish ABI version %u", version);
    return -1;
  }
  return 0;
}

int vanish_verify_hashes(const elf_file_t *f, char *err, size_t errsz) {
  static const char *names[] = { SEC_TEXT, SEC_AST, SEC_PROOF, SEC_SYM };
  const elf_section_t *hashsec = elf_find(f, SEC_HASH);
  size_t i;
  if (!hashsec) {
    snprintf(err, errsz, "missing %s section", SEC_HASH);
    return -1;
  }
  for (i = 0; i < 4; i++) {
    const elf_section_t *sec = elf_find(f, names[i]);
    uint8_t digest[SHA256_DIGEST_SIZE];
    char hex[65];
    char *line, *save = NULL;
    int found = 0;
    if (!sec) {
      snprintf(err, errsz, "missing %s section", names[i]);
      return -1;
    }
    sha256(sec->data, sec->size, digest);
    sha256_hex(digest, hex);
    /* Find the line "<hex>  <name>" in .vanish.hash. */
    {
      char *copy = (char *)malloc(hashsec->size + 1);
      if (!copy) {
        snprintf(err, errsz, "out of memory");
        return -1;
      }
      memcpy(copy, hashsec->data, hashsec->size);
      copy[hashsec->size] = '\0';
      for (line = strtok_r(copy, "\n", &save); line;
           line = strtok_r(NULL, "\n", &save)) {
        char h[65], n[128];
        if (sscanf(line, "%64s %127s", h, n) == 2 && strcmp(n, names[i]) == 0) {
          if (strcmp(h, hex) != 0) {
            snprintf(err, errsz, "hash mismatch for %s", names[i]);
            free(copy);
            return -1;
          }
          found = 1;
          break;
        }
      }
      free(copy);
    }
    if (!found) {
      snprintf(err, errsz, "no digest for %s in %s", names[i], SEC_HASH);
      return -1;
    }
  }
  return 0;
}

int vanish_image_load(const char *path, vanish_image_t *img,
                      char *err, size_t errsz) {
  const elf_section_t *text, *symsec;
  size_t i, nsyms = 0;
  memset(img, 0, sizeof(*img));
  if (elf_read_file(path, &img->elf, err, errsz) != 0) return -1;
  if (check_note(&img->elf, err, errsz) != 0) goto fail;
  if (vanish_verify_hashes(&img->elf, err, errsz) != 0) goto fail;
  text = elf_find(&img->elf, SEC_TEXT);
  symsec = elf_find(&img->elf, SEC_SYM);
  if (!text || !symsec) {
    snprintf(err, errsz, "missing %s or %s section", SEC_TEXT, SEC_SYM);
    goto fail;
  }
  if (text->size % VANISH_INSTR_SIZE != 0) {
    snprintf(err, errsz, "%s size is not a multiple of %u", SEC_TEXT,
             VANISH_INSTR_SIZE);
    goto fail;
  }
  img->ninstrs = text->size / VANISH_INSTR_SIZE;
  if (img->ninstrs > 0) {
    img->instrs = (vanish_instr_t *)malloc(img->ninstrs * sizeof(vanish_instr_t));
    if (!img->instrs) {
      snprintf(err, errsz, "out of memory");
      goto fail;
    }
    for (i = 0; i < img->ninstrs; i++) {
      const uint8_t *b = text->data + i * VANISH_INSTR_SIZE;
      img->instrs[i].op = b[0];
      img->instrs[i].operand = rd64le(b + 1);
    }
  }
  /* Count NUL-separated symbols. */
  if (symsec->size > 0) {
    for (i = 0; i < symsec->size; i++) {
      if (symsec->data[i] == 0) nsyms++;
    }
    if (symsec->data[symsec->size - 1] != 0) nsyms++;
  }
  img->nsyms = nsyms;
  if (nsyms > 0) {
    img->syms = (char **)calloc(nsyms, sizeof(char *));
    if (!img->syms) {
      snprintf(err, errsz, "out of memory");
      goto fail;
    }
    {
      size_t start = 0, idx = 0;
      for (i = 0; i <= symsec->size; i++) {
        if (i == symsec->size || symsec->data[i] == 0) {
          size_t len = i - start;
          if (len > 0) {
            img->syms[idx] = (char *)malloc(len + 1);
            if (!img->syms[idx]) {
              snprintf(err, errsz, "out of memory");
              goto fail;
            }
            memcpy(img->syms[idx], symsec->data + start, len);
            img->syms[idx][len] = '\0';
            idx++;
          }
          start = i + 1;
        }
      }
      img->nsyms = idx;
    }
  }
  return 0;
fail:
  vanish_image_free(img);
  return -1;
}

void vanish_print_instructions(const vanish_image_t *img, FILE *out) {
  size_t i;
  for (i = 0; i < img->ninstrs; i++) {
    const vanish_instr_t *in = &img->instrs[i];
    if (in->op == OP_PUSH_SYMBOL) {
      const char *sym = (in->operand >= 0 && (uint64_t)in->operand < img->nsyms)
                            ? img->syms[in->operand]
                            : "?";
      fprintf(out, "%zu: PUSH_SYMBOL %s\n", i, sym);
    } else if (in->op == OP_PUSH_INT) {
      fprintf(out, "%zu: PUSH_INT %lld\n", i, (long long)in->operand);
    } else {
      fprintf(out, "%zu: %s\n", i, vanish_op_name(in->op));
    }
  }
}

void vanish_image_free(vanish_image_t *img) {
  size_t i;
  if (!img) return;
  elf_free(&img->elf);
  for (i = 0; i < img->nsyms; i++) free(img->syms[i]);
  free(img->syms);
  free(img->instrs);
  memset(img, 0, sizeof(*img));
}
