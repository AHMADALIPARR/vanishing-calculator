import Vanish.Pipeline

/-!
  Vanish.Correspondence -- Universal compiler correspondence.

  The Lean side of the XSLT-Lean lowering agreement. The supported
  AST is the complete `Expr` type (lean/Vanish/Syntax.lean). The
  enumeration below is complete: every constructor of `Expr` is
  covered, and every XSLT template in xslt/lower.xsl has exactly one
  formalized counterpart here. The supported set is the intersection
  the compiler actually handles.

  Enumeration (constructor -- XSLT template -- Lean compile -- DTD):
    lit n     -- integer  -- [pushInt n]                     -- integer
    var x     -- symbol   -- [pushSym x]                     -- symbol
    add a b   -- add      -- compile a ++ compile b ++ [add] -- add
    sub a b   -- sub      -- compile a ++ compile b ++ [sub] -- sub
    neg a     -- (none: encoded as sub-from-zero by the Scheme
               --  emitter and by compile, see `encode`)     -- (none)
    mul a b   -- mul      -- compile a ++ compile b ++ [mul] -- mul
    pow a n   -- pow      -- compile a ++ [pushInt n] ++ [pow] -- pow
  The root template (/) and the vanish|expr wrapper templates only
  recurse; they have no node of their own in `XmlTree`. The trailing
  sequence NORMALIZE, ASSERT_ZERO, VERIFY_PROOF, HALT is `lowerProgram`.

  Rule-by-rule correspondence table (XSLT template -> Lean function):
    /                    -> `lowerProgram` (lowerXml + trailing checks)
    vanish | expr        -> identity recursion (no wrapper node)
    symbol               -> `lowerXml (XmlTree.sym x)` = [pushSym x]
    integer              -> `lowerXml (XmlTree.int n)` = [pushInt n]
    sub                  -> `lowerXml (XmlTree.sub a b)`
    add                  -> `lowerXml (XmlTree.add a b)`
    mul                  -> `lowerXml (XmlTree.mul a b)`
    pow                  -> `lowerXml (XmlTree.pow a b)`

  On decoding and the canonical form. The sub-from-zero encoding
  identifies unary minus with subtraction from zero: `neg a` and
  `sub (lit 0) a` have the same XML tree, the same instruction stream
  and the same value. So a literal `decode (encode e) = e` is false
  for those two forms, and this file does not claim it. What holds is
  `decode (encode e) = canon e`, where `canon` eliminates unary minus
  to sub-from-zero, and `compile (canon e) = compile e` and
  `eval rho (canon e) = eval rho e` are proved below. The XML the
  emitter produces therefore decodes to the original AST up to this
  one identified encoding, and the identification is invisible to the
  compiler and to the semantics.

  TRUSTED BOUNDARY -- read this before citing the theorems below.
  The theorems in this file are about the FORMALIZED template
  semantics (`lowerXml`), the FORMALIZED XML tree (`XmlTree`), and the
  Lean compiler (`compile`). They do NOT execute xslt/lower.xsl and
  they do NOT parse XML. What connects the formalization to the real
  stylesheet is the executable corpus check (tests/correspondence.exs,
  wired into tests/run_pipeline.sh): it runs the actual stylesheet
  through the real XSLT engine on every well-formed expression of
  depth at most 2 over variables {x, y} and literals {0, 1} with
  exponents {0, 1, 2}, plus edge cases, and compares the instruction
  stream with the Lean compile. The remaining trusted implementation
  boundary is the XSLT 1.0 engine executing xslt/lower.xsl as written
  and the XML parser (libxml2) producing the tree the templates match.
  A universal proof about the XSLT engine's execution does not exist
  here and is not claimed: the Lean side carries the universal theorem
  over all well-formed expressions, and the XSLT side carries
  exhaustive-corpus agreement up to the stated bound.
  A second boundary: Lean `Int` is unbounded while the C ELF encoding
  carries int64 operands, so the binary correspondence holds for
  literals inside the int64 range; the corpus uses small literals.
-/

namespace Vanish

