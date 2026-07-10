# nuprl/ilvm-self-hosting-compiler

Agents write a self-hosting compiler from MiniScheme (`environment/Scheme.md`)
to ILVM (`environment/ILVM.md`). Both language specs are shipped to the
agent; no implementation of either language is. The graded deliverable is
exactly two files:

| Path | Role |
|------|------|
| `/app/compiler.scm` | The compiler's own source, in MiniScheme |
| `/app/compiler.ilvm` | `compiler.scm`, compiled to ILVM by the agent's own compiler |

ILVM programs are textual source, so a MiniScheme compiler can emit them
using ILVM's ASCII output primitives. This makes it possible for an agent to
write a real, self-hosting compiler. The oracle does not attempt to
self-host (see below); it provides transparent partial credit instead.

## Why grade against a private reference ILVM implementation

The verifier never runs the agent's own ILVM tooling to grade the agent's
compiler. It brings its own ILVM implementation (`tests/ilvm_ref/`, vendored
from `nuprl/plbench`'s `ilvm-interpreter` reference solution, never copied
into the agent's image) and uses *that* to run `compiler.ilvm` and everything
it produces. This decouples "is the compiler correct" from "is the agent's
own interpreter correct" — an agent whose interpreter and compiler have
matching, canceling-out bugs would otherwise look self-hosting under its own
tooling while actually being wrong.

## Self-hosting check: behavioral, not textual

We do not require `compiler.ilvm` to reproduce itself byte-for-byte when
recompiling `compiler.scm` (that's a much stronger and more fragile property
than "self-hosting" needs to mean, and would constrain how the agent's
codegen is allowed to work, e.g. no gensym-style naming that could vary
between runs). Instead: recompile `compiler.scm` using `compiler.ilvm` to get
`compiler2.ilvm`, then compile *and run* a battery of test programs through
both `compiler.ilvm` and `compiler2.ilvm`, and require identical observable
behavior (same output, same success-vs-abort outcome) from both. A compiler
that fails on everything doesn't pass this vacuously — both sides must
actually succeed and agree, not merely fail identically. See
`tests/test_suite.py`'s per-example loop.

## Scoring

`tests/test_suite.py` computes two independent sub-scores over the same
battery of test programs under `tests/examples/`:

- **correctness**: fraction of test programs where compiling with
  `compiler.ilvm` and running the result under the reference ILVM
  implementation produces the exact expected output (hand-verified against
  `Scheme.md`'s semantics, hardcoded in `EXPECTED` — this is ground truth
  computed independently of any agent artifact, so a bug in a test fixture
  can't masquerade as an agent failure the way it did in `scheme-typeinf`
  before that was fixed).
- **self-hosting**: fraction of the same test programs for which
  `compiler.ilvm` and `compiler2.ilvm` (see above) agree.

`reward = 0.5 * correctness + 0.5 * self_hosting`. There's no hard gate that
zeroes the whole score on one failure — the test battery mixes easy
(arithmetic, recursion) and hard (closures, `let`/`letrec`, vectors) programs
precisely so partial credit is informative.

## Oracle (`solution/`): a real compiler, but not a self-hosting one

Writing a genuinely self-hosting compiler for this oracle — one written in
MiniScheme, capable of compiling itself — is a substantial undertaking (it
means implementing closures, recursion, and heap-based data structures using
only what a from-scratch bootstrap compiler can lean on). We didn't do that.
Instead, `solution/compile_scheme_to_ilvm.py` is a real MiniScheme → ILVM
compiler — real tokenizer, real parser, real codegen (closures via
heap-allocated frame chains, an explicit call stack and value stack since
ILVM itself has neither, recursion, `let`/`letrec`, lists, strings, vectors)
— written directly in Python rather than in MiniScheme. It is deliberately
*not* self-hosting, and doesn't pretend to be.

`solution/compiler.scm` is a trivial stub (never actually run) that carries
a long, non-guessable marker string, `ORACLE_MARKER` in
`tests/test_suite.py`. `solution/solve.sh` copies that stub pair into
`/app/{compiler.scm,compiler.ilvm}` (satisfying the "both files must exist"
contract) and drops the real Python compiler at
`/app/.oracle_fallback_compiler.py`. The verifier has exactly one branch on
this marker, clearly documented at the top of `tests/test_suite.py`:

- **Marker present**: `self_hosting` is scored `0.0` outright — not skipped,
  not free credit, an explicit admission that this submission isn't
  self-hosting. `correctness` is graded by invoking the fallback Python
  compiler instead of running `compiler.ilvm`.
- **Marker absent** (any real agent submission): graded exactly as described
  above, no special-casing at all.

This nets the oracle a `0.5` reward (`correctness=1.0`, `self_hosting=0.0`)
— real, verifiable partial credit, consistent with the "lame oracle" pattern
used elsewhere in this repo (e.g. `typewhich`, `scheme-typeinf`), just
achieved through an admitted-non-self-hosting compiler rather than a
feature-limited one.

**Known risk, accepted deliberately:** if a real agent discovers the exact
oracle marker string (e.g. by having seen this repository) and pastes it into
`compiler.scm`, it gets the oracle's full `0.5` reward without building
anything. The marker is a long, effectively non-guessable token, making
accidental collisions astronomically unlikely; the residual risk is
deliberate reuse by an agent that has seen this file.
