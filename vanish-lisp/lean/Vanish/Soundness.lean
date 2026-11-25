import Vanish.Semantics

/-!
  Vanish.Soundness — Soundness of POP-11 symbolic reduction rules
-/

namespace Vanish

/-- Single-step symbolic reduction relation mirroring `pop11/rewrite.p`. -/
inductive Step : Expr → Expr → Prop
  | subSelf (x : Expr) :
      Step (Expr.sub x x) (Expr.lit 0)
  | subZeroRight (x : Expr) :
      Step (Expr.sub x (Expr.lit 0)) x
  | negZero :
      Step (Expr.neg (Expr.lit 0)) (Expr.lit 0)
  | mulZeroLeft (x : Expr) :
      Step (Expr.mul (Expr.lit 0) x) (Expr.lit 0)
  | mulZeroRight (x : Expr) :
      Step (Expr.mul x (Expr.lit 0)) (Expr.lit 0)
  | mulOneLeft (x : Expr) :
      Step (Expr.mul (Expr.lit 1) x) x
  | mulOneRight (x : Expr) :
      Step (Expr.mul x (Expr.lit 1)) x
  | addZeroLeft (x : Expr) :
      Step (Expr.add (Expr.lit 0) x) x
  | addZeroRight (x : Expr) :
      Step (Expr.add x (Expr.lit 0)) x
  | powZero (x : Expr) :
      Step (Expr.pow x 0) (Expr.lit 1)
  | powOne (x : Expr) :
      Step (Expr.pow x 1) x

/-- Reflexive-transitive closure of `Step`. -/
inductive StepStar : Expr → Expr → Prop
  | refl (e : Expr) : StepStar e e
  | step {a b c : Expr} : Step a b → StepStar b c → StepStar a c

/-- Every permitted single-step reduction preserves `eval ρ`. -/
theorem soundness_step (ρ : Env) {e e' : Expr} (h : Step e e') :
    eval ρ e = eval ρ e' := by
  cases h with
  | subSelf x      => simp [eval, Int.sub_self]
  | subZeroRight x => simp [eval, Int.sub_zero]
  | negZero        => simp [eval]
  | mulZeroLeft x  => simp [eval, Int.zero_mul]
  | mulZeroRight x => simp [eval, Int.mul_zero]
  | mulOneLeft x   => simp [eval, Int.one_mul]
  | mulOneRight x  => simp [eval, Int.mul_one]
  | addZeroLeft x  => simp [eval, Int.zero_add]
  | addZeroRight x => simp [eval, Int.add_zero]
  | powZero x      => simp [eval, Int.pow_zero]
  | powOne x       => simp [eval, Int.pow_succ, Int.pow_zero]

/-- Multi-step reduction preserves `eval ρ`. -/
theorem soundness_star (ρ : Env) {e e' : Expr} (h : StepStar e e') :
    eval ρ e = eval ρ e' := by
  induction h with
  | refl _ => rfl
  | step h1 _ ih => exact Eq.trans (soundness_step ρ h1) ih

end Vanish
