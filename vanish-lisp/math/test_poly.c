/* math/test_poly.c -- Standalone test for the polynomial layer.
 * Prints PASS/FAIL per check; exits non-zero on any failure. */
#include "poly.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

static void check(const char *name, int ok) {
  if (ok) {
    printf("PASS %s\n", name);
  } else {
    printf("FAIL %s\n", name);
    failures++;
  }
}

static void check_str(const char *name, poly_t *p, const char *want) {
  char *s = poly_to_string(p);
  int ok = s && strcmp(s, want) == 0;
  if (!ok) {
    printf("FAIL %s: got '%s' want '%s'\n", name, s ? s : "(null)", want);
    failures++;
  } else {
    printf("PASS %s\n", name);
  }
  free(s);
}

int main(void) {
  poly_t *x = poly_var("x");
  poly_t *y = poly_var("y");
  poly_t *zero = poly_const(0);
  poly_t *one = poly_const(1);
  poly_t *two = poly_const(2);
  poly_t *t, *u, *v;

  /* x - x = 0 (the subSelf rule, as polynomials). */
  t = poly_sub(x, x);
  check("x - x = 0", poly_is_zero(t));
  check_str("x - x prints 0", t, "0");
  poly_free(t);

  /* x * 0 = 0 (the mulZero rule). */
  t = poly_mul(x, zero);
  check("x * 0 = 0", poly_is_zero(t));
  poly_free(t);

  /* x * 1 = x (the mulOne rule). */
  t = poly_mul(x, one);
  check("x * 1 = x", poly_equal(t, x));
  poly_free(t);

  /* x + 0 = x (the addZero rule). */
  t = poly_add(x, zero);
  check("x + 0 = x", poly_equal(t, x));
  poly_free(t);

  /* x^0 = 1 and x^1 = x (the pow rules). */
  t = poly_pow(x, 0);
  check("x^0 = 1", poly_equal(t, one));
  poly_free(t);
  t = poly_pow(x, 1);
  check("x^1 = x", poly_equal(t, x));
  poly_free(t);

  /* (x + 1)^2 = x^2 + 2*x + 1. */
  u = poly_add(x, one);
  t = poly_pow(u, 2);
  check_str("(x+1)^2", t, "x^2 + 2*x + 1");
  poly_free(u);
  poly_free(t);

  /* (x^2 - 1) = (x - 1)(x + 1). */
  u = poly_pow(x, 2);
  v = poly_sub(u, one);
  poly_free(u);
  u = poly_sub(x, one);
  t = poly_add(x, one);
  {
    poly_t *prod = poly_mul(u, t);
    check("(x-1)(x+1) = x^2 - 1", poly_equal(prod, v));
    check_str("x^2 - 1", v, "x^2 - 1");
    poly_free(prod);
  }
  poly_free(u);
  poly_free(t);
  poly_free(v);

  /* 2*x + 3*x = 5*x (like terms combine). */
  u = poly_mul(two, x);
  v = poly_mul(poly_const(3), x);
  t = poly_add(u, v);
  check_str("2x + 3x", t, "5*x");
  poly_free(u);
  poly_free(v);
  poly_free(t);

  /* x*y + y*x = 2*x*y (multivariate like terms combine). */
  u = poly_mul(x, y);
  v = poly_mul(y, x);
  t = poly_add(u, v);
  check_str("xy + yx", t, "2*x*y");
  poly_free(u);
  poly_free(v);
  poly_free(t);

  /* Constant folding: 2 * 3 = 6. */
  t = poly_mul(two, poly_const(3));
  {
    int64_t c = -1;
    check("2 * 3 is const 6", poly_is_const(t, &c) && c == 6);
  }
  poly_free(t);

  poly_free(x);
  poly_free(y);
  poly_free(zero);
  poly_free(one);
  poly_free(two);

  if (failures == 0) {
    printf("POLY TEST PASS\n");
    return 0;
  }
  printf("POLY TEST FAIL: %d failures\n", failures);
  return 1;
}
