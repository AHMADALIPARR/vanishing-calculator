import Vanish.Semantics

/-!
  Vanish.Ideals — Polynomial ideal membership and vanishing theorems
-/

namespace Vanish

/-- Linear combination `∑ q_i * g_i` evaluated under environment `ρ`. -/
def sumProd (ρ : Env) : List Expr → List Expr → Int
  | q :: qs, g :: gs => eval ρ q * eval ρ g + sumProd ρ qs gs
  | _, _             => 0

/-- If every generator vanishes under `ρ`, then `∑ q_i * g_i` vanishes. -/
theorem sumProd_vanishes (ρ : Env) (qs gs : List Expr)
    (hgs : ∀ g ∈ gs, eval ρ g = 0) :
    sumProd ρ qs gs = 0 := by
  induction qs generalizing gs with
  | nil => simp [sumProd]
  | cons q qs ih =>
    cases gs with
    | nil => simp [sumProd]
    | cons g gs =>
      have hg : eval ρ g = 0 := hgs g (by simp)
      have hrest : ∀ g' ∈ gs, eval ρ g' = 0 := fun g' hg' => hgs g' (by simp [hg'])
      simp [sumProd, hg, ih gs hrest]

/-- Ideal membership witnessed by explicit cofactors `qs`. -/
def InIdeal (gens : List Expr) (f : Expr) : Prop :=
  ∃ qs : List Expr, qs.length = gens.length ∧ ∀ ρ : Env, eval ρ f = sumProd ρ qs gens

/-- Ideal membership implies vanishing on the zero locus of `gens`. -/
theorem vanish_of_ideal_member {gens : List Expr} {f : Expr}
    (hmem : InIdeal gens f) (ρ : Env) (hzero : ∀ g ∈ gens, eval ρ g = 0) :
    eval ρ f = 0 := by
  rcases hmem with ⟨qs, _, hcomb⟩
  rw [hcomb ρ]
  exact sumProd_vanishes ρ qs gens hzero

end Vanish
