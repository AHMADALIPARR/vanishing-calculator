<!--
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
-->
# VANISH-LISP — Status

Source: `vanish-lisp.zip`, sha256
`53c5393dc70edf04969c89959fc7d1fab77c0451599f67352d1c120b60f8197a`,
29 files, all present byte-for-byte (see `MANIFEST.sha256`).
Created as a local repo 2026-11-24. Nothing pushed; no destination
or token was named.

## Verification, measured on this box (2026-11-24)

Toolchain: Lean 4.12.0 via elan (matches `lean-toolchain`),
GNU Emacs 29.3, gcc not needed. No Pop-11 runtime on this box.

### Lean — header and layout fixed, build still fails at Soundness

As supplied, `lake build` failed at `lean/Vanish.lean:5:0: error:
invalid 'import' command, it must be used in the beginning of the
file`, because a `/-! -/` module doc comment sat above the imports
(proven by a minimal probe on Lean 4.12.0: doc comment first fails,
import first passes). That fix is installed: the `import` lines now
sit above the `/-!` header in all seven files. The module layout is
fixed too: the six modules now live in `lean/Vanish/`, where their
`Vanish.*` names say they belong (the lakefile uses `srcDir "lean"`
and root `Vanish`), and `lean/Vanish.lean` stays at the root.

`lake build` still fails, now at `Vanish.Soundness`: the proof leaves
the goal `eval ρ e' ^ 1 = eval ρ e'` open. That is a proof failure in
the supplied code, not a header or layout issue. `Vanish.Ideals` and
`Vanish.Certificate` build clean; `Vanish.Termination` and `Vanish`
wait on `Soundness`.

Lean hygiene: no `sorry`, `admit`, or `by decide` in `lean/` or
`tests/`. No TODO markers anywhere in the repo.

### Emacs Lisp — reduction passes, differential fails

- `make test-elisp`, reduction suite: 3/3 pass.
- `make test-elisp`, differential suite: 0/1 pass.
  `vl-test-derivative-vanishing` fails:
  `(vanish (derivative x (pow x 2)))` returns `(* 2 x 1)`,
  the test expects `(* 2 x)`.
  Cause: the power-rule derivative carries the chain-rule factor 1,
  giving the 3-argument form `(* 2 x 1)`, and `vl-normalize` only
  drops a factor 1 for 2-argument `*`, so the form is left
  unnormalized.
  Fix offered, not installed: either make `vl-normalize` drop 1s
  (and fold constants) in n-argument `*`, or change the test
  expectation to `(* 2 x 1)`.
- Byte-compile: all 5 files in `elisp/` compile clean with
  `emacs --batch -L elisp` (no errors, no warnings shown).

### POP-11 — staged, not run

No `pop11` binary on this box, so `make test-pop11` cannot run
here. All 6 files in `pop11/` plus `tests/algebra/ideal-cases.p`
are present and scanned (no TODO markers); none were executed.
Note, untested: `pop11/vanish.p` loads its siblings by bare
filename (`load('stack.p')` etc.), and `tests/algebra/ideal-cases.p`
loads `../../pop11/vanish.p`, so the load path matters when run.

## License

`LICENSE` is the GNU Affero General Public License v3, Copyright (c) 2026 VANISH-LISP
Contributors. No personal name appears in it.

## Combined repo (2026-11-24)

One repo: this Lake project at the root, and the actual system as a
subdirectory. `vanishing-calculator/` holds the calculator kernels
(PowerShell, Racket, Common Lisp, Poplog, C core, ob-lean4.el) copied
from the pirtm-hcalc repo; its own `verify.py` passes 66 checks,
0 failures, run from inside that directory. The old pirtm-hcalc copy
is still on disk untouched.

## Files added by the repo build (not in the zip)

- `STATUS.md` — this file.
- `verify.sh` — runs `lake build`, the two ERT suites, and the
  Elisp byte-compile check; exits non-zero while the two known
  failures above stand.
