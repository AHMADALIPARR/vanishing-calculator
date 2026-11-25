/* math/poly.h -- Integer polynomial representation and normal-form
 * arithmetic, shared by the VM's NORMALIZE step.
 *
 * A polynomial is a sum of terms. A term is an int64 coefficient times
 * a monomial, a product of variables raised to non-negative powers.
 * Variables are interned by name. Every operation returns its result
 * already in normal form: terms sorted by a fixed monomial order, like
 * terms combined, zero coefficients dropped. The zero polynomial is
 * the empty term list. Coefficients are int64; arithmetic that
 * overflows int64 is out of range for this layer and is not silently
 * wrapped: the VM's domain is small integers.
 */
#ifndef VANISH_POLY_H
#define VANISH_POLY_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  int var; /* interned variable index */
  int exp; /* exponent, >= 1 */
} poly_factor_t;

typedef struct {
  int64_t coeff;
  poly_factor_t *factors; /* sorted by var, length nfactors */
  size_t nfactors;
} poly_term_t;

typedef struct {
  poly_term_t *terms; /* sorted, no zero coefficients */
  size_t nterms;
  size_t cap;
} poly_t;

/* Intern a variable name, returning its index. */
int poly_var_index(const char *name);

/* Name of an interned variable index. */
const char *poly_var_name(int idx);

poly_t *poly_new(void);
void poly_free(poly_t *p);
poly_t *poly_copy(const poly_t *p);

/* Constant and variable polynomials. */
poly_t *poly_const(int64_t c);
poly_t *poly_var(const char *name);

/* Arithmetic. Each returns a fresh polynomial in normal form. */
poly_t *poly_add(const poly_t *a, const poly_t *b);
poly_t *poly_sub(const poly_t *a, const poly_t *b);
poly_t *poly_neg(const poly_t *a);
poly_t *poly_mul(const poly_t *a, const poly_t *b);
poly_t *poly_pow(const poly_t *a, uint64_t n);

/* Re-canonicalize in place: sort, combine like terms, drop zeros. */
void poly_normalize(poly_t *p);

int poly_is_zero(const poly_t *p);
int poly_equal(const poly_t *a, const poly_t *b);

/* True when p is a constant; its value is written to *out. */
int poly_is_const(const poly_t *p, int64_t *out);

/* Print form: "0", "x", "2*x", "x^2 + 2*x + 1", "-x + 3".
 * The caller frees the result. */
char *poly_to_string(const poly_t *p);

#endif /* VANISH_POLY_H */
