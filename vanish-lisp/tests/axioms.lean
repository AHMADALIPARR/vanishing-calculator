import Vanish.Correspondence

/-!
  axioms -- List the axioms the Phase 1 correspondence theorems depend
  on. Only the standard Lean axioms are allowed (propext,
  Classical.choice, Quot.sound). Any other axiom printed here is a
  failure of the Phase 1 constraint "zero unproven custom axioms".
  Run with: lake env lean tests/axioms.lean
-/

namespace VanishTests

open Vanish

#print axioms correspondence
#print axioms correspondence_wf
#print axioms decode_encode
#print axioms encode_decode
#print axioms lowerXml_encode
#print axioms lowerProgram_encode
#print axioms compile_deterministic
#print axioms lowerXml_deterministic
#print axioms boundedRun_agree
#print axioms stack_safe
#print axioms stack_bound
#print axioms semantic_preservation
#print axioms compile_correct

end VanishTests
