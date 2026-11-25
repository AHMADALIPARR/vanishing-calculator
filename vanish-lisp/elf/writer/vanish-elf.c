/* elf/writer/vanish-elf.c -- ELF64 emitter for the VANISH-LISP ABI.
 * Reads a lowered program (program XML from xslt/lower.xsl), the
 * canonical AST (vanish XML) and the certificate XML (from
 * xslt/certificates.xsl), and writes the ELF object with the
 * .vanish.text, .vanish.ast, .vanish.proof, .vanish.sym, .vanish.hash
 * and .note.vanish sections. The writer recomputes the digests and
 * refuses to seal a certificate whose hashes disagree with the
 * artifacts it is sealing.
 *
 * Usage: vanish-elf -o out.elf program.xml ast.xml cert.xml
 */
#include "elfio.h"
#include "opcodes.h"
#include "sha256.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *read_file(const char *path, size_t *len_out) {
  FILE *f = fopen(path, "rb");
  uint8_t *buf;
  size_t len, got;
  if (!f) {
    fprintf(stderr, "vanish-elf: cannot open %s\n", path);
    return NULL;
  }
  fseek(f, 0, SEEK_END);
  len = (size_t)ftell(f);
  fseek(f, 0, SEEK_SET);
  buf = (uint8_t *)malloc(len + 1);
  if (!buf) {
    fclose(f);
    return NULL;
  }
  got = fread(buf, 1, len, f);
  fclose(f);
  if (got != len) {
    free(buf);
    return NULL;
  }
  buf[len] = '\0'; /* NUL-terminate so strstr stays in bounds */
  *len_out = len;
  return buf;
}

static int opcode_number(const char *name) {
  if (strcmp(name, "PUSH_SYMBOL") == 0) return OP_PUSH_SYMBOL;
  if (strcmp(name, "PUSH_INT") == 0) return OP_PUSH_INT;
  if (strcmp(name, "DUP") == 0) return OP_DUP;
  if (strcmp(name, "ADD") == 0) return OP_ADD;
  if (strcmp(name, "SUB") == 0) return OP_SUB;
  if (strcmp(name, "MUL") == 0) return OP_MUL;
  if (strcmp(name, "POW") == 0) return OP_POW;
  if (strcmp(name, "NORMALIZE") == 0) return OP_NORMALIZE;
  if (strcmp(name, "ASSERT_ZERO") == 0) return OP_ASSERT_ZERO;
  if (strcmp(name, "VERIFY_PROOF") == 0) return OP_VERIFY_PROOF;
  if (strcmp(name, "HALT") == 0) return OP_HALT;
  return -1;
}

typedef struct {
  uint8_t op;
  int64_t operand;
  char *symbol; /* owned, only for PUSH_SYMBOL */
} prog_instr_t;

static char *trim_dup(const char *s, size_t len) {
  while (len > 0 && (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r')) {
    s++;
    len--;
  }
  while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\t' ||
                     s[len - 1] == '\n' || s[len - 1] == '\r')) {
    len--;
  }
  {
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, s, len);
    out[len] = '\0';
    return out;
  }
}

/* Parse the lowered program XML. The format is restricted: a <program>
 * of <instruction opcode="NAME">text</instruction> or
 * <instruction opcode="NAME"/> elements, exactly as xslt/lower.xsl
 * emits it. Returns the instruction count, or -1 on error. */