- `MANIFEST.sha256` — sha256 of the current tree.
- `MANIFEST.zip.sha256` — sha256 of the 29 files as supplied in the zip.
- `vanishing-calculator/` — the calculator kernels, from pirtm-hcalc.
- `.gitignore` — `.lake/`, `*.elc`, `lake-manifest.json`.

## Pipeline (2026-11-24)

Full chain: Scheme --openmath -> OpenMath (canonical IR) ->
openmath-to-vanish.xsl -> vanish XML -> canonicalize -> lower ->
certificates -> ELF writer -> loader -> VM. Run with
`bash tests/run_pipeline.sh`; it prints ADMIT or DENY and exits
non-zero on DENY. Full run instructions are in PIPELINE.md.

### Lean build fix

`lake build` failed at Vanish.Soundness with the open goal
`eval rho e' ^ 1 = eval rho e'` (`unknown constant 'Int.pow_one'`).
Probed on Lean 4.12.0 core, no Mathlib: `pow_one`, `pow_zero`,
`pow_succ`, `pow_add`, `Int.pow_one`, `Int.pow_add`, `one_mul` do not
exist unqualified; `Int.pow_succ` and `Int.pow_zero` exist. Fixes:
Soundness.lean uses `simp [eval, Int.pow_succ, Int.pow_zero]`;
Termination.lean `termination_step` rewritten (omega does not use
universally-quantified hypotheses in core 4.12.0; only the subSelf
case needs positivity); Vanish.lean and
tests/certificates/CertificateTests.lean use
`simp only [Int.pow_succ, Int.pow_zero, Int.one_mul, Int.mul_assoc]`.
No sorry, no admit, no by decide on ground goals (grep clean).
`lake build` passes 9/9; `lake env lean
tests/certificates/CertificateTests.lean` exits 0.

New module lean/Vanish/Pipeline.lean (imported by lean/Vanish.lean):
Instr (11 constructors, opcodes matching elf/abi/opcodes.h and
xslt/lower.xsl), compile : Expr -> List Instr mirroring the XSLT
lowering opcode for opcode, step/run, compile_correct (executing
compile e leaves eval e on the stack), run_tail, program_vanishes,
vanish_of_cert_program (connects cert_soundness), CDVanishes (the
vanish1 CD symbol `vanishes` as eval e = 0 in every environment) and
cd_vanishes_iff_semantic. Proof notes: `++` is left-associative, so
the run_append rewrites split the outer append first; Option.bind
redexes need `Option.bind` in the simp set or the step matches stay
stuck under binders; `a + b :: s` parses as `a + (b :: s)`, so the
step equations parenthesize the arithmetic.

Cross-check: `lake env lean tests/lean-cross-check.lean` prints the
Lean compile for the four examples (30 lines); `diff` against
`tests/program_to_text.py` on the XSLT lowering is empty. XSLT
lowering == Lean compile on all four examples.

### Tool substitutions on this box

- No xsltproc binary exists here (not on PATH, not in /usr/bin).
  tests/xslt.py runs the transforms through lxml, which embeds
  libxslt 1.1.39, the same XSLT 1.0 engine xsltproc fronts.
- No SGML parser (no nsgmls): tests/check_dtd.py translates the SGML
  DTD's `- -` minimization markers out and validates with libxml2.
  All four examples validate; a malformed add (one expr) is rejected.
- No DSSSL engine (no Jade/OpenJade): scheme/vanish.rkt is the
  runnable Racket mirror. Selftest 17/17 PASS.
- No pop11 binary: the Gherkin runner drives the POP-11 reduction
  through the Scheme mirror of pop11/rewrite.p.
- AMPL is not installed: ampl/check.c is the exact certified
  equivalent of ampl/vanish.mod (exact enumeration over {-1, 1} in
  integer arithmetic; max of (x^4 - 1)^2 is 0).

### Provenance flags

- OpenMath: the paste texts for vanish1.ocd and the example objects
  were NOT in the working context. The OCD and the example objects
  were authored from the field/spec descriptions given in the brief,
  in standard OpenMath form. Do not claim them verbatim.
