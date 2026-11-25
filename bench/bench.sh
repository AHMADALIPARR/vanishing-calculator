#!/bin/bash
# Benchmark harness - own file, outside both repos. No repo code touched. No Python.
# Usage: bench.sh <vanish-root> <out-tsv>
set -u
ROOT="$1"; OUT="$2"; WORK="$ROOT/tests/.pipeline-work"
# Absolutize OUT before cd, or the redirect lands in the wrong directory.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT";; esac
case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT";; esac
WORK="$ROOT/tests/.pipeline-work"
mkdir -p "$WORK" "$(dirname "$OUT")"
: > "$OUT"
run_timed() { # label, command...
  local label="$1"; shift
  local s e ms
  s=$(date +%s%N)
  "$@" > /tmp/bench-last.log 2>&1
  local rc=$?
  e=$(date +%s%N)
  ms=$(( (e - s) / 1000000 ))
  printf '%s\t%s\t%s\n' "$label" "$(awk -v m="$ms" 'BEGIN{printf "%.3f", m/1000}')" "exit=$rc $(head -c 120 /tmp/bench-last.log | tr '\n' ' ')" >> "$OUT"
  echo "$label: $(awk -v m="$ms" 'BEGIN{printf "%.3f", m/1000}')s exit=$rc"
  return $rc
}
cd "$ROOT" || exit 1
CFLAGS="-std=gnu11 -O2 -Wall -Wextra -Werror"
run_timed "C build vanish-elf" gcc $CFLAGS -I elf/abi -o "$WORK/vanish-elf" elf/writer/vanish-elf.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
run_timed "C build vanish-load" gcc $CFLAGS -I elf/abi -o "$WORK/vanish-load" elf/loader/vanish-load.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
run_timed "C build vanish-link" gcc $CFLAGS -I elf/abi -o "$WORK/vanish-link" elf/linker/vanish-link.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
run_timed "C build vanish-vm" gcc $CFLAGS -I elf/abi -I math -o "$WORK/vanish-vm" vm/vanish-vm.c math/poly.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
run_timed "C build ampl-check" gcc $CFLAGS -o "$WORK/ampl-check" ampl/check.c
run_timed "C build test-poly" gcc $CFLAGS -I math -o "$WORK/test-poly" math/test_poly.c math/poly.c
run_timed "Math poly test (13/13)" "$WORK/test-poly"
run_timed "AMPL exact check" "$WORK/ampl-check"
# ELF round-trip on ex1 if prog xml exists via scheme later; for now loader/vm on a synthetic check:
if [ -x "$WORK/vanish-elf" ] && [ -x "$WORK/vanish-load" ]; then
  echo "binaries present: $(ls -l "$WORK" | awk '{print $9, $5}')"
fi
echo "--- TSV ---"; cat "$OUT"
