/* ampl/check.c -- Exact certified equivalent of ampl/vanish.mod.
 *
 * The AMPL model is the specification for a real solver; AMPL is not
 * installed on this box, so this program is the exact equivalent that
 * runs here. The model asks for the maximum of |f(x)|^2 with
 * f(x) = x^4 - 1 over the feasible set S = {x in R : x^2 - 1 = 0}.
 * The feasible set is exactly x in {-1, 1}, so the maximum is
 * computed by exact enumeration in integer arithmetic, not by a
 * numerical search: f(-1) = 0 and f(1) = 0, so the maximum of
 * (x^4 - 1)^2 over S is 0, and that maximum of zero is the
 * certificate that f vanishes over the feasible set.
 *
 * A numerical solver result alone is not a proof; Lean remains the
 * final authority. This program is the exact arithmetic check the
 * model describes, and the Lean certificate (Vanish.Certificate,
 * cert_soundness) is what turns the vanishing into a theorem.
 */

#include <stdint.h>
#include <stdio.h>

static int64_t ipow(int64_t base, int exp) {
  int64_t result = 1;
  for (int i = 0; i < exp; i++) {
    result *= base;
  }
  return result;
}

int main(void) {
  static const int64_t feasible[] = {-1, 1};
  int64_t max_violation = -1;
  int64_t argmax = 0;
  for (size_t i = 0; i < sizeof(feasible) / sizeof(feasible[0]); i++) {
    int64_t x = feasible[i];
    /* The manifold constraint is exact: x^2 - 1 must be 0. */
    if (ipow(x, 2) - 1 != 0) {
      printf("AMPL check FAIL: x = %lld not on the manifold\n",
             (long long)x);
      return 1;
    }
    int64_t residual = ipow(x, 4) - 1;
    int64_t violation = residual * residual;
    printf("x = %lld: residual = %lld, violation = %lld\n",
           (long long)x, (long long)residual, (long long)violation);
    if (violation > max_violation) {
      max_violation = violation;
      argmax = x;
    }
  }
  printf("max violation over S = %lld (argmax x = %lld)\n",
         (long long)max_violation, (long long)argmax);
  if (max_violation != 0) {
    printf("AMPL check FAIL: nonzero maximum, counterexample at x = %lld\n",
           (long long)argmax);
    return 1;
  }
  printf("AMPL check PASS: certified global maximum 0, x^4 - 1 vanishes on S\n");
  return 0;
}