/-- The vanish XML element tree, mirroring sgml/vanish.dtd. There is
    no wrapper node: the `<vanish>` and `<expr>` elements only recurse,
    exactly as the vanish|expr template does. `pow` carries both
    children as trees; only an integer-literal exponent decodes. -/
inductive XmlTree : Type
  | int : Int → XmlTree
  | sym : String → XmlTree
  | add : XmlTree → XmlTree → XmlTree
  | sub : XmlTree → XmlTree → XmlTree
  | mul : XmlTree → XmlTree → XmlTree
  | pow : XmlTree → XmlTree → XmlTree
  deriving Repr, DecidableEq, BEq

/-- Encode an expression as its vanish XML tree. Unary minus has no
    element in the DTD, so it is encoded as subtraction from zero,
    the same encoding the Scheme emitter (scheme/vanish.rkt) and the
    Lean compiler use. -/
def encode : Expr → XmlTree
  | Expr.lit n => XmlTree.int n
  | Expr.var x => XmlTree.sym x
  | Expr.add a b => XmlTree.add (encode a) (encode b)
  | Expr.sub a b => XmlTree.sub (encode a) (encode b)
  | Expr.neg a => XmlTree.sub (XmlTree.int 0) (encode a)
  | Expr.mul a b => XmlTree.mul (encode a) (encode b)
  | Expr.pow a n => XmlTree.pow (encode a) (XmlTree.int (Int.ofNat n))

/-- Decode a vanish XML tree to an expression, structurally. A `pow`
    whose exponent is not a non-negative integer literal does not
    decode: it is outside the well-formed set. -/
def decode : XmlTree → Option Expr
  | XmlTree.int n => some (Expr.lit n)
  | XmlTree.sym x => some (Expr.var x)
  | XmlTree.add a b =>
    match decode a, decode b with
    | some a', some b' => some (Expr.add a' b')
    | _, _ => none
  | XmlTree.sub a b =>
    match decode a, decode b with
    | some a', some b' => some (Expr.sub a' b')
    | _, _ => none
  | XmlTree.mul a b =>
    match decode a, decode b with
    | some a', some b' => some (Expr.mul a' b')
    | _, _ => none
  | XmlTree.pow a b =>
    match decode a, decode b with
    | some a', some (Expr.lit n) =>
      if 0 ≤ n then some (Expr.pow a' n.toNat) else none
    | _, _ => none

/-- A vanish XML tree is well-formed when it decodes to an expression. -/
def WellFormed (t : XmlTree) : Prop := ∃ e, decode t = some e

/-- The formalized semantics of the XSLT templates in
    xslt/lower.xsl, one clause per template. The root template's
    trailing sequence is `lowerProgram`, below. -/
def lowerXml : XmlTree → List Instr
  | XmlTree.int n => [Instr.pushInt n]
  | XmlTree.sym x => [Instr.pushSym x]
  | XmlTree.add a b => lowerXml a ++ lowerXml b ++ [Instr.add]
  | XmlTree.sub a b => lowerXml a ++ lowerXml b ++ [Instr.sub]
  | XmlTree.mul a b => lowerXml a ++ lowerXml b ++ [Instr.mul]
  | XmlTree.pow a b => lowerXml a ++ lowerXml b ++ [Instr.pow]

/-- The formalized root template: the lowering plus the trailing
    checks NORMALIZE, ASSERT_ZERO, VERIFY_PROOF, HALT. -/
def lowerProgram (t : XmlTree) : List Instr :=
  lowerXml t ++ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt]

/-- Canonical form: unary minus eliminated to subtraction from zero,
    the form `decode` returns. Every other constructor is structural. -/
def canon : Expr → Expr
  | Expr.lit n => Expr.lit n
  | Expr.var x => Expr.var x
  | Expr.add a b => Expr.add (canon a) (canon b)
  | Expr.sub a b => Expr.sub (canon a) (canon b)
  | Expr.neg a => Expr.sub (Expr.lit 0) (canon a)
  | Expr.mul a b => Expr.mul (canon a) (canon b)
  | Expr.pow a n => Expr.pow (canon a) n

/-- Decoding is a left inverse of encoding up to the canonical form:
    the XML the emitter produces for an expression decodes back to
    that expression with unary minus written as subtraction from zero. -/
