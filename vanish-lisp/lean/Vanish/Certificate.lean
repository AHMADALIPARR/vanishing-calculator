import Vanish.Ideals

/-!
  Vanish.Certificate — Proof-carrying vanishing certificates from POP-11
-/

namespace Vanish

/-- Certificate produced by POP-11's Buchberger / division engine. -/
structure VanishingCert where
  target     : Expr
  generators : List Expr
  quotients  : List Expr
  remainder  : Expr
  deriving Repr

/-- A certificate is valid if `quotients` matches `generators` in length,
    the remainder is literally zero, and `target = ∑ q_i * g_i` for all `ρ`. -/
def ValidCert (c : VanishingCert) : Prop :=
  c.quotients.length = c.generators.length ∧
  c.remainder = Expr.lit 0 ∧
  ∀ ρ : Env, eval ρ c.target = sumProd ρ c.quotients c.generators

/-- Soundness of certificate verification: a valid certificate guarantees
    that `target` vanishes whenever all `generators` vanish. -/
theorem cert_soundness (c : VanishingCert) (h : ValidCert c) :
    ∀ ρ : Env, (∀ g ∈ c.generators, eval ρ g = 0) → eval ρ c.target = 0 := by
  intro ρ hgens
  rcases h with ⟨_, _, hcomb⟩
  rw [hcomb ρ]
  exact sumProd_vanishes ρ c.quotients c.generators hgens

end Vanish
