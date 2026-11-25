#!/bin/bash
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

# tests/run_pipeline.sh -- End-to-end pipeline test with the admission gate.
#
# Runs the full chain on the four pipeline examples and then applies the
# admission gate Admit(M) = G_grammar AND G_semantics AND G_proof AND
# G_behavior AND G_binary, where each G is a real check:
#   G_grammar   the vanish XML validates against the SGML DTD structure
#   G_semantics the OpenMath round-trip preserves the expression
#   G_proof     lake build passes and the Lean certificate check passes
#   G_behavior  all Gherkin scenarios pass
#   G_binary    the ELF loader round-trip reconstructs the identical AST
#               and the section hashes match
# Prints ADMIT or DENY and exits non-zero on DENY.
#
# The chain per example: Scheme --openmath -> OpenMath (canonical IR)
# -> openmath-to-vanish.xsl -> vanish XML -> canonicalize -> lower
# -> certificates -> ELF writer -> loader -> VM. The issued certificate
# XML for each example is copied to certificates/ at the repo root.
#
# Expected VM outcomes: ex1 and ex4 pass ASSERT_ZERO (exit 0). ex2
# fails ASSERT_ZERO with residual x^4 - 1 (its vanishing is conditional
# on x^2 - 1 = 0, via the ideal certificate) and ex3 fails with
# residual x - y; both failures are the expected outcome and are
# checked as such.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/tests/.pipeline-work"
RACKET="$HOME/workspace/.tools/racket/bin/racket"
export PATH="$HOME/workspace/.tools/racket/bin:$HOME/.elan/bin:$PATH"
export ELIXIR_ERL_OPTIONS="+fnu"

# Zero-Python gate: fail closed if any Python file or invocation enters the tree.
# The word is split as p''ython so the check does not match its own line.
if find "$ROOT" \( -name .git -o -name .lake -o -name .pipeline-work \) -prune -o -name '*.py' -print | grep -q .; then echo "FAIL: Python file present" >&2; exit 1; fi
if grep -rnE '(^|[^A-Za-z0-9_])p''ython3?([^A-Za-z0-9_]|$)' --include='*.sh' --include='*.yml' --include='*.exs' --include='*.rkt' --include='Makefile' "$ROOT" --exclude-dir=.git --exclude-dir=.lake --exclude-dir=.pipeline-work | grep -q .; then echo "FAIL: Python invocation in runnable file" >&2; exit 1; fi

FAILURES=0
say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
check() { # check DESCRIPTION COMMAND...
  local desc="$1"; shift
  if "$@" >"$WORK/last.log" 2>&1; then
    note "ok: $desc"
  else
    fail "$desc (see $WORK/last.log)"
    sed 's/^/    /' "$WORK/last.log" | head -10
  fi
}

mkdir -p "$WORK" "$ROOT/certificates"
cd "$ROOT" || exit 1

# --- Build the C stages -------------------------------------------
say "== build C stages"
CFLAGS="-std=gnu11 -O2 -Wall -Wextra -Werror"
gcc $CFLAGS -I elf/abi -o "$WORK/vanish-elf" elf/writer/vanish-elf.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c || fail "build vanish-elf"
gcc $CFLAGS -I elf/abi -o "$WORK/vanish-load" elf/loader/vanish-load.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c || fail "build vanish-load"
gcc $CFLAGS -I elf/abi -o "$WORK/vanish-link" elf/linker/vanish-link.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c || fail "build vanish-link"
gcc $CFLAGS -I elf/abi -I math -o "$WORK/vanish-vm" vm/vanish-vm.c math/poly.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c || fail "build vanish-vm"
gcc $CFLAGS -o "$WORK/ampl-check" ampl/check.c || fail "build ampl-check"
gcc $CFLAGS -I math -o "$WORK/test-poly" math/test_poly.c math/poly.c || fail "build test-poly"
note "C stages built"