theorem decode_encode (e : Expr) : decode (encode e) = some (canon e) := by
  induction e with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb => simp [encode, decode, canon, iha, ihb]
  | sub a b iha ihb => simp [encode, decode, canon, iha, ihb]
  | neg a ih => simp [encode, decode, canon, ih]
  | mul a b iha ihb => simp [encode, decode, canon, iha, ihb]
  | pow a n ih => simp [encode, decode, canon, ih, Int.ofNat_nonneg, int_toNat_ofNat]

/-- The canonical form compiles exactly like the original: the
    sub-from-zero encoding is invisible to the compiler. -/
theorem compile_canon (e : Expr) : compile (canon e) = compile e := by
  induction e with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb => simp [canon, compile, iha, ihb]
  | sub a b iha ihb => simp [canon, compile, iha, ihb]
  | neg a ih => simp [canon, compile, ih]
  | mul a b iha ihb => simp [canon, compile, iha, ihb]
  | pow a n ih => simp [canon, compile, ih]

/-- The canonical form evaluates exactly like the original. -/
theorem eval_canon (ρ : Env) (e : Expr) : eval ρ (canon e) = eval ρ e := by
  induction e with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb => simp [canon, eval, iha, ihb]
  | sub a b iha ihb => simp [canon, eval, iha, ihb]
  | neg a ih => simp [canon, eval, ih, int_zero_sub]
  | mul a b iha ihb => simp [canon, eval, iha, ihb]
  | pow a n ih => simp [canon, eval, ih]

/-- Encoding is a right inverse of decoding on well-formed trees:
    every tree that decodes to `e` is the encoding of `e`. -/
theorem encode_decode (t : XmlTree) (e : Expr) (h : decode t = some e) :
    encode e = t := by
  induction t generalizing e with
  | int n =>
    simp only [decode, Option.some.injEq] at h
    subst h
    rfl
  | sym x =>
    simp only [decode, Option.some.injEq] at h
    subst h
    rfl
  | add a b iha ihb =>
    simp only [decode] at h
    cases ha : decode a with
    | none => simp [ha] at h
    | some a' =>
      cases hb : decode b with
      | none => simp [hb] at h
      | some b' =>
        simp only [ha, hb, Option.some.injEq] at h
        subst h
        simp only [encode, iha _ ha, ihb _ hb]
  | sub a b iha ihb =>
    simp only [decode] at h
    cases ha : decode a with
    | none => simp [ha] at h
    | some a' =>
      cases hb : decode b with
      | none => simp [hb] at h
      | some b' =>
        simp only [ha, hb, Option.some.injEq] at h
        subst h
        simp only [encode, iha _ ha, ihb _ hb]
  | mul a b iha ihb =>
    simp only [decode] at h
    cases ha : decode a with
    | none => simp [ha] at h
    | some a' =>
      cases hb : decode b with
      | none => simp [hb] at h
      | some b' =>
        simp only [ha, hb, Option.some.injEq] at h
        subst h
        simp only [encode, iha _ ha, ihb _ hb]
  | pow a b iha ihb =>
    simp only [decode] at h
    cases ha : decode a with
    | none => simp [ha] at h
    | some a' =>
      cases hb : decode b with
      | none => simp [hb] at h
      | some b' =>
        simp only [ha, hb] at h
        cases b' with
        | lit n =>
          by_cases hn : 0 ≤ n
          · simp only [hn, ↓reduceIte, Option.some.injEq] at h
            subst h
            have ha' : encode a' = a := iha _ ha
            have hb2 : XmlTree.int n = b := ihb _ hb
            have hnat : Int.ofNat n.toNat = n := by
              have h1 := Int.ofNat_toNat n
              show (n.toNat : Int) = n
              omega
            simp only [encode, ha', hnat, hb2]
          · simp at h
            exact absurd h.1 hn
        | var x => simp at h
        | add a1 a2 => simp at h
        | sub a1 a2 => simp at h
        | neg a1 => simp at h
        | mul a1 a2 => simp at h
        | pow a1 n => simp at h

/-- The formalized lowering agrees with the Lean compiler on every
    expression: the template semantics applied to the encoded AST is
    the compiled program. -/
theorem lowerXml_encode (e : Expr) : lowerXml (encode e) = compile e := by
  induction e with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb => simp [encode, lowerXml, compile, iha, ihb]
  | sub a b iha ihb => simp [encode, lowerXml, compile, iha, ihb]
  | neg a ih => simp [encode, lowerXml, compile, ih]
  | mul a b iha ihb => simp [encode, lowerXml, compile, iha, ihb]
  | pow a n ih => simp [encode, lowerXml, compile, ih]

/-- The root template agrees with the full compiled program. -/
theorem lowerProgram_encode (e : Expr) :
    lowerProgram (encode e) =
      compile e ++ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt] := by
  simp [lowerProgram, lowerXml_encode]

