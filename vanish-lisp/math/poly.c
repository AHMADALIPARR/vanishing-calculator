/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

/* math/poly.c -- Integer polynomial normal-form arithmetic. */
#include "poly.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- Variable interning ---- */

#define MAX_VARS 256
static char *var_names[MAX_VARS];
static int nvars = 0;

int poly_var_index(const char *name) {
  int i;
  for (i = 0; i < nvars; i++) {
    if (strcmp(var_names[i], name) == 0) return i;
  }
  if (nvars >= MAX_VARS) return -1;
  var_names[nvars] = strdup(name);
  if (!var_names[nvars]) return -1;
  return nvars++;
}

const char *poly_var_name(int idx) {
  if (idx < 0 || idx >= nvars) return "?";
  return var_names[idx];
}

/* ---- Terms ---- */

static int factor_cmp(const poly_factor_t *a, const poly_factor_t *b) {
  if (a->var != b->var) return a->var < b->var ? -1 : 1;
  if (a->exp != b->exp) return a->exp < b->exp ? -1 : 1;
  return 0;
}

/* Total order on monomials: total degree first (higher degree first),
 * then factor lists lexicographically; a shorter list that is a prefix
 * sorts first. The constant term sorts last. */
static int mono_degree(const poly_term_t *t) {
  int d = 0;
  size_t i;
  for (i = 0; i < t->nfactors; i++) d += t->factors[i].exp;
  return d;
}

static int mono_cmp(const poly_term_t *a, const poly_term_t *b) {
  int da = mono_degree(a), db = mono_degree(b);
  size_t i, n;
  if (da != db) return da > db ? -1 : 1;
  n = a->nfactors < b->nfactors ? a->nfactors : b->nfactors;
  for (i = 0; i < n; i++) {
    int c = factor_cmp(&a->factors[i], &b->factors[i]);
    if (c != 0) return c;
  }
  if (a->nfactors != b->nfactors) return a->nfactors < b->nfactors ? -1 : 1;
  return 0;
}

static int term_cmp_qsort(const void *pa, const void *pb) {
  return mono_cmp((const poly_term_t *)pa, (const poly_term_t *)pb);
}

static void term_free(poly_term_t *t) {
  free(t->factors);
  t->factors = NULL;
  t->nfactors = 0;
}

static int term_copy_into(poly_term_t *dst, const poly_term_t *src) {
  dst->coeff = src->coeff;
  dst->nfactors = src->nfactors;
  dst->factors = NULL;
  if (src->nfactors > 0) {
    dst->factors = (poly_factor_t *)malloc(src->nfactors * sizeof(poly_factor_t));
    if (!dst->factors) return -1;
    memcpy(dst->factors, src->factors, src->nfactors * sizeof(poly_factor_t));
  }
  return 0;
}

/* ---- Polynomials ---- */

poly_t *poly_new(void) {
  poly_t *p = (poly_t *)calloc(1, sizeof(poly_t));
  return p;
}

void poly_free(poly_t *p) {
  size_t i;
  if (!p) return;
  for (i = 0; i < p->nterms; i++) term_free(&p->terms[i]);
  free(p->terms);
  free(p);
}

static int poly_push_term(poly_t *p, const poly_term_t *t) {
  if (p->nterms == p->cap) {
    size_t ncap = p->cap ? p->cap * 2 : 8;
    poly_term_t *nt = (poly_term_t *)realloc(p->terms, ncap * sizeof(poly_term_t));
    if (!nt) return -1;
    p->terms = nt;
    p->cap = ncap;
  }
  if (term_copy_into(&p->terms[p->nterms], t) != 0) return -1;
  p->nterms++;
  return 0;
}

poly_t *poly_copy(const poly_t *p) {
  poly_t *q = poly_new();
  size_t i;
  if (!q) return NULL;
  for (i = 0; i < p->nterms; i++) {
    if (poly_push_term(q, &p->terms[i]) != 0) {
      poly_free(q);
      return NULL;
    }
  }
  return q;
}

