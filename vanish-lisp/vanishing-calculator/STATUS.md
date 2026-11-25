# Vanishing Calculator — status

Last verified: 2026-11-24, `python3 verify.py`, 66 checks, 0 failures.
Full log: TEST_LOG.txt. Runtimes measured here: pwsh 7.4.6, Racket 8.15,
SBCL 2.2.9, gcc 13.3.0, Lean 4.12.0 via elan, GNU Emacs 29.3.
Poplog: no pop11 runtime on this VM, file staged, not run.

## What was supplied, what was reconstructed

The pastes arrived truncated: PowerShell Main cut off after the STATE line,
Racket Main cut off after the banner, Common Lisp make-hidden cut off
mid-function, Poplog make_hidden cut off mid-function. Tails were
reconstructed from the same toggle pattern in the other kernels in the
same paste. Reconstructed parts are marked RECONSTRUCTED in each file.
No paste was presented as verbatim where it was reconstructed.

## Per-kernel results

- PowerShell: run 1 calculates (fib, primes, fact all as in README), hides,
  run 2 restores byte-identical, run 3 calculates again. All 12 checks pass.
- Racket: same round-trip, all 12 checks pass.
- Common Lisp: same round-trip, all 12 checks pass.
- Poplog: 9 file checks pass (functions, issubstring, markers, base64
  encode/decode, make_hidden/make_visible present) plus 3 Python-mirror
  checks of its arithmetic. Not run under pop11.
- C core (`vanishing_calculator.c`, added 2026-11-24): compiles clean
  with gcc 13.3.0, `-std=gnu11 -O2 -Wall -Wextra -Werror`, exit 0.
  First `(get-fib 10)` prints `34 21 13 8 5 3 2 1 1 0`, second prints
  nothing: `vanish!` zeroed the closure body in place. All 4 checks pass.
  Compiled with `-std=gnu11` because `strdup` needs it; the source is
  otherwise plain C11.
- ob-lean4.el (added 2026-11-24, second paste is the revised version):
  byte-compiles clean in Emacs 29.3; `lean --json` over a test file
  returns the `#eval`/`#check` messages as expected; end-to-end
  `org-babel-execute:lean4` returns `2`, `Nat : Type`, `42`, positions
  an error as `L1:17 error:`, stays silent on a definition-only block,
  replays a session block (`sessval + 1` gives 8), re-running a block
  stays silent (no duplicate definition), and `org-babel-lean4-edit`
  opens the block in a real `.lean` file with the generated regions
  and writes an edit back into the Org buffer. All 14 checks pass.
  The first paste arrived mid-commentary, so the file header is
  reconstructed and marked as such in the file; the second paste added
  the session-prelude fix and the language-server edit section, and
  `(require 'ob)` is retained because the file calls Org Babel
  functions. The load-path entry is the directory holding ob-lean4.el,
  and `ob-lean4-test.el` adds its own directory for that reason.

## Fixes found by execution, with the measurement

1. PowerShell payload line: pasted `HIDDEN_PAYLOAD="..."` with no `$` is
   executed as a command name on the hidden run and fails. Changed to
   `$HIDDEN_PAYLOAD="..."`, with the Make-Visible regex updated to match.
2. Whole-file state check: Main matched "# STATE: VISIBLE" over the whole
   file, which always hits because the toggle code itself contains that
   string, so run 2 went down the visible branch with no engine and failed.
   Fixed in all four kernels to match the header line only (PowerShell
   `(?m)^`, Racket exact-line member, Lisp newline-prefixed search, Poplog
   newline-prefixed issubstring).
3. Global state replace: PowerShell `-replace` and Racket `string-replace`
   are global and rewrote the state strings inside Make-Hidden/Make-Visible
   themselves, breaking the round-trip. Fixed to header-line-only,
   first-match replacement.
4. Racket whole-module expansion: a direct `(calc-fibonacci ...)` call in
   main fails to compile once the engine is hidden. Main now calls the
   engine through `eval` in the module namespace (namespace-anchor probe
   verified: `(eval '(calc-fibonacci 10) ns)` returns the value).
5. Racket `string-contains?`: in Racket 8.15 it returns #t/#f, not an index,
   so the pasted make-hidden/make-visible could not locate the markers.
   Added a `str-index` helper via `regexp-match-positions`.
6. Common Lisp factorial: the pasted LOOP form measured on SBCL 2.2.9 as
   NIL for 0/1 and 60 for 5. Replaced with the accumulator loop the other
   kernels use; now 1 for 0, 120 for 5. Original form:
   `(loop for i from 2 to n for acc = 1 then (* acc i) finally (return acc))`
7. Common Lisp loader: SBCL --script keeps the file open and tries to read
   past `(main)` after it returns; the file was just rewritten under it,
   so the loader re-read at a stale offset and died with a READ error at
   EOF. Main now calls `(sb-ext:exit :code 0)` at once after rewriting.
8. Racket / Lisp payload removal: a whole-file payload regex / search in
   make-visible would match the payload pattern string inside make-hidden
   itself. Removed: the payload sits between the markers, so
   before+decoded+after already excludes it.
9. Poplog calc_primes: the pasted version mixed three sieve attempts and a
   maplist/applist join that does not produce "[2, 3, ...]". Replaced with
   one flags-vector sieve, same name and return format.
10. Poplog base64_encode: `alphabet((n >> 18) && 63 + 1)` parses as
    `(n>>18) && (63+1)`. Parentheses corrected to
    `alphabet(((n >> 18) && 63) + 1)`, and likewise for the other nibbles.

## Not done

- No push. Destination is AHMADALIPARR/pirtm-hcalc; it needs a fresh token
  naming that repo and the user's word to push.
- Poplog not run here. If a pop11 runtime is supplied, run verify.py's
  Poplog section against it before claiming it runs.