# --- Math test and Scheme selftest --------------------------------
say "== math and Scheme selftest"
check "math poly test (13/13)" "$WORK/test-poly"
check "Scheme selftest (17/17)" "$RACKET" scheme/vanish.rkt --selftest

# --- Per-example chain --------------------------------------------
say "== per-example chain"
for ex in ex1 ex2 ex3 ex4; do
  say "-- $ex: $(cat "tests/examples/$ex.sexp")"
  # Scheme emits OpenMath as the canonical IR.
  "$RACKET" scheme/vanish.rkt --openmath "tests/examples/$ex.sexp" "$WORK/$ex.om" >"$WORK/last.log" 2>&1 || { fail "$ex scheme --openmath"; continue; }
  # OpenMath to vanish XML; it must equal the direct Scheme XML output.
  elixir tests/xslt.exs openmath/openmath-to-vanish.xsl "$WORK/$ex.om" > "$WORK/$ex.xml" 2>"$WORK/last.log" || { fail "$ex openmath-to-vanish"; continue; }
  "$RACKET" scheme/vanish.rkt --xml "tests/examples/$ex.sexp" "$WORK/$ex.direct.xml" >"$WORK/last.log" 2>&1 || { fail "$ex scheme --xml"; continue; }
  if cmp -s "$WORK/$ex.xml" "$WORK/$ex.direct.xml"; then note "ok: $ex OpenMath -> vanish XML equals Scheme XML"; else fail "$ex OpenMath -> vanish XML differs from Scheme XML"; fi
  # Canonicalize, lower.
  elixir tests/xslt.exs xslt/canonicalize.xsl "$WORK/$ex.xml" > "$WORK/$ex.canon.xml" 2>"$WORK/last.log" || { fail "$ex canonicalize"; continue; }
  elixir tests/xslt.exs xslt/lower.xsl "$WORK/$ex.canon.xml" > "$WORK/$ex.prog.xml" 2>"$WORK/last.log" || { fail "$ex lower"; continue; }
  # Certificate. The witness is per example: ex2 carries the ideal
  # certificate (x^4 - 1 = (x^2 + 1)(x^2 - 1)); ex1 and ex4 vanish by
  # a rewrite rule, so their residual is already 0 with no ideal
  # needed; ex3 is unresolved, so its witness records the residual.
  case "$ex" in
    ex1) GEN="" QUOT="" REM="0" ;;
    ex2) GEN="x^2 - 1" QUOT="x^2 + 1" REM="0" ;;
    ex3) GEN="" QUOT="" REM="x - y" ;;
    ex4) GEN="" QUOT="" REM="0" ;;
  esac
  ASTH="$(sha256sum "$WORK/$ex.canon.xml" | cut -d' ' -f1)"
  PROGH="$(sha256sum "$WORK/$ex.prog.xml" | cut -d' ' -f1)"
  elixir tests/xslt.exs xslt/certificates.xsl "$WORK/$ex.prog.xml" \
    "ast-uri=file://$WORK/$ex.canon.xml" "ast-hash=$ASTH" "program-hash=$PROGH" \
    "generators=$GEN" "quotients=$QUOT" "remainder=$REM" \
    > "$WORK/$ex.cert.xml" 2>"$WORK/last.log" || { fail "$ex certificates"; continue; }
  cp "$WORK/$ex.cert.xml" "$ROOT/certificates/$ex.cert.xml"
  note "ok: $ex certificate issued to certificates/$ex.cert.xml"
  # ELF writer, loader, VM.
  "$WORK/vanish-elf" -o "$WORK/$ex.elf" "$WORK/$ex.prog.xml" "$WORK/$ex.canon.xml" "$WORK/$ex.cert.xml" >"$WORK/last.log" 2>&1 || { fail "$ex ELF writer"; continue; }
  note "ok: $ex ELF sealed"
  check "$ex loader verifies hashes" "$WORK/vanish-load" "$WORK/$ex.elf"
  "$WORK/vanish-vm" "$WORK/$ex.elf" >"$WORK/last.log" 2>&1
  vm_code=$?
  case "$ex" in
    ex1|ex4)
      if [ "$vm_code" -eq 0 ]; then note "ok: $ex VM passes ASSERT_ZERO (exit 0)"; else fail "$ex VM should pass ASSERT_ZERO"; sed 's/^/    /' "$WORK/last.log" | head -5; fi ;;
    ex2)
      if [ "$vm_code" -ne 0 ] && grep -q "ASSERT_ZERO FAIL: residual x^4 - 1" "$WORK/last.log"; then note "ok: $ex VM fails ASSERT_ZERO as expected (conditional vanishing)"; else fail "$ex VM should fail ASSERT_ZERO with residual x^4 - 1"; fi ;;
    ex3)
      if [ "$vm_code" -ne 0 ] && grep -q "ASSERT_ZERO FAIL: residual x - y" "$WORK/last.log"; then note "ok: $ex VM fails ASSERT_ZERO as expected (non-vanishing)"; else fail "$ex VM should fail ASSERT_ZERO with residual x - y"; fi ;;
  esac