void poly_normalize(poly_t *p) {
  size_t i, w = 0;
  if (p->nterms > 1) {
    qsort(p->terms, p->nterms, sizeof(poly_term_t), term_cmp_qsort);
  }
  for (i = 0; i < p->nterms; i++) {
    if (w > 0 && mono_cmp(&p->terms[w - 1], &p->terms[i]) == 0) {
      p->terms[w - 1].coeff += p->terms[i].coeff;
      term_free(&p->terms[i]);
    } else {
      p->terms[w++] = p->terms[i];
    }
  }
  p->nterms = w;
  /* Drop zero coefficients, compacting. */
  w = 0;
  for (i = 0; i < p->nterms; i++) {
    if (p->terms[i].coeff == 0) {
      term_free(&p->terms[i]);
    } else {
      if (w != i) p->terms[w] = p->terms[i];
      w++;
    }
  }
  p->nterms = w;
}

poly_t *poly_const(int64_t c) {
  poly_t *p = poly_new();
  poly_term_t t;
  if (!p) return NULL;
  if (c == 0) return p;
  t.coeff = c;
  t.factors = NULL;
  t.nfactors = 0;
  if (poly_push_term(p, &t) != 0) {
    poly_free(p);
    return NULL;
  }
  return p;
}

poly_t *poly_var(const char *name) {
  poly_t *p = poly_new();
  poly_term_t t;
  int idx = poly_var_index(name);
  if (!p || idx < 0) {
    poly_free(p);
    return NULL;
  }
  t.coeff = 1;
  t.nfactors = 1;
  t.factors = (poly_factor_t *)malloc(sizeof(poly_factor_t));
  if (!t.factors) {
    poly_free(p);
    return NULL;
  }
  t.factors[0].var = idx;
  t.factors[0].exp = 1;
  if (poly_push_term(p, &t) != 0) {
    free(t.factors);
    poly_free(p);
    return NULL;
  }
  free(t.factors);
  return p;
}

int poly_is_zero(const poly_t *p) {
  return p->nterms == 0;
}

int poly_equal(const poly_t *a, const poly_t *b) {
  size_t i;
  if (a->nterms != b->nterms) return 0;
  for (i = 0; i < a->nterms; i++) {
    if (a->terms[i].coeff != b->terms[i].coeff) return 0;
    if (mono_cmp(&a->terms[i], &b->terms[i]) != 0) return 0;
  }
  return 1;
}

int poly_is_const(const poly_t *p, int64_t *out) {
  if (p->nterms == 0) {
    *out = 0;
    return 1;
  }
  if (p->nterms == 1 && p->terms[0].nfactors == 0) {
    *out = p->terms[0].coeff;
    return 1;
  }
  return 0;
}

poly_t *poly_add(const poly_t *a, const poly_t *b) {
  poly_t *r = poly_copy(a);
  size_t i;
  if (!r) return NULL;
  for (i = 0; i < b->nterms; i++) {
    if (poly_push_term(r, &b->terms[i]) != 0) {
      poly_free(r);
      return NULL;
    }
  }
  poly_normalize(r);
  return r;
}

poly_t *poly_neg(const poly_t *a) {
  poly_t *r = poly_copy(a);
  size_t i;
  if (!r) return NULL;
  for (i = 0; i < r->nterms; i++) r->terms[i].coeff = -r->terms[i].coeff;
  return r;
}

poly_t *poly_sub(const poly_t *a, const poly_t *b) {
  poly_t *nb = poly_neg(b);
  poly_t *r;
  if (!nb) return NULL;
  r = poly_add(a, nb);
  poly_free(nb);
  return r;
}

static int merge_factors(const poly_term_t *a, const poly_term_t *b,
                         poly_factor_t **out, size_t *nout) {
  size_t i = 0, j = 0, w = 0;
  poly_factor_t *f = (poly_factor_t *)malloc(
      (a->nfactors + b->nfactors) * sizeof(poly_factor_t));
  if (!f && (a->nfactors + b->nfactors) > 0) return -1;
  while (i < a->nfactors && j < b->nfactors) {
    if (a->factors[i].var < b->factors[j].var) {
      f[w++] = a->factors[i++];
    } else if (a->factors[i].var > b->factors[j].var) {
      f[w++] = b->factors[j++];
    } else {
      f[w].var = a->factors[i].var;
      f[w].exp = a->factors[i].exp + b->factors[j].exp;
      w++;
      i++;
      j++;
    }
  }
  while (i < a->nfactors) f[w++] = a->factors[i++];
  while (j < b->nfactors) f[w++] = b->factors[j++];
  *out = f;
  *nout = w;
  return 0;
}

