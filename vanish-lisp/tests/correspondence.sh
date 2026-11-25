#!/bin/bash
# tests/correspondence.sh -- Run the exhaustive correspondence corpus
# check (tests/correspondence.exs) and report its verdict.
#
# The corpus is every well-formed expression of depth <= 2 over
# variables {x, y} and literals {0, 1} with exponents {0, 1, 2}, plus
# hand-picked edge cases. For each expression it runs the real XSLT
# lowering on the real Scheme-emitted XML and compares against the
# Lean compiler and the formalized lowering from one batched Lean run.
# This is differential testing, not the proof: the universal theorem
# is Vanish.correspondence in lean/Vanish/Correspondence.lean.
# Exits non-zero on any mismatch.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.elan/bin:$PATH"
export ELIXIR_ERL_OPTIONS="+fnu"
exec elixir "$ROOT/tests/correspondence.exs" "$@"