done

# --- Linker: ex1 + ex4 --------------------------------------------
say "== linker"
"$WORK/vanish-link" -o "$WORK/linked.elf" "$WORK/ex1.elf" "$WORK/ex4.elf" >"$WORK/last.log" 2>&1 || fail "link ex1 + ex4"
check "linked ELF loads and verifies" "$WORK/vanish-load" "$WORK/linked.elf"
"$WORK/vanish-vm" "$WORK/linked.elf" >"$WORK/last.log" 2>&1
if [ $? -eq 0 ]; then note "ok: linked VM passes ASSERT_ZERO (exit 0)"; else fail "linked VM should pass ASSERT_ZERO"; fi

# --- AMPL exact check ---------------------------------------------
say "== AMPL exact check"
check "AMPL check (max violation 0 over {-1, 1})" "$WORK/ampl-check"

# --- Lean: build oleans first --------------------------------------
# The cross-check, the correspondence corpus, and the Gherkin
# correspondence step all run `lake env lean` against the Vanish
# modules. On a fresh checkout there are no oleans until `lake build`
# runs; G_proof builds them too, but it runs after these steps, so a
# fresh checkout failed here (CI run 45520800279). Build first.
say "== Lean build"
lake build >"$WORK/last.log" 2>&1 || fail "lake build"

# --- Lean: cross-check XSLT lowering vs Lean compile -------------
say "== Lean cross-check"
lake env lean tests/lean-cross-check.lean > "$WORK/lean-programs.txt" 2>"$WORK/last.log" || fail "lean-cross-check"
for ex in ex1 ex2 ex3 ex4; do
  elixir tests/program_to_text.exs "$WORK/$ex.prog.xml" > "$WORK/$ex.txt" 2>"$WORK/last.log" || fail "$ex program_to_text"
done
if cmp -s <(cat "$WORK/ex1.txt" "$WORK/ex2.txt" "$WORK/ex3.txt" "$WORK/ex4.txt") "$WORK/lean-programs.txt"; then
  note "ok: XSLT lowering == Lean compile on all four examples"
else
  fail "XSLT lowering differs from Lean compile"
  diff <(cat "$WORK/ex1.txt" "$WORK/ex2.txt" "$WORK/ex3.txt" "$WORK/ex4.txt") "$WORK/lean-programs.txt" | head -10
fi

# --- Correspondence corpus check ------------------------------------
# Phase 1: every well-formed expression of depth <= 2 over {x, y} and
# {0, 1} with exponents {0, 1, 2}, plus edge cases, run through the
# real XSLT lowering on the real Scheme-emitted XML and compared
# against the Lean compiler and the formalized lowering. This is
# differential testing, not the proof: the universal theorem is
# Vanish.correspondence. A failure here blocks ADMIT via FAILURES.
say "== correspondence corpus check"
check "correspondence corpus (depth <= 2 + edge cases)" bash tests/correspondence.sh