- AMPL: ampl/vanish.mod is the model verbatim as supplied.
- Gherkin: Scenario 1 ("Polynomial vanishing under constraints") is
  verbatim as far as given. The steps of Scenario 2 ("Unresolved
  mathematical obligation") and Scenario 3 ("Binary round-trip
  preservation") were not quoted in the brief; they are written in
  the same style from the scenario titles, implementable by the
  runner, and noted as such in gherkin/vanishing.feature.

### Verification results (full pipeline run, 2026-11-24)

- `bash tests/run_pipeline.sh` -> ADMIT, exit 0.
- C builds: gcc -std=gnu11 -O2 -Wall -Wextra -Werror clean for
  vanish-elf, vanish-load, vanish-link, vanish-vm, ampl-check,
  test-poly.
- math/test_poly: 13/13 PASS. Scheme selftest: 17/17 PASS.
- Per example: OpenMath -> vanish XML equals the direct Scheme XML;
  certificate issued to certificates/exN.cert.xml; ELF sealed;
  loader verifies hashes. VM: ex1 exit 0 (ASSERT_ZERO passes); ex2
  exit 1 with `ASSERT_ZERO FAIL: residual x^4 - 1` (expected,
  conditional vanishing); ex3 exit 1 with `ASSERT_ZERO FAIL:
  residual x - y` (expected, non-vanishing); ex4 exit 0.
- Linker: ex1 + ex4 -> 13 instructions, 1 symbol; loader verifies;
  linked VM exit 0.
- AMPL check: x = -1 and x = 1, residual 0, max violation 0, PASS.
- Admission gate: G_grammar ok, G_semantics ok, G_proof ok,
  G_behavior ok (3 Gherkin scenarios pass), G_binary ok.
- G_semantics note: the OpenMath the XSLT emits for a bare
  expression is vanishes() of the Scheme OpenMath (the <vanish> root
  is the vanishing claim); tests/check_om.py accepts the identical
  object or the vanishes() wrapping, and the vanish XML round-trip is
  the identity in both cases.
- The known differential ERT failure (vl-test-derivative-vanishing)
  is out of scope and untouched; verify.sh still exits non-zero
  while it stands. (Superseded by the Phase 1 section below: the
  fix is installed, committed as 00afa4d, and verify.sh exits 0.)

## Strengthening — Phase 1: Universal Compiler Correspondence (2026-11-24)

Step 0 — differential test fixed (banked separately, commit 00afa4d):
`vl-normalize` in `elisp/vanish.el` now drops 1s and folds constants
in n-argument `*` (`vl-normalize-product`), so
`(vanish (derivative x (pow x 2)))` returns `(* 2 x)`. The test
expectation was not changed. Regression test
`vl-test-normalize-nary-product` added to
`tests/reduction/test-reduction.el`. `make test-elisp`: reduction
4/4, differential 1/1. `./verify.sh` exits 0 (ALL CHECKS PASS).
GNU Emacs 29.3 was installed from the Ubuntu pool via apt
(`apt-get install -y --no-install-recommends emacs-nox`); it was
absent on this VM after a VM replacement.

Step 1 — universal compiler correspondence. The proofs are derived
from the existing compiler and theorems, not rebuilt from scratch:
the correspondence builds on `compile` and the universal
`compile_correct` in `lean/Vanish/Pipeline.lean`, and on the
existing `eval` semantics in `lean/Vanish/Semantics.lean`.

New module `lean/Vanish/Correspondence.lean` (module
`Vanish.Correspondence`, imported by `lean/Vanish.lean`).
`lake build` passes; the file compiles with zero errors and zero
warnings. Zero `sorry`, zero `admit`, zero `by decide`, zero
unproven custom axioms (grep clean; see the axioms list below).

Enumeration (complete, matches the XSLT templates one to one):
`lit`, `var`, `add`, `sub`, `neg`, `mul`, `pow` — the whole `Expr`
type. `neg` has no template and no DTD element; it is supported
through the sub-from-zero encoding, used identically by the Scheme
emitter, by Lean `compile`, and by Lean `encode`. Recorded in the
Lean file header and in PIPELINE.md.

Theorems (all by structural induction over the complete supported
AST):
- `decode_encode`: `decode (encode e) = some (canon e)`. Decoding
  returns the canonical form: `neg a` and `sub (lit 0) a` share one
  XML tree, one instruction stream, and one value, so the
  identification is invisible to the compiler and the semantics.
  `compile_canon` and `eval_canon` prove the canonical form
  compiles and evaluates exactly like the original.
- `encode_decode`: every tree that decodes to `e` is the encoding
  of `e`.
- `lowerXml_encode`: `lowerXml (encode e) = compile e`.
- `lowerProgram_encode`: the root template agrees with the full
  compiled program.
- `correspondence` / `correspondence_wf`: for every well-formed
  tree, `lowerXml t = compile e`. The universal theorem.
- `compile_deterministic` / `lowerXml_deterministic`: the compiler
  and the lowering are total functions.
- `boundedRun_agree` / `stack_bound`: a compiled program runs
  identically under any stack-length cap of at least
  `s.length + size e`, so no intermediate stack ever exceeds
  `s.length + size e` (`size`: leaf 1, binary
  `size a + size b + 1`, unary `size a + 1`).
- `stack_safe`: `run ρ (compile e) s ≠ none` — a compiled program
  never underflows the stack.
- `semantic_preservation`: executing the compiled program yields
  `eval ρ e` (the existing universal `compile_correct`, restated).

Proof notes: `cases h : decode a` does not substitute into the
hypothesis, so the `encode_decode` proof rewrites the hypothesis
with the case equations first (`simp only [ha, hb] at h`); the
`pow` exponent fact is `Int.ofNat n.toNat = n`, proved from
`Int.ofNat_toNat n` (`↑n.toNat = max n 0`) plus `omega` on the cast
form. In the `neg` case of `boundedRun_agree`, `simp only [run]`
must not see `run` applied to the appended program: its
cons-equation unifies by unfolding `List.append [pushInt 0] Y` to
`pushInt 0 :: ([] ++ Y)`, and the resulting `List.append` form no
longer matches `run_append` (whose pattern uses `++`); the two
sides are computed separately instead.

Axioms (`lake env lean tests/axioms.lean`, recorded in
`tests/axioms.lean`): every main theorem depends only on the
standard Lean axioms `propext` and `Quot.sound`; `compile_deterministic`
and `lowerXml_deterministic` depend on no axioms at all. No custom
axioms, no `sorryAx`.

Corpus check (the XSLT side — differential testing, NOT the proof):
`tests/correspondence.py` (+ `tests/correspondence.sh`,
`scheme/batch-xml.rkt`, one Racket process for the whole corpus so
it uses the real Scheme emitter end to end). Bound: every
well-formed expression of depth <= 2 over variables `{x, y}` and
literals `{0, 1}` with exponents `{0, 1, 2}` (14,148 expressions),
plus 30 hand-picked edge cases (negative literals, exponent 4,
deeper nesting, n-ary surface forms; 16 new, 14 already in the
corpus), total **14,164 expressions**. For each one: the real XSLT
lowering run twice (determinism, byte-compare), the Scheme XML
decoded with a Python mirror of `Vanish.decode` and compared
against the canonical form, and the lowering compared against the
Lean compiler and the formalized lowering from batched Lean runs.
Result: `correspondence corpus: PASS (14164 expressions)`,
determinism PASS, decode PASS, lowering==compile PASS,
lowering==lowerXml PASS, trailing PASS, in 2m39s. The Lean batch is
split into chunks of 500 expressions per run: elaborating one
giant `List Expr` literal is severely superlinear (1000 fast,
2000 slow, 4000 does not finish in 280s). Per-expression check:
`python3 tests/correspondence.py --one SEXPR`.
Finite corpus coverage is differential testing only and is NOT a
universal XSLT proof; the universal statement is
`Vanish.correspondence` on the Lean side.

Gherkin: new scenario "Compiler correspondence and stack safety"
in `gherkin/vanishing.feature`, with real bindings in
`gherkin/runner.rkt` (new `corr` and `axioms` context fields; the
correspondence When step runs `tests/correspondence.py --one` on
the scenario polynomial, the Lean When step runs
`tests/axioms.lean` and rejects any non-standard axiom; the Then
steps assert lowering == compile, determinism, no underflow
(`stack_safe`), the stack bound (`stack_bound`), and the decode
round-trip from the stored results). 4 scenarios pass, 0 failed.

Trusted boundary (stated in the Lean file, in PIPELINE.md, and
here): the Lean model is not the stylesheet. The rule-by-rule
correspondence table in the Lean file header and in PIPELINE.md is
the explicit connection between the formalized transformation
semantics and the actual stylesheet, template by template. What
remains trusted, and is not proved in Lean, is the XSLT engine
executing the stylesheet as written (here libxslt, via
`tests/xslt.py`) and the XML parser that reads the vanish XML.
The corpus check is the evidence on the XSLT side.

Pipeline wiring: `tests/run_pipeline.sh` runs the corpus check
(`bash tests/correspondence.sh`) before the admission gate; a
failure increments FAILURES and blocks ADMIT.

Verification results (Phase 1, 2026-11-24):
- `lake build` passes (Vanish.Correspondence built).
- `lake env lean tests/axioms.lean` exits 0, standard axioms only.
- `python3 tests/correspondence.py` exits 0, PASS on 14,164
  expressions.
- `racket gherkin/runner.rkt --root . --work tests/.pipeline-work
  gherkin/vanishing.feature`: 4 scenarios, 0 failed.
- `./verify.sh` exits 0 (ALL CHECKS PASS).
- `bash tests/run_pipeline.sh` prints ADMIT, exit 0 (full run
  2026-11-24, ~3 min; the corpus check is part of it and passed;
  all five admission gates ok, 4 Gherkin scenarios pass).

## README rewrite — benchmarks, figures, math (2026-11-24)

README.md rewritten to the pirtm-hcalc pattern (title, subtitle, badges,
stat table, contents, Overview, Architecture, layout, one section per
layer, Build and reproduce, Benchmarks, Verification evidence, Trust
boundaries, Axiom audit, Assurance matrix, Figure provenance,
Provenance and licensing). The owner's title line is unchanged. No code,
proof, or test file was touched; only README.md, docs/figures/, and
this file. Figures are real SVGs under docs/figures/: pipeline.svg
(stages of tests/run_pipeline.sh, in order), admission.svg (the five
gates), correspondence.svg (XSLT lowering = Lean compile), and
benchmarks.svg (bar chart generated by docs/figures/gen-benchmarks.py
from docs/figures/benchmarks.tsv, log scale).

### Benchmark measurement log (all measured 2026-11-24, wall clock)

Environment: this box, 1.5 shared CPUs, 6 GB RAM. Lean 4.12.0
(commit dc2533473114) and Lake 5.0.0 via ~/.elan/bin; gcc 13.3.0;
Racket 8.15; GNU Emacs 29.3; Python 3.12.3 with lxml 5.2.1 /
libxslt 1.1.39 (xsltproc absent on this VM). Timed with the shell
`time` builtin (TIMEFORMAT wall=%Rs); /usr/bin/time does not exist
here.

- `lake clean && lake build`: 6.110s wall (5.773s user, 0.684s sys),
  "Build completed successfully", 11 targets.
- `lake build` immediately after (incremental): 0.162s wall.
- `./verify.sh`: 1.053s wall, ALL CHECKS PASS (lake build, ERT
  reduction 4/4, ERT differential 1/1, byte-compile PASS, pop11 SKIP).
- `bash tests/run_pipeline.sh`: 211.247s wall (171.384s user,
  6.533s sys), ADMIT, exit 0, all five gates ok.
- `bash tests/correspondence.sh` standalone: 194.503s wall
  (159.513s user, 3.387s sys), PASS on 14,164 expressions, all five
  checks green (determinism, decode, lowering==compile,
  lowering==lowerXml, trailing).
- C builds (six binaries, one gcc -std=gnu11 -O2 -Wall -Wextra
  -Werror invocation each): 4.489s wall total, clean.
- `test-poly`: 0.002s wall, 13/13 PASS.
- `ampl-check`: 0.001s wall, max violation 0 over {-1, 1}, PASS.
- `make test-elisp`: 0.340s wall, reduction 4/4, differential 1/1.
- `racket scheme/vanish.rkt --selftest`: 2.747s wall, 17/17 PASS.
- `racket gherkin/runner.rkt --root . --work tests/.pipeline-work
  gherkin/vanishing.feature`: 6.561s wall, 4 scenarios, 0 failed.
  (With an empty work dir the runner fails 3 scenarios because the
  pipeline artifacts it checks do not exist there; the pipeline
  itself invokes it with the populated work dir.)
- `lake env lean tests/axioms.lean`: 0.436s wall, exit 0.
- `lake env lean tests/certificates/CertificateTests.lean`:
  0.366s wall, exit 0.

Counts measured in the same run: 103 tracked files
(`git ls-files | wc -l`); 10,565 lines in tracked files; Lean 1,064
lines, Elisp 1,516, Racket 982, C/H 2,674, XSLT 387, DSSSL/DTD/SGML/
OCD/OM/XML 200, POP-11 772, AMPL + feature 49, Markdown 941. Lean:
35 theorem declarations, 21 definitions. Axioms (13 audited
theorems): 8 depend on propext + Quot.sound, 3 on propext only, 2
on no axioms. Gherkin: 4 scenarios. Corpus: 14,164 expressions.

## README rewrite — production README and CI (2026-11-24)

README.md rewritten to the production pattern of the owner's own public repos (pirtm-hcalc, read via the GitHub page, and the SNAPKITTYWEST umbrella README): H1 title, subtitle, shields.io badges, author line, ASCII architecture diagram, stat table, numbered contents, Overview, Architecture, repository layout, one deep section per layer with the actual functions, templates, theorems, and opcodes from the code, Build and reproduce, Continuous integration, Benchmarks, Verification evidence, Trust boundaries, Axiom audit, Assurance matrix, Figure provenance, Provenance and licensing. The owner's title line is unchanged. The previous 317-line README was rejected by the owner as thin outlines; this rewrite is 628 lines, 7,078 words, and says what each part of the repo is and does, from the code itself. No code, proof, or test file was touched; only README.md, .github/workflows/ci.yml, and this file. Benchmark numbers are the measured 2026-11-24 values from the earlier rewrite; nothing was re-measured and no number was invented. The axiom table names the theorems in each dependency category, verified by re-running `lake env lean tests/axioms.lean` for this revision. The pattern repos sovereign-eda, boyer-moore-search, and cognition-netlist were not retrievable by search (no indexed README pages found); the pattern comes from pirtm-hcalc and SNAPKITTYWEST, both read in full.

CI: `.github/workflows/ci.yml` runs `./verify.sh` and the full `bash tests/run_pipeline.sh` on push and pull request, installing elan (pinned Lean 4.12.0), Racket, Emacs, and Python lxml. The pipeline script expects Racket at `~/workspace/.tools/racket/bin/racket`, so the workflow symlinks the installed Racket binary to that path; no repository script was modified for CI. The CI badge in the README points at `AHMADALIPARR/vanish-lisp` (the assumed destination repo; correct it if the push lands elsewhere). The workflow has never run and the badge shows no result: the repository has never been pushed.

Counts at this rewrite: 110 tracked files, 11547 lines. Lean 1,064, Elisp 1,516, Racket 982, C/H 2,674, XSLT 387, DSSSL/DTD/SGML/OCD/OM/XML 200, POP-11 772, AMPL + feature 49, Markdown 1,590, Python 951, shell 278, YAML 40. Lean: 35 theorem declarations, 21 definitions. Axioms (13 audited theorems): 8 depend on propext + Quot.sound, 3 on propext only, 2 on no axioms. Gherkin: 4 scenarios. Corpus: 14,164 expressions.
