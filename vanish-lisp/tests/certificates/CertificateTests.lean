import Vanish.Certificate

/-!
  CertificateTests — Verified vanishing certificates for VANISH-LISP
-/

namespace VanishTests

open Vanish

/-- Witness certificate for `x^4 - 1 = (x^2 + 1) * (x^2 - 1)`. -/
def quarticCert : VanishingCert :=
  { target     := Expr.sub (Expr.pow (Expr.var "x") 4) (Expr.lit 1)
    generators := [Expr.sub (Expr.pow (Expr.var "x") 2) (Expr.lit 1)]
    quotients  := [Expr.add (Expr.pow (Expr.var "x") 2) (Expr.lit 1)]
    remainder  := Expr.lit 0 }

theorem quarticCert_valid : ValidCert quarticCert := by
  refine ⟨rfl, rfl, ?_⟩
  intro ρ
  simp [quarticCert, eval, sumProd]
  have h4 : (ρ "x") ^ 4 = (ρ "x") ^ 2 * (ρ "x") ^ 2 := by
    simp only [Int.pow_succ, Int.pow_zero, Int.one_mul, Int.mul_assoc]
  rw [h4]
  have := Int.mul_sub ((ρ "x") ^ 2 + 1) ((ρ "x") ^ 2) 1
  have := Int.add_mul ((ρ "x") ^ 2) 1 ((ρ "x") ^ 2)
  omega

end VanishTests
