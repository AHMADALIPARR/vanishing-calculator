# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

Feature: Formally verified vanishing calculus

  Scenario: Polynomial vanishing under constraints
    Given polynomial "x^4 - 1"
    And constraint "x^2 - 1 = 0"
    When POP-11 reduces the expression
    And AMPL searches for a counterexample
    And Lean validates the algebraic certificate
    Then the polynomial shall be classified as vanishing
    And the symbolic residual shall equal zero
    And the ELF artifact shall contain a verified certificate

  # NOTE (2026-11-24): the steps of the second and third scenarios were
  # not quoted in the supplied text; they are written here in the same
  # style, from the scenario titles, and each step is implemented by
  # gherkin/runner.rkt against a real pipeline stage.
  Scenario: Unresolved mathematical obligation
    Given polynomial "x - y"
    When POP-11 reduces the expression
    And Lean validates the algebraic certificate
    Then the polynomial shall not be classified as vanishing
    And the obligation shall remain unresolved

  Scenario: Binary round-trip preservation
    Given polynomial "x - x"
    When the pipeline seals the ELF artifact
    And the loader reads the ELF artifact back
    Then the loader shall reconstruct the identical AST
    And the section hashes shall match

  # NOTE (2026-11-24, Phase 1): the correspondence check below is the
  # per-expression differential check (tests/correspondence.exs --one),
  # backed by the real XSLT lowering, the real Scheme emitter, and a
  # batched Lean run; the universal theorem is Vanish.correspondence.
  Scenario: Compiler correspondence and stack safety
    Given polynomial "x - x"
    When the correspondence check runs on the expression
    And the Lean correspondence theorems are checked
    Then the XSLT lowering shall equal the Lean compile
    And the lowering shall be deterministic
    And the compiled program shall never underflow the stack
    And the stack depth shall be bounded by the expression size
    And the XML shall decode to the original expression