# --- Admission gate ------------------------------------------------
say "== admission gate Admit(M) = G_grammar AND G_semantics AND G_proof AND G_behavior AND G_binary"

G_GRAMMAR=1
elixir tests/check_dtd.exs sgml/vanish.dtd "$WORK/ex1.xml" "$WORK/ex2.xml" "$WORK/ex3.xml" "$WORK/ex4.xml" >"$WORK/last.log" 2>&1 || G_GRAMMAR=0
[ "$G_GRAMMAR" -eq 1 ] && note "ok: G_grammar: all four vanish XMLs validate against the DTD structure" || fail "G_grammar"

G_SEMANTICS=1
for ex in ex1 ex2 ex3 ex4; do
  elixir tests/xslt.exs openmath/vanish-to-openmath.xsl "$WORK/$ex.xml" > "$WORK/$ex.rt.om" 2>"$WORK/last.log" || { G_SEMANTICS=0; break; }
  elixir tests/xslt.exs openmath/openmath-to-vanish.xsl "$WORK/$ex.rt.om" > "$WORK/$ex.rt.xml" 2>"$WORK/last.log" || { G_SEMANTICS=0; break; }
  # Vanish XML -> OpenMath -> vanish XML is the identity on the expression.
  cmp -s "$WORK/$ex.rt.xml" "$WORK/$ex.xml" || { G_SEMANTICS=0; break; }
  # The OpenMath the XSLT emits is either identical to the Scheme
  # OpenMath (the expression carries a (vanish ...) wrapper) or
  # vanishes() of it (a bare expression; the <vanish> root is the
  # vanishing claim). tests/check_om.exs checks both forms.
  elixir tests/check_om.exs "$WORK/$ex.rt.om" "$WORK/$ex.om" >"$WORK/last.log" 2>&1 || { G_SEMANTICS=0; break; }
done
[ "$G_SEMANTICS" -eq 1 ] && note "ok: G_semantics: OpenMath round-trip preserves every expression" || fail "G_semantics"

G_PROOF=1
lake build >"$WORK/last.log" 2>&1 || G_PROOF=0
lake env lean tests/certificates/CertificateTests.lean >>"$WORK/last.log" 2>&1 || G_PROOF=0
[ "$G_PROOF" -eq 1 ] && note "ok: G_proof: lake build passes and the Lean certificate check passes" || fail "G_proof"

G_BEHAVIOR=1
"$RACKET" gherkin/runner.rkt --root "$ROOT" --work "$WORK" gherkin/vanishing.feature >"$WORK/gherkin.log" 2>&1 || G_BEHAVIOR=0
if [ "$G_BEHAVIOR" -eq 1 ]; then note "ok: G_behavior: all Gherkin scenarios pass"; else fail "G_behavior"; sed 's/^/    /' "$WORK/gherkin.log" | head -20; fi

G_BINARY=1
for ex in ex1 ex2 ex3 ex4; do
  "$WORK/vanish-load" "$WORK/$ex.elf" --dump >"$WORK/$ex.dump" 2>"$WORK/last.log" || { G_BINARY=0; break; }
  elixir tests/check_dump.exs "$WORK/$ex.dump" "$WORK/$ex.canon.xml" >"$WORK/last.log" 2>&1 || { G_BINARY=0; break; }
done
[ "$G_BINARY" -eq 1 ] && note "ok: G_binary: loader round-trip reconstructs the identical AST and the hashes match" || fail "G_binary"

# --- Verdict -------------------------------------------------------
say "== verdict"
if [ "$FAILURES" -eq 0 ] && [ "$G_GRAMMAR" -eq 1 ] && [ "$G_SEMANTICS" -eq 1 ] && [ "$G_PROOF" -eq 1 ] && [ "$G_BEHAVIOR" -eq 1 ] && [ "$G_BINARY" -eq 1 ]; then
  say "ADMIT"
  exit 0
else
  say "DENY (failures: $FAILURES)"
  exit 1
fi