poly_t *poly_mul(const poly_t *a, const poly_t *b) {
  poly_t *r = poly_new();
  size_t i, j;
  if (!r) return NULL;
  for (i = 0; i < a->nterms; i++) {
    for (j = 0; j < b->nterms; j++) {
      poly_term_t t;
      t.coeff = a->terms[i].coeff * b->terms[j].coeff;
      if (merge_factors(&a->terms[i], &b->terms[j], &t.factors, &t.nfactors) != 0) {
        poly_free(r);
        return NULL;
      }
      if (poly_push_term(r, &t) != 0) {
        free(t.factors);
        poly_free(r);
        return NULL;
      }
      free(t.factors);
    }
  }
  poly_normalize(r);
  return r;
}

poly_t *poly_pow(const poly_t *a, uint64_t n) {
  poly_t *result = poly_const(1);
  poly_t *base = poly_copy(a);
  poly_t *tmp;
  if (!result || !base) {
    poly_free(result);
    poly_free(base);
    return NULL;
  }
  while (n > 0) {
    if (n & 1u) {
      tmp = poly_mul(result, base);
      poly_free(result);
      result = tmp;
      if (!result) {
        poly_free(base);
        return NULL;
      }
    }
    n >>= 1;
    if (n > 0) {
      tmp = poly_mul(base, base);
      poly_free(base);
      base = tmp;
      if (!base) {
        poly_free(result);
        return NULL;
      }
    }
  }
  poly_free(base);
  return result;
}

char *poly_to_string(const poly_t *p) {
  size_t cap = 64, len = 0, i, j;
  char *buf = (char *)malloc(cap);
  if (!buf) return NULL;
  buf[0] = '\0';
  if (p->nterms == 0) {
    strcpy(buf, "0");
    return buf;
  }
  for (i = 0; i < p->nterms; i++) {
    const poly_term_t *t = &p->terms[i];
    char tmp[256];
    int tlen;
    /* Build one term: [coeff*]factor[^exp]... */
    if (t->nfactors == 0) {
      /* Constant term: print the absolute value; the join supplies
       * the sign, so a negative constant never prints twice. */
      tlen = snprintf(tmp, sizeof(tmp), "%lld",
                      (long long)(t->coeff < 0 ? -t->coeff : t->coeff));
    } else {
      int need_coeff = (t->coeff != 1 && t->coeff != -1);
      if (need_coeff) {
        tlen = snprintf(tmp, sizeof(tmp), "%lld*", (long long)(t->coeff < 0 ? -t->coeff : t->coeff));
      } else {
        tmp[0] = '\0';
        tlen = 0;
      }
      for (j = 0; j < t->nfactors; j++) {
        char piece[64];
        if (t->factors[j].exp == 1) {
          snprintf(piece, sizeof(piece), "%s", poly_var_name(t->factors[j].var));
        } else {
          snprintf(piece, sizeof(piece), "%s^%d", poly_var_name(t->factors[j].var),
                   t->factors[j].exp);
        }
        if (j > 0) {
          tlen += snprintf(tmp + tlen, sizeof(tmp) - (size_t)tlen, "*%s", piece);
        } else {
          tlen += snprintf(tmp + tlen, sizeof(tmp) - (size_t)tlen, "%s", piece);
        }
      }
    }
    /* Join with sign. */
    {
      const char *sep;
      int neg = (t->coeff < 0);
      if (i == 0) {
        sep = neg ? "-" : "";
      } else {
        sep = neg ? " - " : " + ";
      }
      size_t need = len + strlen(sep) + strlen(tmp) + 1;
      if (need > cap) {
        while (cap < need) cap *= 2;
        buf = (char *)realloc(buf, cap);
        if (!buf) return NULL;
      }
      strcpy(buf + len, sep);
      len += strlen(sep);
      strcpy(buf + len, tmp);
      len += strlen(tmp);
    }
    (void)tlen;
  }
  return buf;
}
