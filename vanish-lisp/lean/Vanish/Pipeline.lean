-- VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- See the LICENSE file for the full text.

import Vanish.Semantics
import Vanish.Certificate

/-!
  Vanish.Pipeline -- The compiled pipeline in Lean: the stack-machine
  instruction set, the compiler from Expr to instructions, the
  machine's execution, and the preservation theorems. The instruction
  set and the compiler mirror the XSLT lowering (xslt/lower.xsl)
  opcode for opcode, and the ELF writer (elf/writer/vanish-elf.c)
  encodes exactly these opcodes. The vanishing theorem connects the
  compiled program back to the certificate soundness of
  Vanish.Certificate.
-/

namespace Vanish

/-- Stack-machine instructions. The opcode numbers are the ELF ABI
    (elf/abi/opcodes.h); the names match xslt/lower.xsl. -/
inductive Instr : Type
  | pushSym : String → Instr
  | pushInt : Int → Instr
  | dup : Instr
  | add : Instr
  | sub : Instr
  | mul : Instr
  | pow : Instr
  | normalize : Instr
  | assertZero : Instr
  | verifyProof : Instr
  | halt : Instr
  deriving Repr, DecidableEq, BEq

/-- One-line text form of an instruction, the same form the pipeline
    test extracts from the lowered program XML. -/
def instrToText : Instr → String
  | Instr.pushSym x => "PUSH_SYMBOL " ++ x
  | Instr.pushInt n => "PUSH_INT " ++ toString n
  | Instr.dup => "DUP"
  | Instr.add => "ADD"
  | Instr.sub => "SUB"
  | Instr.mul => "MUL"
  | Instr.pow => "POW"
  | Instr.normalize => "NORMALIZE"
  | Instr.assertZero => "ASSERT_ZERO"
  | Instr.verifyProof => "VERIFY_PROOF"
  | Instr.halt => "HALT"

/-- The compiler: Expr to the instruction list. This mirrors
    xslt/lower.xsl opcode for opcode. Negation has no element in the
    SGML DTD, so it compiles as subtraction from zero, the same
    encoding the Scheme emitter uses for unary minus. -/
def compile : Expr → List Instr
  | Expr.lit n => [Instr.pushInt n]
  | Expr.var x => [Instr.pushSym x]
  | Expr.add a b => compile a ++ compile b ++ [Instr.add]
  | Expr.sub a b => compile a ++ compile b ++ [Instr.sub]
  | Expr.neg a => [Instr.pushInt 0] ++ compile a ++ [Instr.sub]
  | Expr.mul a b => compile a ++ compile b ++ [Instr.mul]
  | Expr.pow a n => compile a ++ [Instr.pushInt (Int.ofNat n)] ++ [Instr.pow]

/-- One machine step. The stack head is the top. NORMALIZE is the
    identity on integer values: over Z, normalization preserves the
    value, and the polynomial normal form equals the integer the
    expression denotes. VERIFY_PROOF is the identity here; the real
    hash check lives in the C VM. -/
def step (ρ : Env) : Instr → List Int → Option (List Int)
  | Instr.pushSym x, s => some (ρ x :: s)
  | Instr.pushInt n, s => some (n :: s)
  | Instr.dup, a :: s => some (a :: a :: s)
  | Instr.add, b :: a :: s => some ((a + b) :: s)
  | Instr.sub, b :: a :: s => some ((a - b) :: s)
  | Instr.mul, b :: a :: s => some ((a * b) :: s)
  | Instr.pow, n :: a :: s => some (a ^ n.toNat :: s)
  | Instr.normalize, s => some s
  | Instr.assertZero, a :: s => if a = 0 then some (a :: s) else none
  | Instr.verifyProof, s => some s
  | Instr.halt, s => some s
  | _, _ => none

/-- Run an instruction list on a stack. -/
def run (ρ : Env) : List Instr → List Int → Option (List Int)
  | [], s => some s
  | i :: is, s =>
    match step ρ i s with
    | some s' => run ρ is s'
    | none => none

/-- Running a concatenated program is running the parts in sequence. -/
theorem run_append (ρ : Env) (is1 is2 : List Instr) (s : List Int) :
    run ρ (is1 ++ is2) s = (run ρ is1 s).bind (fun s' => run ρ is2 s') := by
  induction is1 generalizing s with
  | nil => rfl
  | cons i is1 ih =>
    simp only [List.cons_append, run]
    cases h : step ρ i s with
    | none => simp [h]
    | some s' => simp [h, ih]

