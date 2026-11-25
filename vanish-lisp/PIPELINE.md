<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
# VANISH-LISP pipeline

The full chain runs one expression from an S-expression to a sealed
ELF object and back, with a Lean proof at the end. Each stage is
runnable on its own; `tests/run_pipeline.sh` runs the whole chain on
the four examples and applies the admission gate.

## The chain

Scheme emits OpenMath as the canonical IR. XSLT converts OpenMath to
vanish XML. The vanish XML is canonicalized, lowered to the
stack-machine program, and certified. The ELF writer seals the
program, the AST, and the certificate into one object. The loader
reads it back and verifies the hashes. The VM executes it.

```
tests/examples/exN.sexp
  -> scheme/vanish.rkt --openmath            (OpenMath, canonical IR)
  -> openmath/openmath-to-vanish.xsl         (vanish XML)
  -> xslt/canonicalize.xsl                  (canonical vanish XML)
  -> xslt/lower.xsl                         (program XML)
  -> xslt/certificates.xsl                  (certificate XML)
  -> elf/writer/vanish-elf                  (ELF object)
  -> elf/loader/vanish-load                 (verify + dump)
  -> vm/vanish-vm                           (execute)
```

## Running the full chain

```sh
bash tests/run_pipeline.sh
```

It builds the C stages, runs the math test and the Scheme selftest,
runs the chain on all four examples, links ex1 + ex4, runs the AMPL
exact check, cross-checks the XSLT lowering against the Lean compile,
and applies the admission gate. It prints ADMIT or DENY and exits
non-zero on DENY. Intermediate artifacts and binaries land in
`tests/.pipeline-work/` (gitignored); the issued certificate XML for
each example lands in `certificates/`.

## Running each stage

Toolchains: Lean 4.12.0 and Lake via `~/.elan/bin` (put it on PATH);
gcc 13.3.0; Racket at `~/workspace/.tools/racket/bin/racket`; Elixir
1.20.5 with `xsltproc`. XSLT runs through `tests/xslt.exs`, which
drives libxslt via `xsltproc`. There is no SGML parser (no nsgmls)
and no DSSSL engine (no Jade/OpenJade) on this box; the grammar check
is `tests/check_dtd.exs` (the DTD's ELEMENT declarations parsed and
enforced directly) and the runnable DSSSL mirror is `scheme/vanish.rkt`.

Scheme (Racket mirror of the DSSSL rules):

```sh
racket scheme/vanish.rkt --xml tests/examples/ex1.sexp out.xml
racket scheme/vanish.rkt --openmath tests/examples/ex1.sexp out.om
racket scheme/vanish.rkt --normalize tests/examples/ex1.sexp
racket scheme/vanish.rkt --selftest
```

XSLT (via `tests/xslt.exs`, usage `xslt.exs STYLESHEET INPUT [name=value ...]`):

```sh
elixir tests/xslt.exs openmath/openmath-to-vanish.xsl out.om > out.xml
elixir tests/xslt.exs xslt/canonicalize.xsl out.xml > out.canon.xml
elixir tests/xslt.exs xslt/lower.xsl out.canon.xml > out.prog.xml
elixir tests/xslt.exs xslt/certificates.xsl out.prog.xml \
  ast-uri=file://$PWD/out.canon.xml \
  ast-hash=$(sha256sum out.canon.xml | cut -d' ' -f1) \
  program-hash=$(sha256sum out.prog.xml | cut -d' ' -f1) \
  generators="x^2 - 1" quotients="x^2 + 1" remainder="0" > out.cert.xml
elixir tests/program_to_text.exs out.prog.xml
elixir tests/check_dtd.exs sgml/vanish.dtd out.xml
elixir tests/check_om.exs out.rt.om out.om
```

C stages (all build with `gcc -std=gnu11 -O2 -Wall -Wextra -Werror`,
clean, no warnings):

