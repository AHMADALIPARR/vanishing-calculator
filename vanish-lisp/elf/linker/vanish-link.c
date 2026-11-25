/* elf/linker/vanish-link.c -- Linker for the VANISH-LISP ABI.
 * Combines two independently compiled ELF objects into one: the
 * first module's trailing HALT is dropped so execution continues
 * into the second module, the symbol tables are unioned with the
 * second module's PUSH_SYMBOL operands remapped, the AST and proof
 * sections are concatenated in order, and the digests are
 * recomputed. The linked .vanish.ast holds the two AST documents in
 * sequence.
 *
 * Usage: vanish-link -o out.elf a.elf b.elf
 */
#include "elfio.h"
#include "opcodes.h"
#include "sha256.h"
#include "verify.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wr32le(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xffu);
  p[1] = (uint8_t)((v >> 8) & 0xffu);
  p[2] = (uint8_t)((v >> 16) & 0xffu);
  p[3] = (uint8_t)((v >> 24) & 0xffu);
}

static void free_syms(char **syms, size_t n) {
  size_t i;
  if (!syms) return;
  for (i = 0; i < n; i++) free(syms[i]);
  free(syms);
}

int main(int argc, char **argv) {
  vanish_image_t a, b;
  char err[256];
  const elf_section_t *atext, *btext, *aast, *bast, *aproof, *bproof;
  char **syma, **symb, **syms = NULL;
  size_t nsyma, nsymb, nsyms = 0, symcap = 0, i;
  int64_t *remap = NULL;
  uint8_t *text = NULL, *symdata = NULL, *ast = NULL, *proof = NULL;
  size_t textlen, symlen = 0, astlen, prooflen;
  char hash_text[65], hash_ast[65], hash_proof[65], hash_sym[65];
  uint8_t digest[SHA256_DIGEST_SIZE];
  char hashsec[512];
  uint8_t note[12 + 8 + NOTE_DESC_SIZE];
  elf_section_t secs[6];
  int rc = 1;

  if (argc != 5 || strcmp(argv[1], "-o") != 0) {
    fprintf(stderr, "usage: vanish-link -o out.elf a.elf b.elf\n");
    return 2;
  }
  if (vanish_image_load(argv[3], &a, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-link: %s: %s\n", argv[3], err);
    return 1;
  }
  if (vanish_image_load(argv[4], &b, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-link: %s: %s\n", argv[4], err);
    vanish_image_free(&a);
    return 1;
  }
  if (a.ninstrs == 0 || b.ninstrs == 0 ||
      a.instrs[a.ninstrs - 1].op != OP_HALT ||
      b.instrs[b.ninstrs - 1].op != OP_HALT) {
    fprintf(stderr, "vanish-link: both modules must end in HALT\n");
    goto done;
  }
  atext = elf_find(&a.elf, SEC_TEXT);
  btext = elf_find(&b.elf, SEC_TEXT);
  aast = elf_find(&a.elf, SEC_AST);
  bast = elf_find(&b.elf, SEC_AST);
  aproof = elf_find(&a.elf, SEC_PROOF);
  bproof = elf_find(&b.elf, SEC_PROOF);
  syma = a.syms;
  nsyma = a.nsyms;
  symb = b.syms;
  nsymb = b.nsyms;

  /* Union the symbol tables, a's order first. */
  for (i = 0; i < nsyma; i++) {
    if (nsyms == symcap) {
      size_t ncap = symcap ? symcap * 2 : 8;
      char **ns = (char **)realloc(syms, ncap * sizeof(char *));
      if (!ns) goto done;
      syms = ns;
      symcap = ncap;
    }
    syms[nsyms++] = strdup(syma[i]);
  }
  remap = (int64_t *)malloc((nsymb ? nsymb : 1) * sizeof(int64_t));
  if (!remap) goto done;
  for (i = 0; i < nsymb; i++) {
    size_t j;
    int found = -1;
    for (j = 0; j < nsyms; j++) {
      if (strcmp(syms[j], symb[i]) == 0) {
        found = (int)j;
        break;
      }
    }
    if (found < 0) {
      if (nsyms == symcap) {
        size_t ncap = symcap ? symcap * 2 : 8;
        char **ns = (char **)realloc(syms, ncap * sizeof(char *));
        if (!ns) goto done;
        syms = ns;
        symcap = ncap;
      }
      syms[nsyms] = strdup(symb[i]);
      found = (int)nsyms;
      nsyms++;
    }
    remap[i] = found;
  }

  /* Text: a without its trailing HALT, then b with remapped symbols. */
  textlen = (a.ninstrs - 1 + b.ninstrs) * VANISH_INSTR_SIZE;
  text = (uint8_t *)malloc(textlen ? textlen : 1);
  if (!text) goto done;
  {
    size_t w = 0, k;
    for (k = 0; k < a.ninstrs - 1; k++) {
      memcpy(text + w, atext->data + k * VANISH_INSTR_SIZE, VANISH_INSTR_SIZE);
      w += VANISH_INSTR_SIZE;
    }
    for (k = 0; k < b.ninstrs; k++) {
      uint8_t *dst = text + w;
      const uint8_t *src = btext->data + k * VANISH_INSTR_SIZE;
      int j;
      memcpy(dst, src, VANISH_INSTR_SIZE);
      if (dst[0] == OP_PUSH_SYMBOL) {
        int64_t old = 0;
        for (j = 0; j < 8; j++) old |= (int64_t)src[1 + j] << (8 * j);
        if (old < 0 || (uint64_t)old >= nsymb) {
          fprintf(stderr, "vanish-link: bad symbol index in %s\n", argv[4]);
          goto done;
        }
        {
          uint64_t nv = (uint64_t)remap[old];
          for (j = 0; j < 8; j++) dst[1 + j] = (uint8_t)((nv >> (8 * j)) & 0xffu);
        }
      }
      w += VANISH_INSTR_SIZE;
    }
  }

  /* Symbol table bytes. */
  for (i = 0; i < nsyms; i++) symlen += strlen(syms[i]) + 1;
  symdata = (uint8_t *)malloc(symlen ? symlen : 1);
  if (!symdata) goto done;
  {
    size_t p = 0;
    for (i = 0; i < nsyms; i++) {
      size_t l = strlen(syms[i]);
      memcpy(symdata + p, syms[i], l);
      p += l;
      symdata[p++] = 0;
    }
  }

  /* AST and proof concatenate in order. */
  astlen = aast->size + bast->size;
  ast = (uint8_t *)malloc(astlen ? astlen : 1);
  if (!ast) goto done;
  memcpy(ast, aast->data, aast->size);
  memcpy(ast + aast->size, bast->data, bast->size);
  prooflen = aproof->size + bproof->size;
  proof = (uint8_t *)malloc(prooflen ? prooflen : 1);
  if (!proof) goto done;
  memcpy(proof, aproof->data, aproof->size);
  memcpy(proof + aproof->size, bproof->data, bproof->size);

  sha256(text, textlen, digest);
  sha256_hex(digest, hash_text);
  sha256(ast, astlen, digest);
  sha256_hex(digest, hash_ast);
  sha256(proof, prooflen, digest);
  sha256_hex(digest, hash_proof);
  sha256(symdata, symlen, digest);
  sha256_hex(digest, hash_sym);
  snprintf(hashsec, sizeof(hashsec),
           "%s  %s\n%s  %s\n%s  %s\n%s  %s\n",
           hash_text, SEC_TEXT, hash_ast, SEC_AST, hash_proof, SEC_PROOF,
           hash_sym, SEC_SYM);

  memset(note, 0, sizeof(note));
  wr32le(note + 0, 8);
  wr32le(note + 4, NOTE_DESC_SIZE);
  wr32le(note + 8, NT_VANISH_ABI);
  memcpy(note + 12, "vanish", 6);
  wr32le(note + 20, VANISH_ABI_VERSION);
  wr32le(note + 24, 0);

  memset(secs, 0, sizeof(secs));
  secs[0].name = (char *)SEC_TEXT;
  secs[0].type = 1;
  secs[0].data = text;
  secs[0].size = textlen;
  secs[1].name = (char *)SEC_AST;
  secs[1].type = 1;
  secs[1].data = ast;
  secs[1].size = astlen;
  secs[2].name = (char *)SEC_PROOF;
  secs[2].type = 1;
  secs[2].data = proof;
  secs[2].size = prooflen;
  secs[3].name = (char *)SEC_SYM;
  secs[3].type = 1;
  secs[3].data = symdata;
  secs[3].size = symlen;
  secs[4].name = (char *)SEC_HASH;
  secs[4].type = 1;
  secs[4].data = (uint8_t *)hashsec;
  secs[4].size = strlen(hashsec);
  secs[5].name = (char *)SEC_NOTE;
  secs[5].type = 7;
  secs[5].data = note;
  secs[5].size = sizeof(note);

  if (elf_write_file(argv[2], secs, 6, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-link: %s\n", err);
    goto done;
  }
  printf("linked %s + %s -> %s: %zu instructions, %zu symbols\n", argv[3],
         argv[4], argv[2], (a.ninstrs - 1 + b.ninstrs), nsyms);
  rc = 0;
done:
  vanish_image_free(&a);
  vanish_image_free(&b);
  free_syms(syms, nsyms);
  free(remap);
  free(text);
  free(symdata);
  free(ast);
  free(proof);
  return rc;
}
