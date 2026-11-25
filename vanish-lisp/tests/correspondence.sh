#!/bin/bash
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

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
