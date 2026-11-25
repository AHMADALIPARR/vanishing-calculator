import Vanish.Pipeline

/-!
  lean-cross-check -- Print the Lean compiler's output for the four
  pipeline examples, one instruction per line, in the same form as
  tests/program_to_text.exs prints the XSLT lowering. The pipeline
  test diffs the two outputs: the XSLT lowering and the Lean compile
  must agree instruction for instruction.
-/

namespace VanishTests

open Vanish

/-- Print the full compiled program for one expression, trailing
    checks included. -/
def showProgram (e : Expr) : IO Unit := do
  let prog := compile e ++ [Instr.normalize, Instr.assertZero,
    Instr.verifyProof, Instr.halt]
  for i in prog do
    IO.println (instrToText i)

-- ex1: (vanish (- x x))
#eval showProgram (Expr.sub (Expr.var "x") (Expr.var "x"))

-- ex2: (- (pow x 4) 1)
#eval showProgram (Expr.sub (Expr.pow (Expr.var "x") 4) (Expr.lit 1))

-- ex3: (- x y)
#eval showProgram (Expr.sub (Expr.var "x") (Expr.var "y"))

-- ex4: (* x 0)
#eval showProgram (Expr.mul (Expr.var "x") (Expr.lit 0))

end VanishTests
