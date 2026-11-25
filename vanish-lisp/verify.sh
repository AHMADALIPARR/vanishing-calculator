#!/bin/sh
# Verification for vanish-lisp. Runs lake build, the Elisp ERT suites,
# and the Elisp byte-compile check. Exits non-zero while any check fails.
# POP-11 cannot run on this box (no pop11 binary); it is scanned only.
# Usage: ./verify.sh
set -u
cd "$(dirname "$0")"
export PATH="$HOME/.elan/bin:$PATH"

# Zero-Python gate: fail closed if any Python file or invocation enters the tree.
# The word is split as p''ython so the check does not match its own line.
if find . \( -name .git -o -name .lake -o -name .pipeline-work \) -prune -o -name '*.py' -print | grep -q .; then echo "FAIL: Python file present" >&2; exit 1; fi
if grep -rnE '(^|[^A-Za-z0-9_])p''ython3?([^A-Za-z0-9_]|$)' --include='*.sh' --include='*.yml' --include='*.exs' --include='*.rkt' --include='Makefile' . --exclude-dir=.git --exclude-dir=.lake --exclude-dir=.pipeline-work | grep -q .; then echo "FAIL: Python invocation in runnable file" >&2; exit 1; fi
fail=0

echo "== lake build =="
if lake build; then
  echo "PASS lake build"
else
  echo "FAIL lake build"
  fail=1
fi

echo "== ERT reduction =="
if emacs --batch -L elisp -l tests/reduction/test-reduction.el -f ert-run-tests-batch-and-exit; then
  echo "PASS ert reduction"
else
  echo "FAIL ert reduction"
  fail=1
fi

echo "== ERT differential =="
if emacs --batch -L elisp -l tests/differential/test-differential.el -f ert-run-tests-batch-and-exit; then
  echo "PASS ert differential"
else
  echo "FAIL ert differential"
  fail=1
fi

echo "== byte-compile elisp =="
tmp=$(mktemp -d)
cp elisp/*.el "$tmp/"
ok=1
for f in "$tmp"/*.el; do
  if ! emacs --batch -L "$tmp" --eval "(byte-compile-file \"$f\")" >/dev/null 2>&1; then
    echo "FAIL byte-compile $f"
    ok=0
  fi
done
rm -rf "$tmp"
if [ "$ok" = 1 ]; then
  echo "PASS byte-compile elisp"
else
  fail=1
fi

echo "== pop11 presence =="
if command -v pop11 >/dev/null 2>&1; then
  echo "pop11 present"
else
  echo "SKIP pop11: no pop11 binary on this box (staged, not run)"
fi

if [ "$fail" = 0 ]; then
  echo "ALL CHECKS PASS"
else
  echo "FAILURES PRESENT"
fi
exit "$fail"
