import Vanish.Syntax

/-!
  Vanish.Semantics — Denotational semantics of VANISH-LISP over ℤ
-/

namespace Vanish

abbrev Env := String → Int

/-- Evaluate an `Expr` in an integer environment `ρ`. -/
def eval (ρ : Env) : Expr → Int
  | Expr.lit n     => n
  | Expr.var x     => ρ x
  | Expr.add a b   => eval ρ a + eval ρ b
  | Expr.sub a b   => eval ρ a - eval ρ b
  | Expr.neg a     => -(eval ρ a)
  | Expr.mul a b   => eval ρ a * eval ρ b
  | Expr.pow a n   => (eval ρ a) ^ n

/-- Satisfaction of a single constraint under `ρ`. -/
def satisfiesConstraint (ρ : Env) : Constraint → Prop
  | Constraint.eq a b  => eval ρ a = eval ρ b
  | Constraint.neq a b => eval ρ a ≠ eval ρ b

/-- Satisfaction of a constraint context `Γ`. -/
def satisfies (ρ : Env) (Γ : List Constraint) : Prop :=
  ∀ c ∈ Γ, satisfiesConstraint ρ c

/-- Semantic vanishing predicate: `Γ ⊨ e = 0`. -/
def SemanticallyVanishes (Γ : List Constraint) (e : Expr) : Prop :=
  ∀ ρ : Env, satisfies ρ Γ → eval ρ e = 0

end Vanish
