# VANISH-LISP Cross-Language IR & Verification Contract

## 1. Overview

VANISH-LISP separates **symbolic discovery** from **formal verification** across three layers:

1. **Emacs Lisp (`elisp/`)** — Frontend reader, macro expansion, REPL, and S-expression AST.
2. **POP-11 (`pop11/`)** — Stack-based term rewriting, canonical polynomial normalization, multivariate division, and Gröbner basis certificate generation.
3. **Lean 4 (`lean/`)** — Macro calculus (`vanishes[e]`, `vanish_solve`) and kernel-checked verification of identities and ideal membership certificates.

All layers communicate via a restricted S-expression Intermediate Representation (IR) defined in `ir/grammar.ebnf`.

---

## 2. Serialization Mapping

| Concept | Emacs Lisp S-exp | POP-11 Tagged List | Lean 4 `Expr` AST |
| :--- | :--- | :--- | :--- |
| Integer literal | `7`, `-3` | `7`, `-3` | `Expr.lit 7`, `Expr.lit (-3)` |
| Variable | `x`, `y` | `x`, `y` | `Expr.var "x"`, `Expr.var "y"` |
| Addition | `(+ a b)` | `[add a b]` | `Expr.add a b` |
| Subtraction | `(- a b)` | `[sub a b]` | `Expr.sub a b` |
| Negation | `(- a)` | `[neg a]` | `Expr.neg a` |
| Multiplication | `(* a b)` | `[mul a b]` | `Expr.mul a b` |
| Power | `(pow x n)` | `[pow x n]` | `Expr.pow x n` |
| Constraint | `(= a b)` | `[eq a b]` | `Constraint.eq a b` |
| Under | `(under ((= x y)) e)` | `[under [[eq x y]] e]` | `(ctx, e)` |
| Derivative | `(derivative x e)` | `[deriv x e]` | `Expr.deriv "x" e` |
| Ideal | `(vanish-ideal (generators g1 ...) f)` | `[ideal [generators g1 ...] f]` | `IdealMembership [g1, ...] f` |

---

## 3. Tri-State Vanishing Semantics

The vanishing operator $\mathcal{V}_\Gamma(f)$ evaluates to:

- `1` ($\Gamma \vdash f = 0$): Proven to vanish under assumptions $\Gamma$.
- `0` ($\Gamma \vdash f \neq 0$): Proven non-vanishing (witnessed by a counterexample or non-zero normal form).
- `bot` ($\bot$): Undetermined / unresolved proof obligation.

---

## 4. Formal Verification Contracts

Every implementation of the reduction and certificate pipeline must uphold four invariants:

1. **Soundness**:
   $$\Gamma \vdash_{\text{POP-11}} e \twoheadrightarrow e' \implies \Gamma \models \llbracket e \rrbracket = \llbracket e' \rrbracket$$
   Every rewrite rule and polynomial reduction preserves denotational equality in the ring $\mathbb{Z}[x_1, \dots, x_n]$ (or $K[x_1, \dots, x_n]$).

2. **Termination**:
   There exists a well-founded measure $\mu : \text{Expr} \to \mathbb{N}$ such that every permitted rewrite step $e \to e'$ strictly decreases the measure: $\mu(e') < \mu(e)$.

3. **Idempotence**:
   $$\text{normalize}(\text{normalize}(e)) = \text{normalize}(e)$$
   Canonical normalization reaches a unique fixed point in one pass.

4. **Vanishing Certificate**:
   For ideal membership $f \in \langle g_1, \dots, g_m \rangle$, POP-11 produces explicit cofactor polynomials $q_1, \dots, q_m$ such that:
   $$f = \sum_{i=1}^{m} q_i g_i$$
   Lean 4 verifies this polynomial identity directly in the kernel without trusting Buchberger's algorithm or POP-11's search.
