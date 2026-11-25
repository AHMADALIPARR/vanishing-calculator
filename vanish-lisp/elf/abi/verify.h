/* elf/abi/verify.h -- Shared ELF image loading, verification and
 * instruction decoding for the loader and the VM. */
#ifndef VANISH_VERIFY_H
#define VANISH_VERIFY_H

#include "elfio.h"
#include "opcodes.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
  uint8_t op;
  int64_t operand;
} vanish_instr_t;

typedef struct {
  elf_file_t elf;
  char **syms;      /* symbol table, first-use order */
  size_t nsyms;
  vanish_instr_t *instrs;
  size_t ninstrs;
} vanish_image_t;

/* Load an ELF file, check the .note.vanish version, recompute the
 * SHA-256 digests in .vanish.hash and compare them, and decode the
 * instruction stream and symbol table. Returns 0 on success, -1 on
 * failure with a message in err. */
int vanish_image_load(const char *path, vanish_image_t *img,
                      char *err, size_t errsz);

/* Recompute the section digests of an already loaded image and
 * compare them with .vanish.hash. Returns 0 when they match. */
int vanish_verify_hashes(const elf_file_t *f, char *err, size_t errsz);

/* Print the decoded instruction list to out. */
void vanish_print_instructions(const vanish_image_t *img, FILE *out);

void vanish_image_free(vanish_image_t *img);

#endif /* VANISH_VERIFY_H */
