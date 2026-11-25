import Vanish.Soundness

/-!
  Vanish.Termination — Well-founded termination measure for symbolic reduction
-/

namespace Vanish

/-- Structural AST size measure `μ(e)`. -/
def measure : Expr → Nat
  | Expr.lit _   => 1
  | Expr.var _   => 1
  | Expr.neg a   => 1 + measure a
  | Expr.add a b => 1 + measure a + measure b
  | Expr.sub a b => 1 + measure a + measure b
  | Expr.mul a b => 1 + measure a + measure b
  | Expr.pow a _ => 2 + measure a

theorem measure_pos (e : Expr) : 0 < measure e := by
  cases e <;> simp [measure] <;> omega

/-- Every permitted reduction step strictly decreases `measure`. -/
theorem termination_step {e e' : Expr} (h : Step e e') :
    measure e' < measure e := by
  cases h <;> simp [measure] <;> try omega
  case subSelf x =>
    have hx := measure_pos x
    omega

end Vanish
