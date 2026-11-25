/-!
  Vanish.Syntax — AST, tri-state verdict, and macro calculus for VANISH-LISP
-/

namespace Vanish

/-- Restricted total-ring expression AST matching the S-expression IR. -/
inductive Expr : Type
  | lit   : Int → Expr
  | var   : String → Expr
  | add   : Expr → Expr → Expr
  | sub   : Expr → Expr → Expr
  | neg   : Expr → Expr
  | mul   : Expr → Expr → Expr
  | pow   : Expr → Nat → Expr
  deriving Repr, DecidableEq, BEq

/-- Equational and disequational constraints for `under`. -/
inductive Constraint : Type
  | eq  : Expr → Expr → Constraint
  | neq : Expr → Expr → Constraint
  deriving Repr, DecidableEq

/-- Tri-state vanishing verdict: 1 (vanishes), 0 (non-zero), ⊥ (undetermined). -/
inductive Verdict : Type
  | vanishes     : Verdict
  | nonZero      : Verdict
  | undetermined : Verdict
  deriving Repr, DecidableEq

/-- Macro notation `vanishes[e]` expanding to `e = 0`. -/
syntax "vanishes[" term "]" : term

macro_rules
  | `(vanishes[$e]) => `($e = 0)

/-- Tactic macro attempting algebraic and arithmetic vanishing proofs. -/
macro "vanish_solve" : tactic =>
  `(tactic| first | simp_all | omega | decide | rfl)

end Vanish