```sh
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -I elf/abi \
  -o vanish-elf elf/writer/vanish-elf.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -I elf/abi \
  -o vanish-load elf/loader/vanish-load.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -I elf/abi \
  -o vanish-link elf/linker/vanish-link.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -I elf/abi -I math \
  -o vanish-vm vm/vanish-vm.c math/poly.c elf/abi/elfio.c elf/abi/sha256.c elf/abi/verify.c
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -o ampl-check ampl/check.c
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -I math \
  -o test-poly math/test_poly.c math/poly.c
./vanish-elf -o out.elf out.prog.xml out.canon.xml out.cert.xml
./vanish-load out.elf --dump
./vanish-vm out.elf
./vanish-link -o linked.elf ex1.elf ex4.elf
./ampl-check
./test-poly
```

Lean:

```sh
lake build
lake env lean tests/certificates/CertificateTests.lean
lake env lean tests/lean-cross-check.lean
```

Gherkin (after `tests/run_pipeline.sh` has built the work directory,
or with any `--work` directory holding the binaries and artifacts):

```sh
racket gherkin/runner.rkt --root . --work tests/.pipeline-work gherkin/vanishing.feature
```

## The admission gate

`Admit(M) = G_grammar AND G_semantics AND G_proof AND G_behavior AND G_binary`:

- `G_grammar`: the vanish XML validates against the SGML DTD structure
  (`tests/check_dtd.exs`).
- `G_semantics`: the OpenMath round-trip preserves the expression
  (vanish XML to OpenMath and back is the identity; the emitted
  OpenMath is either identical to the Scheme OpenMath or `vanishes()`
  of it — see below).
- `G_proof`: `lake build` passes and the Lean certificate check passes.
- `G_behavior`: all Gherkin scenarios pass.
- `G_binary`: the ELF loader round-trip reconstructs the identical AST
  and the section hashes match.

## Compiler correspondence (Phase 1)

The XSLT lowering (`xslt/lower.xsl`) and the Lean compiler
(`Vanish.compile` in `lean/Vanish/Pipeline.lean`) agree for every
well-formed expression. The proof and the evidence are split honestly
between the two sides, because a Lean model of XSLT is not the
stylesheet.

### The supported AST, complete

The supported set is the complete `Expr` type
(`lean/Vanish/Syntax.lean`). Every constructor is covered, and every
XSLT template has exactly one formalized counterpart. `neg` has no
template and no DTD element; it is supported through the
sub-from-zero encoding, used identically by the Scheme emitter
(`scheme/vanish.rkt`), by Lean `compile`, and by Lean `encode`.

| constructor | XSLT template | Lean `compile` | DTD element |
|---|---|---|---|
| `lit n` | `integer` | `[pushInt n]` | `integer` |
| `var x` | `symbol` | `[pushSym x]` | `symbol` |
| `add a b` | `add` | `compile a ++ compile b ++ [add]` | `add` |
| `sub a b` | `sub` | `compile a ++ compile b ++ [sub]` | `sub` |
| `neg a` | (none: sub-from-zero) | `[pushInt 0] ++ compile a ++ [sub]` | (none) |
| `mul a b` | `mul` | `compile a ++ compile b ++ [mul]` | `mul` |
| `pow a n` | `pow` | `compile a ++ [pushInt n] ++ [pow]` | `pow` |

The root template (`/`) and the `vanish | expr` wrapper templates only
recurse; they have no node of their own. The trailing sequence
`NORMALIZE, ASSERT_ZERO, VERIFY_PROOF, HALT` is `lowerProgram`.

### Rule-by-rule correspondence table

XSLT template in `xslt/lower.xsl` to its formalized semantics in
`lean/Vanish/Correspondence.lean` (`lowerXml`, `lowerProgram`):