/-- UNIVERSAL CORRESPONDENCE. For every well-formed vanish XML tree,
    the formalized XSLT lowering equals the Lean compile of the
    expression the tree decodes to. Combined with `decode_encode`,
    this covers every well-formed expression. -/
theorem correspondence (t : XmlTree) (e : Expr) (h : decode t = some e) :
    lowerXml t = compile e := by
  have henc : encode e = t := encode_decode t e h
  rw [← henc, lowerXml_encode]

/-- The same statement over the well-formed predicate. -/
theorem correspondence_wf (t : XmlTree) (hw : WellFormed t) :
    ∃ e, lowerXml t = compile e := by
  obtain ⟨e, h⟩ := hw
  exact ⟨e, correspondence t e h⟩

/-- Determinism: the compiler is a total function, so one expression
    has exactly one instruction stream. -/
theorem compile_deterministic (e : Expr) (is1 is2 : List Instr)
    (h1 : compile e = is1) (h2 : compile e = is2) : is1 = is2 :=
  h1 ▸ h2

/-- Determinism: the formalized lowering is a total function. -/
theorem lowerXml_deterministic (t : XmlTree) (is1 is2 : List Instr)
    (h1 : lowerXml t = is1) (h2 : lowerXml t = is2) : is1 = is2 :=
  h1 ▸ h2

/-! ## Stack safety

  The compiled program is checked against a stack-length cap
  (`boundedRun`): the cap is enforced before every instruction and at
  the end, so a run that completes under a cap never had an
  intermediate stack longer than that cap. `boundedRun_agree` shows
  the cap never bites when it is at least `s.length + size e`, which
  is the precise sense in which the stack depth is bounded by the
  expression size. -/

/-- Expression size: an upper bound on the extra stack depth the
    compiled program needs beyond the incoming stack. A leaf pushes
    one value; a binary node needs its two children plus one for the
    result; a unary node needs its child plus one. -/
def size : Expr → Nat
  | Expr.lit _ => 1
  | Expr.var _ => 1
  | Expr.add a b => size a + size b + 1
  | Expr.sub a b => size a + size b + 1
  | Expr.neg a => size a + 1
  | Expr.mul a b => size a + size b + 1
  | Expr.pow a _ => size a + 1

/-- Every expression needs at least one stack slot. -/
theorem size_pos (e : Expr) : 1 ≤ size e := by
  induction e with
  | lit n => simp only [size]; omega
  | var x => simp only [size]; omega
  | add a b iha ihb => simp only [size]; omega
  | sub a b iha ihb => simp only [size]; omega
  | neg a ih => simp only [size]; omega
  | mul a b iha ihb => simp only [size]; omega
  | pow a n ih => simp only [size]; omega

/-- Bounded execution: `run` with a per-step stack-length cap. The
    bound is checked before every instruction and at the end, so a
    run that completes under the cap never had an intermediate stack
    longer than the cap. -/
def boundedRun (ρ : Env) (B : Nat) : List Instr → List Int → Option (List Int)
  | [], s => if s.length ≤ B then some s else none
  | i :: is, s =>
    if s.length ≤ B then
      match step ρ i s with
      | some s' => boundedRun ρ B is s'
      | none => none
    else none

/-- A bounded run fails at once when the starting stack already
    exceeds the cap. -/