static int parse_program(const uint8_t *xml, size_t len,
                         prog_instr_t **out, size_t *nout) {
  size_t cap = 16, n = 0, pos = 0;
  prog_instr_t *ins = (prog_instr_t *)calloc(cap, sizeof(prog_instr_t));
  if (!ins) return -1;
  if (!strstr((const char *)xml, "<program>") &&
      !strstr((const char *)xml, "<program ")) {
    fprintf(stderr, "vanish-elf: program XML has no <program> root\n");
    free(ins);
    return -1;
  }
  while (pos < len) {
    const char *p = strstr((const char *)xml + pos, "<instruction");
    const char *op_at, *op_end, *gt, *close;
    char opname[32];
    size_t oplen;
    char *text = NULL;
    int op;
    if (!p) break;
    op_at = strstr(p, "opcode=\"");
    if (!op_at) {
      fprintf(stderr, "vanish-elf: instruction without opcode\n");
      goto fail;
    }
    op_at += 8;
    op_end = strchr(op_at, '"');
    if (!op_end || (size_t)(op_end - op_at) >= sizeof(opname)) {
      fprintf(stderr, "vanish-elf: bad opcode attribute\n");
      goto fail;
    }
    oplen = (size_t)(op_end - op_at);
    memcpy(opname, op_at, oplen);
    opname[oplen] = '\0';
    op = opcode_number(opname);
    if (op < 0) {
      fprintf(stderr, "vanish-elf: unknown opcode %s\n", opname);
      goto fail;
    }
    gt = strchr(op_end, '>');
    if (!gt) {
      fprintf(stderr, "vanish-elf: truncated instruction element\n");
      goto fail;
    }
    if (gt[-1] == '/') {
      text = trim_dup("", 0);
    } else {
      close = strstr(gt + 1, "</instruction>");
      if (!close) {
        fprintf(stderr, "vanish-elf: unterminated instruction element\n");
        goto fail;
      }
      text = trim_dup(gt + 1, (size_t)(close - (gt + 1)));
      pos = (size_t)(close - (const char *)xml) + 14;
    }
    if (!text) goto fail;
    if (gt[-1] == '/') pos = (size_t)(gt - (const char *)xml) + 1;
    if (n == cap) {
      prog_instr_t *ni;
      cap *= 2;
      ni = (prog_instr_t *)realloc(ins, cap * sizeof(prog_instr_t));
      if (!ni) {
        free(text);
        goto fail;
      }
      ins = ni;
    }
    ins[n].op = (uint8_t)op;
    ins[n].operand = 0;
    ins[n].symbol = NULL;
    if (op == OP_PUSH_SYMBOL) {
      if (text[0] == '\0') {
        fprintf(stderr, "vanish-elf: PUSH_SYMBOL without a symbol\n");
        free(text);
        goto fail;
      }
      ins[n].symbol = text;
    } else if (op == OP_PUSH_INT) {
      char *end = NULL;
      long long v = strtoll(text, &end, 10);
      if (!end || *end != '\0' || end == text) {
        fprintf(stderr, "vanish-elf: PUSH_INT with a bad integer '%s'\n", text);
        free(text);
        goto fail;
      }
      ins[n].operand = (int64_t)v;
      free(text);
    } else {
      if (text[0] != '\0') {
        fprintf(stderr, "vanish-elf: %s carries text\n", opname);
        free(text);
        goto fail;
      }
      free(text);
    }
    n++;
  }
  *out = ins;
  *nout = n;
  return 0;
fail:
  {
    size_t i;
    for (i = 0; i < n; i++) free(ins[i].symbol);
    free(ins);
  }
  return -1;
}

/* Extract the hex digest for one section from the certificate XML. */
static int cert_hash(const uint8_t *cert, size_t len, const char *section,
                     char hex[65]) {
  char needle[64];
  const char *p, *gt, *lt;
  snprintf(needle, sizeof(needle), "<hash section=\"%s\"", section);
  p = strstr((const char *)cert, needle);
  if (!p) return -1;
  gt = strchr(p, '>');
  if (!gt) return -1;
  gt++;
  while (gt < (const char *)cert + len &&
         (*gt == ' ' || *gt == '\t' || *gt == '\n' || *gt == '\r')) {
    gt++;
  }
  lt = strchr(gt, '<');
  if (!lt || (size_t)(lt - gt) != 64) return -1;
  memcpy(hex, gt, 64);
  hex[64] = '\0';
  return 0;
}

static void wr32le(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xffu);
  p[1] = (uint8_t)((v >> 8) & 0xffu);
  p[2] = (uint8_t)((v >> 16) & 0xffu);
  p[3] = (uint8_t)((v >> 24) & 0xffu);
}