| XSLT template | Lean function |
|---|---|
| `/` | `lowerProgram` (lowerXml + trailing checks) |
| `vanish \| expr` | identity recursion (no wrapper node) |
| `symbol` | `lowerXml (XmlTree.sym x)` = `[pushSym x]` |
| `integer` | `lowerXml (XmlTree.int n)` = `[pushInt n]` |
| `sub` | `lowerXml (XmlTree.sub a b)` = `lowerXml a ++ lowerXml b ++ [sub]` |
| `add` | `lowerXml (XmlTree.add a b)` = `lowerXml a ++ lowerXml b ++ [add]` |
| `mul` | `lowerXml (XmlTree.mul a b)` = `lowerXml a ++ lowerXml b ++ [mul]` |
| `pow` | `lowerXml (XmlTree.pow a b)` = `lowerXml a ++ lowerXml b ++ [pow]` |

### What is proved, and what is checked

Lean (`lean/Vanish/Correspondence.lean`, module `Vanish.Correspondence`,
imported by `lean/Vanish.lean`), all by structural induction over the
complete supported AST, zero `sorry`, zero `admit`, zero `by decide`,
zero unproven custom axioms:

- `decode_encode`: `decode (encode e) = some (canon e)`. Decoding
  returns the canonical form, not the literal input: `neg a` and
  `sub (lit 0) a` share one XML tree, one instruction stream, and one
  value, so the identification is invisible to the compiler and to
  the semantics. `compile_canon` and `eval_canon` prove the canonical
  form compiles and evaluates exactly like the original.
- `encode_decode`: every tree that decodes to `e` is the encoding of
  `e`.
- `lowerXml_encode`: `lowerXml (encode e) = compile e`.
- `lowerProgram_encode`: the root template agrees with the full
  compiled program.
- `correspondence` / `correspondence_wf`: for every well-formed tree,
  `lowerXml t = compile e`. This is the universal theorem.
- `compile_deterministic` / `lowerXml_deterministic`: the compiler
  and the lowering are total functions.
- `boundedRun_agree` / `stack_bound`: a compiled program runs
  identically under any stack-length cap of at least
  `s.length + size e`, so no intermediate stack ever exceeds
  `s.length + size e`. `size` is the expression size (leaf 1, binary
  `size a + size b + 1`, unary `size a + 1`).
- `stack_safe`: `run ρ (compile e) s ≠ none` — a compiled program
  never underflows the stack.
- `semantic_preservation`: executing the compiled program yields
  `eval ρ e` (the existing universal `compile_correct`, restated).

`tests/axioms.lean` prints the axiom dependencies of the main
theorems (`lake env lean tests/axioms.lean`). They depend only on the
standard Lean axioms `propext` and `Quot.sound`; no custom axioms,
no `sorryAx`.

XSLT side (`tests/correspondence.exs`, `tests/correspondence.sh`,
`tests/correspondence.exs --one SEXPR`, `scheme/batch-xml.rkt`): an
exhaustive corpus of every well-formed expression of depth `<= 2`
over variables `{x, y}` and literals `{0, 1}` with exponents
`{0, 1, 2}` (14,148 expressions), plus 30 hand-picked edge cases
(negative literals, exponent 4, deeper nesting, n-ary surface forms;
16 of them are new, 14 already in the corpus), for a total of
**14,164 expressions**. For each one the check runs the real XSLT
lowering twice on the real Scheme-emitted XML (determinism,
byte-compare), decodes the XML with an Elixir mirror of `Vanish.decode`
and compares it against the canonical form, and compares the lowering
against the Lean compiler and the formalized lowering from one
batched Lean run. The corpus check is wired into
`tests/run_pipeline.sh` and blocks ADMIT on any mismatch. Run it
alone with `bash tests/correspondence.sh`.

### Trusted boundary

The Lean model is not the stylesheet. The correspondence table above
is the explicit connection between the formalized transformation
semantics and the actual stylesheet, template by template. What
remains trusted, and is not proved in Lean, is:

- the XSLT engine executing the stylesheet as written (here libxslt,
  via `tests/xslt.exs`; the same engine `xsltproc` fronts), and