theorem boundedRun_none_of_length (ρ : Env) (B : Nat) (is : List Instr) (s : List Int)
    (h : B < s.length) : boundedRun ρ B is s = none := by
  cases is with
  | nil => simp only [boundedRun, Nat.not_le.mpr h, if_false]
  | cons i is' => simp only [boundedRun, Nat.not_le.mpr h, if_false]

/-- Bounded execution splits over concatenated programs, like `run`. -/
theorem boundedRun_append (ρ : Env) (B : Nat) (is1 is2 : List Instr) (s : List Int) :
    boundedRun ρ B (is1 ++ is2) s =
      (boundedRun ρ B is1 s).bind (fun s' => boundedRun ρ B is2 s') := by
  induction is1 generalizing s with
  | nil =>
    by_cases hs : s.length ≤ B
    · simp only [List.nil_append, boundedRun, hs, if_true, Option.bind]
    · have hnone : boundedRun ρ B is2 s = none :=
        boundedRun_none_of_length ρ B is2 s (Nat.not_le.mp hs)
      simp only [List.nil_append, hnone, boundedRun, hs, if_false, Option.bind]
  | cons i is1 ih =>
    by_cases hs : s.length ≤ B
    · simp only [List.cons_append, boundedRun, hs, if_true]
      cases _hstep : step ρ i s with
      | none => rfl
      | some s' => exact ih s'
    · simp only [List.cons_append, boundedRun, hs, if_false, Option.bind]

/-- Bounded execution agrees with unbounded execution whenever the cap
    is at least the incoming stack length plus the expression size:
    no intermediate stack ever exceeds that bound. Proved by
    structural induction on the expression, using `compile_correct`
    to discharge each compiled part. -/
