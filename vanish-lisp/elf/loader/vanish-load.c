/* elf/loader/vanish-load.c -- ELF loader and verifier for the
 * VANISH-LISP ABI. Reads an ELF object back, checks the ABI version
 * in .note.vanish, recomputes the SHA-256 digests in .vanish.hash and
 * compares them, and optionally dumps the instruction list and the
 * AST. This is the Load side of Load(ELF(M)) = M: the loader
 * reconstructs the program and initial state the writer sealed.
 *
 * Usage: vanish-load file.elf [--dump]
 * Exits 0 when every check passes, 1 otherwise.
 */
#include "elfio.h"
#include "opcodes.h"
#include "verify.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  vanish_image_t img;
  char err[256];
  int dump = 0;
  const elf_section_t *ast, *proof;

  if (argc < 2 || argc > 3 || (argc == 3 && strcmp(argv[2], "--dump") != 0)) {
    fprintf(stderr, "usage: vanish-load file.elf [--dump]\n");
    return 2;
  }
  dump = (argc == 3);

  if (vanish_image_load(argv[1], &img, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-load: %s\n", err);
    return 1;
  }
  printf("OK note: vanish ABI version %u\n", VANISH_ABI_VERSION);
  printf("OK hashes: .vanish.text .vanish.ast .vanish.proof .vanish.sym\n");
  printf("OK instructions: %zu\n", img.ninstrs);
  printf("OK symbols: %zu\n", img.nsyms);
  ast = elf_find(&img.elf, SEC_AST);
  proof = elf_find(&img.elf, SEC_PROOF);
  printf("OK ast: %llu bytes\n", (unsigned long long)ast->size);
  printf("OK proof: %llu bytes\n", (unsigned long long)proof->size);
  if (dump) {
    printf("--- instructions ---\n");
    vanish_print_instructions(&img, stdout);
    printf("--- ast ---\n");
    fwrite(ast->data, 1, ast->size, stdout);
    printf("\n--- proof ---\n");
    fwrite(proof->data, 1, proof->size, stdout);
    printf("\n");
  }
  vanish_image_free(&img);
  printf("LOAD OK\n");
  return 0;
}
