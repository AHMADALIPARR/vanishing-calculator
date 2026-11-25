<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
# Vanishing Calculator

Self-modifying calculator in five kernels, plus the Org Babel Lean 4
bridge. Run once visible: it prints Fibonacci(10), Primes(30),
Factorial(5), then hides its engine as a base64 payload. Run again
hidden: it restores the engine. Run again: it calculates and hides again.

## Files

- vanishing_calculator.ps1 — PowerShell 7.4.6
- vanishing_calculator.rkt — Racket 8.15
- vanishing_calculator.lisp — Common Lisp, SBCL 2.2.9
- vanishing_calculator.p — Poplog / Pop-11, staged, not run here
- vanishing_calculator.c — C core, arena Lisp with vanish!, fib(10) then vanish
- ob-lean4.el — Org Babel support for Lean 4, runs blocks through lean --json
- ob-lean4-test.el — end-to-end test for ob-lean4.el
- verify.py — round-trip verifier, run 1 / 2 / 3 per runnable kernel,
  plus C core and ob-lean4.el checks
- TEST_LOG.txt — full output of the last verify.py run, 0 failures

## Run

- pwsh vanishing_calculator.ps1
- racket vanishing_calculator.rkt
- sbcl --script vanishing_calculator.lisp
- pop11 vanishing_calculator.p
- gcc -std=gnu11 -O2 -Wall -Wextra -Werror vanishing_calculator.c -o vanishing_calculator_c && ./vanishing_calculator_c
- emacs --batch -l ob-lean4-test.el (needs lean on PATH)

Run each on a copy first. Every run rewrites its own file.

## Test vectors

- Fibonacci(10): [0, 1, 1, 2, 3, 5, 8, 13, 21, 34], Racket: (0 1 1 2 3 5 8 13 21 34)
- Primes(30): [2, 3, 5, 7, 11, 13, 17, 19, 23, 29], Racket: (2 3 5 7 11 13 17 19 23 29)
- Factorial(5): 120
- C core: first call prints 34 21 13 8 5 3 2 1 1 0, second call prints
  nothing (get-fib vanished after the first run)

## Status

See STATUS.md. Poplog has no runtime on this VM, so it was not run here.
Nothing in this directory has been pushed. Push to AHMADALIPARR/pirtm-hcalc
still needs a fresh token naming that repo.
