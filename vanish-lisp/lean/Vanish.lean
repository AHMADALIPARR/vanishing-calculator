import Vanish.Syntax
import Vanish.Semantics
import Vanish.Soundness
import Vanish.Termination
import Vanish.Ideals
import Vanish.Certificate
import Vanish.Pipeline
import Vanish.Correspondence

/-!
  Vanish — Top-level Lean 4 macro calculus and example vanishing proofs
-/

namespace VanishExamples

open Vanish

theorem vanish_sub (x : Int) :
    vanishes[x - x] := by
  exact Int.sub_self x

theorem vanish_constraint (x y : Int) (h : x = y) :
    vanishes[x - y] := by
  subst h
  exact Int.sub_self x

theorem polynomial_vanish (x : Int) (h : x ^ 2 - 1 = 0) :
    vanishes[x ^ 4 - 1] := by
  have hfact : x ^ 4 - 1 = (x ^ 2 + 1) * (x ^ 2 - 1) := by
    have h4 : x ^ 4 = x ^ 2 * x ^ 2 := by
      simp only [Int.pow_succ, Int.pow_zero, Int.one_mul, Int.mul_assoc]
    rw [h4]
    -- (a + 1) * (a - 1) = a * a - 1
    have := Int.mul_sub (x ^ 2 + 1) (x ^ 2) 1
    have := Int.add_mul (x ^ 2) 1 (x ^ 2)
    omega
  rw [hfact, h, Int.mul_zero]

end VanishExamples