int main(int argc, char **argv) {
  const char *outpath = NULL, *progpath, *astpath, *certpath;
  uint8_t *progxml = NULL, *ast = NULL, *cert = NULL;
  size_t proglen, astlen, certlen;
  prog_instr_t *ins = NULL;
  size_t nins = 0, i;
  char **syms = NULL;
  size_t nsyms = 0, symcap = 0;
  uint8_t *text = NULL;
  size_t textlen;
  uint8_t *symdata = NULL;
  size_t symlen = 0;
  char hash_text[65], hash_ast[65], hash_proof[65], hash_sym[65];
  char hash_progxml[65];
  char cert_hash_ast[65], cert_hash_text[65];
  uint8_t digest[SHA256_DIGEST_SIZE];
  char hashsec[512];
  uint8_t note[12 + 8 + NOTE_DESC_SIZE];
  elf_section_t secs[6];
  char err[256];
  int rc = 1;

  if (argc != 6 || strcmp(argv[1], "-o") != 0) {
    fprintf(stderr, "usage: vanish-elf -o out.elf program.xml ast.xml cert.xml\n");
    return 2;
  }
  outpath = argv[2];
  progpath = argv[3];
  astpath = argv[4];
  certpath = argv[5];

  progxml = read_file(progpath, &proglen);
  ast = read_file(astpath, &astlen);
  cert = read_file(certpath, &certlen);
  if (!progxml || !ast || !cert) goto done;

  if (parse_program(progxml, proglen, &ins, &nins) != 0) goto done;

  /* Symbol table in first-use order. */
  for (i = 0; i < nins; i++) {
    size_t j;
    int found = -1;
    if (ins[i].op != OP_PUSH_SYMBOL) continue;
    for (j = 0; j < nsyms; j++) {
      if (strcmp(syms[j], ins[i].symbol) == 0) {
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
      syms[nsyms] = ins[i].symbol;
      ins[i].symbol = NULL; /* ownership moves to the table */
      found = (int)nsyms;
      nsyms++;
    }
    ins[i].operand = found;
  }
  /* Duplicate symbols' strings are freed once in the cleanup below;
   * first-use strings now belong to the symbol table. */

  /* Encode .vanish.text. */
  textlen = nins * VANISH_INSTR_SIZE;
  text = (uint8_t *)malloc(textlen ? textlen : 1);
  if (!text) goto done;
  for (i = 0; i < nins; i++) {
    uint8_t *b = text + i * VANISH_INSTR_SIZE;
    uint64_t v = (uint64_t)ins[i].operand;
    int k;
    b[0] = ins[i].op;
    for (k = 0; k < 8; k++) b[1 + k] = (uint8_t)((v >> (8 * k)) & 0xffu);
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

  /* Digests. The .vanish.hash digests cover the sealed section bytes.
   * The certificate's .vanish.text digest covers the lowered program
   * XML, the source the section was encoded from, so the writer
   * checks the certificate against the program XML bytes it read. */
  sha256(text, textlen, digest);
  sha256_hex(digest, hash_text);
  sha256(ast, astlen, digest);
  sha256_hex(digest, hash_ast);
  sha256(cert, certlen, digest);
  sha256_hex(digest, hash_proof);
  sha256(symdata, symlen, digest);
  sha256_hex(digest, hash_sym);
  sha256(progxml, proglen, digest);
  sha256_hex(digest, hash_progxml);

  /* The certificate must agree with the artifacts it seals. */
  if (cert_hash(cert, certlen, SEC_AST, cert_hash_ast) != 0 ||
      cert_hash(cert, certlen, SEC_TEXT, cert_hash_text) != 0) {
    fprintf(stderr, "vanish-elf: certificate carries no digests\n");
    goto done;
  }
  if (strcmp(cert_hash_ast, hash_ast) != 0 ||
      strcmp(cert_hash_text, hash_progxml) != 0) {
    fprintf(stderr,
            "vanish-elf: certificate digests disagree with the artifacts\n");
    goto done;
  }

  snprintf(hashsec, sizeof(hashsec),
           "%s  %s\n%s  %s\n%s  %s\n%s  %s\n",
           hash_text, SEC_TEXT, hash_ast, SEC_AST, hash_proof, SEC_PROOF,
           hash_sym, SEC_SYM);

  /* Note section: namesz, descsz, type, name "vanish\0", descriptor. */
  memset(note, 0, sizeof(note));
  wr32le(note + 0, 8); /* namesz: "vanish\0" padded to 8 */
  wr32le(note + 4, NOTE_DESC_SIZE);
  wr32le(note + 8, NT_VANISH_ABI);
  memcpy(note + 12, "vanish", 6);
  wr32le(note + 20, VANISH_ABI_VERSION);
  wr32le(note + 24, 0);
  /* bytes 28..35 stay zero (reserved) */

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
  secs[2].data = cert;
  secs[2].size = certlen;
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

  if (elf_write_file(outpath, secs, 6, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-elf: %s\n", err);
    goto done;
  }
  printf("wrote %s: %zu instructions, %zu symbols\n", outpath, nins, nsyms);
  printf("  %s %s\n  %s %s\n  %s %s\n  %s %s\n", hash_text, SEC_TEXT,
         hash_ast, SEC_AST, hash_proof, SEC_PROOF, hash_sym, SEC_SYM);
  rc = 0;
done:
  free(progxml);
  free(ast);
  free(cert);
  if (ins) {
    for (i = 0; i < nins; i++) free(ins[i].symbol);
    free(ins);
  }
  for (i = 0; i < nsyms; i++) free(syms[i]);
  free(syms);
  free(text);
  free(symdata);
  return rc;
}