theorem boundedRun_agree (ρ : Env) (e : Expr) (s : List Int) (B : Nat)
    (hB : s.length + size e ≤ B) :
    boundedRun ρ B (compile e) s = run ρ (compile e) s := by
  induction e generalizing s B with
  | lit n =>
    simp only [size] at hB
    have h1 : s.length ≤ B := by omega
    have h2 : (n :: s).length ≤ B := by simp only [List.length_cons]; omega
    simp only [compile, boundedRun, run, step, h1, h2, if_true]
  | var x =>
    simp only [size] at hB
    have h1 : s.length ≤ B := by omega
    have h2 : (ρ x :: s).length ≤ B := by simp only [List.length_cons]; omega
    simp only [compile, boundedRun, run, step, h1, h2, if_true]
  | add a b iha ihb =>
    simp only [size] at hB
    have hBa : s.length + size a ≤ B := by omega
    have hBb : (eval ρ a :: s).length + size b ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hlen : (eval ρ b :: eval ρ a :: s).length ≤ B := by
      simp only [List.length_cons]; have ha := size_pos a; omega
    have hlen2 : ((eval ρ a + eval ρ b) :: s).length ≤ B := by
      simp only [List.length_cons]; omega
    simp only [compile, boundedRun_append, iha s B hBa, compile_correct, Option.bind,
               ihb (eval ρ a :: s) B hBb]
    simp only [boundedRun, run_append, compile_correct, Option.bind, run, step,
               hlen, hlen2, if_true]
  | sub a b iha ihb =>
    simp only [size] at hB
    have hBa : s.length + size a ≤ B := by omega
    have hBb : (eval ρ a :: s).length + size b ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hlen : (eval ρ b :: eval ρ a :: s).length ≤ B := by
      simp only [List.length_cons]; have ha := size_pos a; omega
    have hlen2 : ((eval ρ a - eval ρ b) :: s).length ≤ B := by
      simp only [List.length_cons]; omega
    simp only [compile, boundedRun_append, iha s B hBa, compile_correct, Option.bind,
               ihb (eval ρ a :: s) B hBb]
    simp only [boundedRun, run_append, compile_correct, Option.bind, run, step,
               hlen, hlen2, if_true]
  | neg a ih =>
    simp only [size] at hB
    have hBb : (0 :: s).length + size a ≤ B := by
      simp only [List.length_cons]; omega
    have hlen : (eval ρ a :: 0 :: s).length ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hlen2 : ((0 - eval ρ a) :: s).length ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hpush : boundedRun ρ B [Instr.pushInt 0] s = some (0 :: s) := by
      have h1 : s.length ≤ B := by omega
      have h2 : (0 :: s).length ≤ B := by simp only [List.length_cons]; omega
      simp only [boundedRun, step, h1, h2, if_true]
    simp only [compile, boundedRun_append, hpush, Option.bind, ih (0 :: s) B hBb, compile_correct]
    -- The two sides are computed separately: `simp only [run]` must not
    -- see `run` applied to the appended program, because its
    -- cons-equation unifies by unfolding `List.append [pushInt 0] Y`
    -- to `pushInt 0 :: ([] ++ Y)`, and the resulting `List.append`
    -- form no longer matches `run_append` (whose pattern uses `++`).
    have hbound : boundedRun ρ B [Instr.sub] (eval ρ a :: 0 :: s)
        = some ((0 - eval ρ a) :: s) := by
      simp only [boundedRun, step, hlen, hlen2, if_true]
    have hrun : run ρ ([Instr.pushInt 0] ++ compile a ++ [Instr.sub]) s
        = some ((0 - eval ρ a) :: s) := by
      simp only [run_append, compile_correct, Option.bind]
      simp only [run, step]
    rw [hbound, hrun]
  | mul a b iha ihb =>
    simp only [size] at hB
    have hBa : s.length + size a ≤ B := by omega
    have hBb : (eval ρ a :: s).length + size b ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hlen : (eval ρ b :: eval ρ a :: s).length ≤ B := by
      simp only [List.length_cons]; have ha := size_pos a; omega
    have hlen2 : ((eval ρ a * eval ρ b) :: s).length ≤ B := by
      simp only [List.length_cons]; omega
    simp only [compile, boundedRun_append, iha s B hBa, compile_correct, Option.bind,
               ihb (eval ρ a :: s) B hBb]
    simp only [boundedRun, run_append, compile_correct, Option.bind, run, step,
               hlen, hlen2, if_true]
  | pow a n ih =>
    simp only [size] at hB
    have hBa : s.length + size a ≤ B := by omega
    have hlen : (Int.ofNat n :: eval ρ a :: s).length ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hlen2 : ((eval ρ a ^ n) :: s).length ≤ B := by
      simp only [List.length_cons]; have h := size_pos a; omega
    have hpush : boundedRun ρ B [Instr.pushInt (Int.ofNat n)] (eval ρ a :: s)
        = some (Int.ofNat n :: eval ρ a :: s) := by
      have h1 : (eval ρ a :: s).length ≤ B := by
        simp only [List.length_cons]; have h := size_pos a; omega
      have h2 : (Int.ofNat n :: eval ρ a :: s).length ≤ B := hlen
      simp only [boundedRun, step, h1, h2, if_true]
    simp only [compile, boundedRun_append, ih s B hBa, compile_correct, Option.bind, hpush]
    simp only [boundedRun, run_append, compile_correct, Option.bind, run, step,
               hlen, hlen2, if_true, eval, int_toNat_ofNat]

/-- Stack safety: a compiled program never underflows the stack;
    execution always succeeds. Follows directly from
    `compile_correct`. -/
theorem stack_safe (ρ : Env) (e : Expr) (s : List Int) :
    run ρ (compile e) s ≠ none := by
  rw [compile_correct]
  simp

/-- Stack bound: the compiled program runs identically under any stack
    length cap of at least `s.length + size e`, so no intermediate
    stack ever exceeds `s.length + size e`. -/
theorem stack_bound (ρ : Env) (e : Expr) (s : List Int) (B : Nat)
    (hB : s.length + size e ≤ B) :
    boundedRun ρ B (compile e) s = run ρ (compile e) s :=
  boundedRun_agree ρ e s B hB

/-- Semantic preservation: executing the compiled program yields
    `eval e`. This is `compile_correct` restated under its Phase 1
    name; the proof is the universal theorem itself. -/
theorem semantic_preservation (ρ : Env) (e : Expr) (s : List Int) :
    run ρ (compile e) s = some (eval ρ e :: s) :=
  compile_correct ρ e s

end Vanish
