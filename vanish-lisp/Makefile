# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

EMACS  ?= emacs
POP11  ?= pop11
LAKE   ?= lake

.PHONY: all test test-elisp test-pop11 build-lean clean

all: build-lean

test-elisp:
	$(EMACS) --batch -L elisp -l tests/reduction/test-reduction.el -f ert-run-tests-batch-and-exit
	$(EMACS) --batch -L elisp -l tests/differential/test-differential.el -f ert-run-tests-batch-and-exit

test-pop11:
	$(POP11) pop11/vanish.p < tests/algebra/ideal-cases.p

build-lean:
	$(LAKE) build

test: test-elisp build-lean

clean:
	rm -rf .lake
