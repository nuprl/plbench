# plbench/pyret-typed-tables

Retrofit sound **static type checking for tables** onto Pyret's TypeScript
compiler, aligned with the B2T2 table-types benchmark. This is an open-ended
language-design task: the agent invents the type syntax and rules, implements
them in the type checker, and reports on the design.

## Layout

- `instruction.md` — the task prompt (a "What Is Provided" orientation, the
  design brief, and the deliverables contract).
- `environment/`
  - `Dockerfile` — clones `jpolitz/pyret-lang` at the fixed parent commit
    `043ceab4422ac5ad9479650ec1d47d23bd70b3d4` and builds both backends so the
    agent starts from a working tree.
  - `b2t2-paper.txt` — vendored text of arXiv:2111.10412 (the B2T2 paper).
  - `core.arr` — vendored Bootstrap `core.arr` library.
- `tests/`
  - `test.sh` / `verifier.py` — the **objective** grader (runs in-container,
    needs no credentials); writes `/logs/verifier/reward.txt`.
  - `probes/good`, `probes/bad` — design-agnostic well-typed / ill-typed Pyret
    programs (no table syntax) used to detect a globally vacuous type checker.
  - `probes/table-bad` — a minimal table-soundness probe using Pyret's fixed
    table surface syntax (a `table:` literal + `.get-column`) that reads a
    column absent from a statically known schema (B2T2's canonical wrong-column
    error). A checker that types tables as `Any` accepts it; any real
    schema-tracking design rejects it — so it catches a submission that passes
    everything else while doing no real table typing. Kept deliberately minimal
    (one `get-column`-existence probe): table typing admits many sound-but-
    imprecise choices, so deeper table-soundness is left to the rubric + audit.
  - `judge.toml` — the **subjective** rubric (single source of truth for the
    criteria).
  - `host_judge.py` — host-side rubric grader for credential-light VMs.

## Deliverables the agent must leave in `/app`

1. A built, modified TypeScript compiler (existing suites still pass).
2. `/app/typecheck-example FILE.arr` — exit 0 iff `FILE.arr` has no type error.
3. `/app/typed-examples/*.arr` — non-trivial, type-checking table programs.
4. `/app/DESIGN.md` — the design report.

## Grading

**Objective** (`verifier.py`, binary reward): deliverables present; the compiler
rebuilds; the pre-existing `ts-type-check-test` regression suite still passes
(the main defense against gutting the checker — it ships must-reject programs);
the design-agnostic probe suite behaves correctly under the agent's own
`typecheck-example` (well-typed accepted, ill-typed rejected — catching both
accept-everything and reject-everything wrappers); the table-soundness probes
are rejected (missing-column programs — catching a checker that types tables as
`Any`); and every typed example type-checks and exercises real table
vocabulary.

**Subjective** (`judge.toml`, LLM-as-judge): reads `DESIGN.md`, the typed
examples, and the agent's diff, scoring design soundness, B2T2 alignment,
ability to type realistic `core.arr` operations, honesty of the limitations
report, and example quality.

The subjective rubric is graded two interchangeable ways from the **same**
`judge.toml` criteria:

- **RewardKit / LiteLLM** where model credentials exist:
  `rewardkit /tests/judge.toml`.
- **`host_judge.py`** on hosts that only have a Claude Code OAuth token: it
  parses `judge.toml` and grades with one headless `claude -p` call against the
  downloaded artifact, so no `ANTHROPIC_API_KEY` is needed and the token never
  enters the container.

## Notes

There is deliberately **no oracle solution** committed: the objective verifier
runs the agent's own compiler, and the trust gap (an agent could try to make
the checker vacuously accept everything) is closed by the regression suite, the
probe suite, and the LLM rubric + audit rather than by comparison to a reference
implementation.