/-- The integer pushed for a power exponent converts back to the
    same natural number. -/
theorem int_toNat_ofNat (n : Nat) : (Int.ofNat n).toNat = n := rfl

/-- Zero minus x is the negation of x. -/
theorem int_zero_sub (x : Int) : (0 : Int) - x = -x := by omega

/-- Compilation preserves the denotation: executing the compiled
    program leaves eval on the stack. -/
theorem compile_correct (ρ : Env) (e : Expr) (s : List Int) :
    run ρ (compile e) s = some (eval ρ e :: s) := by
  induction e generalizing s with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb =>
    simp only [compile, run_append, iha, ihb, run, step, eval, Option.bind]
  | sub a b iha ihb =>
    simp only [compile, run_append, iha, ihb, run, step, eval, Option.bind]
  | neg a ih =>
    simp only [compile]
    rw [run_append, run_append]
    show ((some (0 :: s)).bind (fun s' => run ρ (compile a) s')).bind (fun s' => run ρ [Instr.sub] s') = some (eval ρ (Expr.neg a) :: s)
    simp only [Option.bind, ih, run, step, eval, int_zero_sub]
  | mul a b iha ihb =>
    simp only [compile, run_append, iha, ihb, run, step, eval, Option.bind]
  | pow a n ih =>
    simp only [compile, run_append, ih, run, step, eval, int_toNat_ofNat, Option.bind]

/-- Running the trailing checks on one value: they pass exactly when
    the value is zero. -/
theorem run_tail (ρ : Env) (v : Int) :
    run ρ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt] [v]
      = if v = 0 then some [v] else none := by
  show (match step ρ Instr.normalize [v] with
        | some s' => run ρ [Instr.assertZero, Instr.verifyProof, Instr.halt] s'
        | none => none)
      = if v = 0 then some [v] else none
  show run ρ [Instr.assertZero, Instr.verifyProof, Instr.halt] [v]
      = if v = 0 then some [v] else none
  show (match step ρ Instr.assertZero [v] with
        | some s' => run ρ [Instr.verifyProof, Instr.halt] s'
        | none => none)
      = if v = 0 then some [v] else none
  show (match (if v = 0 then some [v] else none : Option (List Int)) with
        | some s' => run ρ [Instr.verifyProof, Instr.halt] s'
        | none => none)
      = if v = 0 then some [v] else none
  by_cases h : v = 0 <;> simp [run, step, h]

/-- A compiled program whose checks succeed establishes that the
    expression evaluates to zero. -/
theorem program_vanishes (ρ : Env) (e : Expr) :
    run ρ (compile e ++ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt]) [] = some [0] →
    eval ρ e = 0 := by
  intro h
  simp only [run_append, compile_correct, run_tail, Option.bind] at h
  by_cases hz : eval ρ e = 0
  · exact hz
  · simp [hz] at h

/-- A valid certificate makes the compiled program succeed: the
    certificate's target vanishes, so the program's ASSERT_ZERO
    passes. This is the Lean side of the certificate the ELF writer
    seals into .vanish.proof. -/
theorem vanish_of_cert_program (c : VanishingCert) (h : ValidCert c)
    (ρ : Env) (hgens : ∀ g ∈ c.generators, eval ρ g = 0) :
    run ρ (compile c.target ++ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt]) [] = some [0] := by
  have hz : eval ρ c.target = 0 := cert_soundness c h ρ hgens
  simp [run_append, compile_correct, run_tail, hz]

/-- The vanish1 CD symbol `vanishes` denotes: the expression equals
    zero in every environment. This is the Lean form of the OpenMath
    content dictionary definition in openmath/vanish1.ocd. -/
def CDVanishes (e : Expr) : Prop := ∀ ρ : Env, eval ρ e = 0

/-- The CD symbol means exactly unconditional semantic vanishing. -/
theorem cd_vanishes_iff_semantic (e : Expr) :
    CDVanishes e ↔ SemanticallyVanishes [] e := by
  constructor
  · intro h ρ _
    exact h ρ
  · intro h ρ
    apply h ρ
    intro c hc
    simp at hc

end Vanish
