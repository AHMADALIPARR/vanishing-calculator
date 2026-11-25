#!/bin/bash
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

# bench/ci.sh — local runner for .github/workflows/ci.yml.
# Runs the same jobs in the same order, on this host, and writes bench/ci.log.
# Exit 0 = all jobs green. The pipeline job runs the shipped
# tests/run_pipeline.sh and expects ADMIT.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/bench/ci.log"
export PATH="$HOME/workspace/.tools/racket/bin:$HOME/.elan/toolchains/leanprover--lean4---v4.12.0/bin:$PATH"
export ELIXIR_ERL_OPTIONS="+fnu"

# Zero-Python gate: fail closed if any Python file or invocation enters the tree.
# The word is split as p''ython so the check does not match its own line.
if find "$ROOT" \( -name .git -o -name .lake -o -name .pipeline-work \) -prune -o -name '*.py' -print | grep -q .; then echo "FAIL: Python file present" >&2; exit 1; fi
if grep -rnE '(^|[^A-Za-z0-9_])p''ython3?([^A-Za-z0-9_]|$)' --include='*.sh' --include='*.yml' --include='*.exs' --include='*.rkt' --include='Makefile' "$ROOT" --exclude-dir=.git --exclude-dir=.lake --exclude-dir=.pipeline-work | grep -q .; then echo "FAIL: Python invocation in runnable file" >&2; exit 1; fi
mkdir -p "$HOME/workspace/.tools/racket/bin"
ln -sf "$(readlink -f "$(command -v racket)")" "$HOME/workspace/.tools/racket/bin/racket" 2>/dev/null || true
exec > >(tee "$LOG") 2>&1
FAIL=0
job() { # job NAME -- runs the rest of the args as a command
  local name="$1"; shift
  echo "===== CI job: $name ====="
  if "$@"; then echo "PASS: $name"; else echo "FAIL: $name"; FAIL=1; fi
}
job_verify() { (cd "$ROOT/vanish-lisp" && ./verify.sh); }
job_cbuilds() { bash "$ROOT/bench/bench.sh" "$ROOT/vanish-lisp" "$ROOT/bench/bench-c.tsv"; }
job_calculators() {
  rm -rf /tmp/calc-ci && mkdir -p /tmp/calc-ci
  cp "$ROOT/vanish-lisp/vanishing-calculator/vanishing_calculator.lisp" \
     "$ROOT/vanish-lisp/vanishing-calculator/vanishing_calculator.rkt" \
     "$ROOT/vanish-lisp/vanishing-calculator/vanishing_calculator.c" /tmp/calc-ci/
  sbcl --script /tmp/calc-ci/vanishing_calculator.lisp || return 1
  racket /tmp/calc-ci/vanishing_calculator.rkt || return 1
  gcc -O2 -o /tmp/calc-ci/vcalc /tmp/calc-ci/vanishing_calculator.c || return 1
  /tmp/calc-ci/vcalc || return 1
  sha256sum "$ROOT/vanishing_calculator.lisp" | grep -q '^d8ed5d66' || return 1
}
job_pipeline() {
  (cd "$ROOT/vanish-lisp" && bash tests/run_pipeline.sh > "$ROOT/bench/pipeline-ci.log" 2>&1)
}
job verify job_verify
job c-builds job_cbuilds
job calculators job_calculators
job pipeline job_pipeline
echo "===== CI summary ====="
if [ "$FAIL" -eq 0 ]; then echo "CI GREEN"; else echo "CI RED"; fi
exit "$FAIL"
