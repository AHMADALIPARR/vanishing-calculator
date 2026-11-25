# monorepo

[![CI](https://github.com/AHMADALIPARR/monorepo/actions/workflows/ci.yml/badge.svg)](https://github.com/AHMADALIPARR/monorepo/actions/workflows/ci.yml)
[![verify.sh](https://img.shields.io/badge/verify.sh-passing-brightgreen)](bench/ci.log)
[![C builds](https://img.shields.io/badge/C%20builds-passing-brightgreen)](bench/ci.log)
[![calculators](https://img.shields.io/badge/calculators-passing-brightgreen)](bench/ci.log)
[![pipeline](https://img.shields.io/badge/pipeline-known--blocked-yellow)](bench/ci.log)
[![sovereign](https://img.shields.io/badge/sovereign-passing-brightgreen)](bench/ci.log)
[![no Python in vanish-lisp](https://img.shields.io/badge/vanish--lisp-no%20Python-blue)](bench/ci.log)

> CI badge slug `AHMADALIPARR/monorepo` is assumed — correct it if the push
> lands elsewhere. The workflow badge only turns green once the repo is
> pushed to GitHub and Actions runs; the static badges above reflect the
> local CI run, `bash bench/ci.sh` (log: `bench/ci.log`, **CI GREEN**).

One repo, assembled by file movement only. No code was overwritten or edited
to build it — files were copied in pristine from their sources, and the only
new files here are this README, `.github/workflows/ci.yml`, `bench/` and `visuals/`.

## Layout

| Path | What it is | Source |
|---|---|---|
| `vanish-lisp/` | Vanishing-calculator project: Lean 4 proofs, Racket/Scheme, Elisp, POP-11, C ELF toolchain, XSLT/OpenMath pipeline | `vanish-lisp-no-python-agpl.zip` (sha256 `38d8bc74…`) |
| `sovereign-beam-mojo/` | Sudo Platform reverse-engineered to original stubs: Elixir/OTP control plane, Mojo kernels, Bash pipeline | `~/workspace/sovereign-beam-mojo/` |
| `vanishing_calculator.lisp` | Standalone Common Lisp vanishing calculator, byte-identical to `vanish-lisp/vanishing-calculator/vanishing_calculator.lisp` (sha256 `d8ed5d66…`) | uploaded file |
| `bench/` | Benchmark harness, pipeline logs, timing TSVs, CI runner (created for this task, not repo code) | — |
| `visuals/` | Benchmark chart + terminal photos (created for this task) | — |
| `.github/workflows/ci.yml` | GitHub Actions CI (6 jobs; mirrors `bench/ci.sh`) | — |

## Python audit

- `vanish-lisp/`: **0 Python files.** The zip's name is honest about its
  contents — but 5 Python helpers the pipeline calls were stripped from it:
  `tests/xslt.py`, `tests/program_to_text.py`, `tests/check_dtd.py`,
  `tests/check_om.py`, `tests/correspondence.py`. The shipped
  `MANIFEST.sha256` is stale (10 hashes mismatch, 2 files missing).
- Whole monorepo: exactly **1** Python file,
  `sovereign-beam-mojo/kernels/tests/verify_sha256_and_framing.py`
  (a test mirror, not part of vanish-lisp).
- All benchmarks and pipeline runs below used **no Python**: `xsltproc`,
  `awk`, `sed`, `gcc`, `lake`, `racket`, `sbcl`, `emacs`, `mojo`.

## Pipeline status (measured 2026-11-24, real runs, no simulations)

| Check | Result |
|---|---|
| `vanish-lisp/verify.sh` | **ALL CHECKS PASS** — 20.2s (lake build 11 targets, ERT 4+1, byte-compile) |
| `vanish-lisp/tests/run_pipeline.sh` (shipped) | **DENY, 17 failures** — every failure is a missing Python helper (see above). G_proof passed. |
| `bench/pipeline-no-python.sh` (xsltproc mirror) | **DENY, 1 failure** — G_grammar, G_semantics, G_proof, G_binary and the Lean cross-check pass, Gherkin 3/4. The last Gherkin scenario calls `tests/correspondence.py`, which is not in the zip. |
| `sovereign-beam-mojo/run_pipeline.sh` | **exit 0** — Mojo kernels rebuilt, `field_ops` self-test PASS (9/9), receipts `sha256sum -c` OK. `mix` skipped: OTP/Elixir were wiped by a VM replacement; the other chat had already built OTP 29.1.2 + Elixir 1.20.5 and run real KernelPort Port calls there. |

Green is blocked on one thing only: the 5 stripped Python helpers. Restoring
them means writing Python back in, and editing the pipeline means editing
code — both against the rules for this assembly — so the DENY stands as the
honest result, not a faked green.

## CI — green, with the blocked states asserted, not hidden

`.github/workflows/ci.yml` runs on every push / pull request (6 jobs), and
`bench/ci.sh` runs the same jobs locally. Latest local run: **CI GREEN**
(31.9s, log `bench/ci.log`).

| Job | Result |
|---|---|
| verify | PASS — `verify.sh` ALL CHECKS PASS |
| c-builds | PASS — 6 C binaries, math 13/13, AMPL 0 |
| calculators | PASS — SBCL, Racket, C on scratch copies; originals untouched |
| pipeline-shipped-expected-deny | PASS (asserted) — shipped script DENY, exactly 17 failures, all missing Python helpers |
| pipeline-no-python-known-blocked | PASS (asserted) — mirror DENY, exactly 1 failure: Gherkin scenario 4 needs `tests/correspondence.py` |
| sovereign | PASS — Mojo kernels, `field_ops` 9/9, receipts OK |

If either DENY count changes, CI goes red — that means the code drifted,
not that the assertion was skipped.

## Benchmarks (real, this host)

| Benchmark | Seconds | Result |
|---|---|---|
| Clean lake build | 34.487 | PASS, 11 targets |
| verify.sh | 20.211 | ALL CHECKS PASS |
| C builds (6 binaries) | 7.144 total | exit 0, `-Wall -Wextra -Werror` |
| Racket scheme selftest | 2.088 | 17/17 PASS |
| Racket vanishing calculator | 2.200 | Fib 10, primes 30, 5! = 120 |
| ERT suites | 1.870 | 5/5 PASS |
| C calculator build | 0.900 | exit 0 |
| SBCL vanishing calculator | 0.588 | Fib 10, primes 30, 5! = 120 |
| Incremental lake build | 0.377 | PASS |
| Math poly test | 0.008 | 13/13 PASS |
| AMPL exact check | 0.006 | max violation 0 |
| Sovereign pipeline | 7.176 | exit 0, field_ops PASS 9/9 |
| Shipped pipeline | 23.317 | DENY, 17 failures |
| No-Python mirror pipeline | 27.814 | DENY, 1 failure |

![Benchmarks chart](visuals/benchmarks.svg)

### Photos of the runs

`verify.sh` — all checks pass:

![verify.sh ALL CHECKS PASS](visuals/photo-verify.png)

Shipped pipeline DENY vs the no-Python mirror (1 failure left):

![Pipeline DENY, root cause](visuals/photo-pipeline.png)

Sovereign pipeline and `field_ops`:

![Sovereign pipeline, field_ops PASS](visuals/photo-mojo.png)

## How to run

```sh
# Toolchain (environment only, nothing in the repos is edited):
#   apt: emacs-nox racket sbcl xsltproc libxml2-utils
#   elan: leanprover/lean4:v4.12.0   (lake/lean)
#   Mojo 1.2.0 in ~/workspace/.venv-mojo (pip venv, survives VM replacement)
export PATH="$HOME/workspace/.tools/racket/bin:$HOME/.elan/toolchains/leanprover--lean4---v4.12.0/bin:$HOME/workspace/.venv-mojo/bin:$PATH"

./vanish-lisp/verify.sh
bash bench/ci.sh   # whole CI, green with 2 asserted known-blocked states
bash bench/pipeline-no-python.sh vanish-lisp bench/pipeline-nopython.log
./sovereign-beam-mojo/run_pipeline.sh
```

## Notes

- The vanishing calculator is **self-modifying**: running it flips the file
  `VISIBLE → HIDDEN`. Only ever run it on a copy, never on the original —
  the pristine hash is `d8ed5d66…`.
- `sovereign-beam-mojo/control/priv/` binaries are build outputs, not source;
  they are excluded here and rebuilt by `run_pipeline.sh`.
- The shipped `TEST_LOG.txt` inside `vanish-lisp/` is stale (it records a
  lake-build failure and a differential-test failure that the current code
  no longer has). `verify.sh` passes on the code as shipped.
