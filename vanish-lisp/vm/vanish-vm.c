/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

/* vm/vanish-vm.c -- Stack machine for the VANISH-LISP ELF ABI.
 * Loads an ELF object, verifies its hashes, and executes the
 * instruction stream in .vanish.text. Every stack value is an
 * integer polynomial (math/poly.h) in normal form, so the rewrite
 * rules of Vanish.Soundness.Step are exactly the polynomial ring
 * identities: x - x cancels to 0 in poly_sub, x * 0 is 0 in
 * poly_mul, x * 1 and x + 0 are identities in poly_mul and
 * poly_add. NORMALIZE re-canonicalizes the top of the stack.
 * ASSERT_ZERO passes exactly when the top of the stack is the zero
 * polynomial. VERIFY_PROOF recomputes the section digests and
 * compares them with .vanish.hash.
 *
 * Usage: vanish-vm file.elf
 * Exits 0 when the program halts after ASSERT_ZERO and VERIFY_PROOF
 * pass, 1 otherwise.
 */
#include "elfio.h"
#include "opcodes.h"
#include "poly.h"
#include "verify.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STACK_MAX 1024

static poly_t *stack[STACK_MAX];
static size_t sp = 0;

static void stack_push(poly_t *p) {
  if (sp >= STACK_MAX) {
    fprintf(stderr, "vanish-vm: stack overflow\n");
    exit(1);
  }
  stack[sp++] = p;
}

static poly_t *stack_pop(void) {
  if (sp == 0) {
    fprintf(stderr, "vanish-vm: stack underflow\n");
    exit(1);
  }
  return stack[--sp];
}

static poly_t *stack_top(void) {
  if (sp == 0) {
    fprintf(stderr, "vanish-vm: empty stack\n");
    exit(1);
  }
  return stack[sp - 1];
}

static void stack_free_all(void) {
  size_t i;
  for (i = 0; i < sp; i++) poly_free(stack[i]);
  sp = 0;
}

int main(int argc, char **argv) {
  vanish_image_t img;
  char err[256];
  size_t pc;

  if (argc != 2) {
    fprintf(stderr, "usage: vanish-vm file.elf\n");
    return 2;
  }
  if (vanish_image_load(argv[1], &img, err, sizeof(err)) != 0) {
    fprintf(stderr, "vanish-vm: %s\n", err);
    return 1;
  }
  printf("loaded %s: %zu instructions, %zu symbols\n", argv[1],
         img.ninstrs, img.nsyms);

  for (pc = 0; pc < img.ninstrs; pc++) {
    const vanish_instr_t *in = &img.instrs[pc];
    switch (in->op) {
      case OP_PUSH_SYMBOL: {
        const char *sym;
        poly_t *p;
        if (in->operand < 0 || (uint64_t)in->operand >= img.nsyms) {
          fprintf(stderr, "vanish-vm: bad symbol index %lld at %zu\n",
                  (long long)in->operand, pc);
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        sym = img.syms[in->operand];
        p = poly_var(sym);
        if (!p) {
          fprintf(stderr, "vanish-vm: out of memory\n");
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        stack_push(p);
        {
          char *s = poly_to_string(stack_top());
          printf("[%zu] PUSH_SYMBOL %s -> top: %s\n", pc, sym, s);
          free(s);
        }
        break;
      }
      case OP_PUSH_INT: {
        poly_t *p = poly_const(in->operand);
        char *s;
        if (!p) {
          fprintf(stderr, "vanish-vm: out of memory\n");
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        stack_push(p);
        s = poly_to_string(stack_top());
        printf("[%zu] PUSH_INT %lld -> top: %s\n", pc,
               (long long)in->operand, s);
        free(s);
        break;
      }
      case OP_DUP: {
        poly_t *p = poly_copy(stack_top());
        char *s;
        if (!p) {
          fprintf(stderr, "vanish-vm: out of memory\n");
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        stack_push(p);
        s = poly_to_string(stack_top());
        printf("[%zu] DUP -> top: %s\n", pc, s);
        free(s);
        break;
      }
      case OP_ADD:
      case OP_SUB:
      case OP_MUL: {
        poly_t *b = stack_pop();
        poly_t *a = stack_pop();
        poly_t *r = NULL;
        char *s;
        if (in->op == OP_ADD) r = poly_add(a, b);
        else if (in->op == OP_SUB) r = poly_sub(a, b);
        else r = poly_mul(a, b);
        poly_free(a);
        poly_free(b);
        if (!r) {
          fprintf(stderr, "vanish-vm: out of memory\n");
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        stack_push(r);
        s = poly_to_string(stack_top());
        printf("[%zu] %s -> top: %s\n", pc, vanish_op_name(in->op), s);
        free(s);
        break;
      }
      case OP_POW: {
        poly_t *exp = stack_pop();
        poly_t *base = stack_pop();
        int64_t n;
        poly_t *r;
        char *s;
        if (!poly_is_const(exp, &n) || n < 0) {
          fprintf(stderr, "vanish-vm: POW needs a non-negative integer exponent at %zu\n", pc);
          poly_free(exp);
          poly_free(base);
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        poly_free(exp);
        r = poly_pow(base, (uint64_t)n);
        poly_free(base);
        if (!r) {
          fprintf(stderr, "vanish-vm: out of memory\n");
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        stack_push(r);
        s = poly_to_string(stack_top());
        printf("[%zu] POW -> top: %s\n", pc, s);
        free(s);
        break;
      }
      case OP_NORMALIZE: {
        char *s;
        poly_normalize(stack_top());
        s = poly_to_string(stack_top());
        printf("[%zu] NORMALIZE -> top: %s\n", pc, s);
        free(s);
        break;
      }
      case OP_ASSERT_ZERO: {
        char *s = poly_to_string(stack_top());
        if (poly_is_zero(stack_top())) {
          printf("[%zu] ASSERT_ZERO OK: top is 0\n", pc);
          free(s);
        } else {
          printf("[%zu] ASSERT_ZERO FAIL: residual %s\n", pc, s);
          free(s);
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        break;
      }
      case OP_VERIFY_PROOF: {
        if (vanish_verify_hashes(&img.elf, err, sizeof(err)) != 0) {
          printf("[%zu] VERIFY_PROOF FAIL: %s\n", pc, err);
          stack_free_all();
          vanish_image_free(&img);
          return 1;
        }
        printf("[%zu] VERIFY_PROOF OK: digests match .vanish.hash\n", pc);
        break;
      }
      case OP_HALT: {
        char *s = poly_to_string(stack_top());
        printf("[%zu] HALT: top is %s\n", pc, s);
        free(s);
        stack_free_all();
        vanish_image_free(&img);
        return 0;
      }
      default: {
        fprintf(stderr, "vanish-vm: unknown opcode 0x%02x at %zu\n", in->op, pc);
        stack_free_all();
        vanish_image_free(&img);
        return 1;
      }
    }
  }
  fprintf(stderr, "vanish-vm: ran off the end without HALT\n");
  stack_free_all();
  vanish_image_free(&img);
  return 1;
}