- the XML parser that reads the vanish XML.

The corpus check is the evidence on the XSLT side: the real
stylesheet, run by the real engine, agrees with the formalization on
every expression up to the stated bound. Finite corpus coverage is
differential testing only and is NOT the proof; it is not presented
as a universal XSLT proof. The universal statement lives on the Lean
side (`Vanish.correspondence`), and the boundary above is where the
two sides meet.

## The examples and their expected outcomes

- ex1 `(vanish (- x x))`: vanishes by the sub rule. VM passes
  ASSERT_ZERO, exit 0.
- ex2 `(- (pow x 4) 1)`: vanishes only under the constraint
  `x^2 - 1 = 0`, via the ideal certificate `x^4 - 1 = (x^2 + 1)(x^2 - 1)`.
  The VM fails ASSERT_ZERO with residual `x^4 - 1` (exit 1); that
  failure is the expected outcome, because the VM runs the program
  unconditionally. The AMPL exact check (max of `(x^4 - 1)^2` over
  `{-1, 1}` is 0) and the Lean certificate are the conditional proof.
- ex3 `(- x y)`: does not vanish. VM fails ASSERT_ZERO with residual
  `x - y` (exit 1), the expected outcome. Its certificate carries an
  empty witness and records the residual; the obligation stays open.
- ex4 `(* x 0)`: vanishes by the mul-zero rule. VM passes ASSERT_ZERO,
  exit 0.

## OpenMath: what it proves and what it does not

OpenMath describes meaning but does not prove correctness. The
vanish1 content dictionary (`openmath/vanish1.ocd`) names the
`vanishes` symbol, and the converters move expressions between
OpenMath, vanish XML, and Content MathML without changing what they
mean — but that movement is not a proof that the expression is zero.
The verification step is the correspondence between the vanish1 CD
symbols, the POP-11 reductions, and the Lean semantics: the Lean side
is `lean/Vanish/Pipeline.lean`, where `CDVanishes` defines the
vanish1 `vanishes` symbol as `eval` equal to zero in every
environment, and `cd_vanishes_iff_semantic` links it to
`SemanticallyVanishes`.

One consequence of the correspondence: the OpenMath an XSLT emits for
a bare expression is `vanishes()` of the Scheme OpenMath. The Scheme
emitter writes the bare expression (no vanishing claim); the vanish
XML root `<vanish>` is itself the vanishing claim, so the XSLT wraps
it in the vanish1 `vanishes` symbol. The round-trip check
(`tests/check_om.exs`) accepts either the identical object or the
`vanishes()` wrapping, and the vanish XML round-trip is the identity
in both cases.

## The certificate and the witness

`certificates/` holds the issued mathematical witness for each
pipeline example, generated by the pipeline run: the target AST, the
lowered program, the Lean certificate reference
(`Vanish.Certificate`, `cert_soundness`), the witness
(generators, quotients, remainder), and the SHA-256 digests of the AST
and the program. The ELF writer recomputes both digests and refuses
to seal on mismatch. The `.vanish.text` digest covers the lowered
program XML, the source the section is encoded from; `.vanish.hash`
holds the digests of the sealed section bytes.

A certificate with an empty witness and a remainder equal to the
target (ex3) is a record of an unresolved obligation, not a vanishing
proof. A certificate with an empty witness and remainder 0 (ex1, ex4)
records a vanishing by a rewrite rule, with no ideal needed.

## AMPL

`ampl/vanish.mod` is the model as supplied: maximize `(x^4 - 1)^2`
subject to `x^2 - 1 = 0`. AMPL is not installed on this box, so
`ampl/check.c` is the exact equivalent that runs here: the feasible
set is exactly `{-1, 1}`, the maximum is computed by exact
enumeration in integer arithmetic, and the maximum of 0 is the
certificate. A numerical solver result alone is not a proof; Lean
remains the final authority.
