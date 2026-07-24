# Rubric calibration — reference solution vs the three trials

**Question.** Does the subjective rubric separate a *shippable* solution from the
not-yet-shippable trial outputs? Ground truth (Joe): the reference solution is
shippable; the three trial solutions are not.

**Method.** Judge-only, using the **same** `host_judge.py`, the **same**
`tests/judge.toml` criteria, and the **same** judge model/settings
(`claude-sonnet-5`, one call, weighted-mean aggregation) as the three trials —
so the numbers are directly comparable. No agent run and no in-container
objective verifier: the reference repo layout predates this task's Deliverables
contract (no `/app/typecheck-example`, no `/app/typed-examples/`), so the
objective machinery does not apply and was not forced.

Reference = `jpolitz/pyret-lang` commit
`d931fab449a2f385b0900be94c377a318f8289b7` vs its parent
`043ceab4422ac5ad9479650ec1d47d23bd70b3d4`.

## Slot mapping (and the bridges it required)

The judge expects an artifact with a `DESIGN.md`, a `typed-examples/` dir, and a
`pyret-lang/` checkout it diffs against the parent. The reference's materials
were mapped in:

| Judge slot | Reference material | Caveat |
|---|---|---|
| `DESIGN.md` | `lang/TYPED-TABLES.md` (27,407 chars) | Direct, clean map. |
| `typed-examples/` | `lang/tests/type-check/tables-good/*.arr` (14, incl. `support/tablib.arr`) + `tables-bad/*.arr` (21) | **Slot-semantics mismatch:** the trials' examples are all programs that *type-check*; the reference's `tables-bad` are **negative tests meant to be rejected**. Files are prefixed `good--`/`bad--` so the judge can tell them apart, but the "examples_quality" criterion is being shown 21 must-fail programs it did not see for the trials. This plausibly *helps* the reference (more coverage on display) and is the main asymmetry to keep in mind. |
| `pyret-lang/` diff | `git diff 043ceab..d931fab` | **Bridged** (below). |

**Diff bridging.** The raw diff is 239,880 chars — over `host_judge`'s 150k cap —
and front-loaded (alphabetically) with noise, so naive truncation would cut the
*core type-checker code*. Two files were reverted/removed from the diffed tree
to make the diff represent the **implementation** the way the trials' diffs did:

- `browser-test/package-lock.json` and `lang/package-lock.json` — reverted to
  parent. Dependency-lock churn, not design substance; the trials' diffs had no
  such noise.
- `lang/TYPED-TABLES.md` — removed from the diff. It already fills the `DESIGN.md`
  slot; leaving it in the diff would **double-count the report prose** (exactly
  the inflation confound this experiment is checking for).

The bridged diff is 162,285 chars; `host_judge` truncates it at 150k. The cut
falls inside a `tables-good` *test program* (`table-empty-infer.arr`), and
everything after it is more `tables-good` programs — **all fully present in the
`typed-examples/` slot** — so no type-checker code is lost. Verified: every
`lang/src/ts-compiler/src/*.ts` file (`type-check-tables.ts`, `type-check.ts`,
`type-structs.ts`, `type-check-structs.ts`, `desugar*.ts`, `type-defaults.ts`,
`ast.ts`) is within the retained 150k.

## Scores (same rubric, same judge)

| criterion (weight) | **REFERENCE** | trial1 S5 | trial2 S5 | trial3 O4.8 |
|---|---|---|---|---|
| design_soundness (×2) | **0.85** | 0.80 | 0.50 | 0.78 |
| b2t2_alignment (×1.5) | **0.80** | 0.72 | 0.55 | 0.78 |
| core_arr_operations (×1.5) | **0.85** | 0.50 | 0.60 | 0.32 |
| limitations_honesty (×1) | 0.78 | **0.87** | 0.85 | 0.85 |
| examples_quality (×1) | **0.90** | 0.82 | 0.70 | 0.65 |
| **weighted mean** | **0.836** | 0.731 | 0.611 | 0.673 |

Report lengths (to check the length confound): trial1 50,231 chars; trial2
38,422; **reference 27,407**; trial3 17,340.

## Honest read

**Yes — the rubric separates the reference from the trials, in the right order.**
Reference 0.836 > trial1 0.731 > trial3 0.673 > trial2 0.611. The reference is
top on four of five criteria and top overall, consistent with the ground truth
that it is the shippable one.

**But the margin is moderate, not a chasm.** The reference leads the *best* trial
(trial1) by only ~0.10. A cut at ~0.75 cleanly separates the reference from all
three trials, but trial1 sits just under it — the rubric ranks correctly while
**compressing** the shippable/not-shippable gap more than the binary ground
truth would suggest. If this rubric were used as a gate, the threshold would
need care (0.75–0.80), and it would treat a strong-but-incomplete trial as a
near-miss rather than a clear fail.

**The separation is substance, not prose.** Three independent signals argue the
judge is rewarding design content over polish:
1. **No length effect.** The *longest* report (trial1, 50k) is not the winner;
   the reference (27k) beats it, and the *second-longest* (trial2, 38k) scores
   *lowest*. Score does not track length.
2. **The reference loses where it is genuinely weaker.** It scores *below* every
   trial on `limitations_honesty` (0.78 vs 0.85–0.87) — the judge did not simply
   rate the polished report higher across the board.
3. **The gap is concentrated on the task's headline ask.** The reference's big
   leads are `core_arr_operations` (0.85 vs 0.32–0.60) and `examples_quality`
   (0.90 vs 0.65–0.82) — and the reasoning cites concrete substance: it types
   `group()` at `Table<{value :: T, subtable :: Table<S>}>` and computes
   `count()`'s result schema through `build-column`/`drop`/`rename`, i.e. it
   actually types column-name-parameterised `core.arr` functions with precise
   (non-`Any`) result types, which all three trials largely punted to `Any`. Its
   `design_soundness` lead rests on a *different and more careful* choice —
   **exact schemas** with an explicit reflection argument for *why width
   subtyping would be unsound*, versus the trials' unanimous width-subtyping
   approach.

So the rubric is discriminating on the right axis (does the design precisely
type real table operations, and is its soundness argument specific), and it
does not appear to be gamed by report length or polish. Its main limitation as a
*gate* is dynamic range: shippable lands ~0.84 and a decent-but-incomplete
attempt lands ~0.73, so the usable separating band is narrow.

## Confound note on the mapping itself

The `tables-bad` negative-test programs shown in the reference's `typed-examples`
slot are a display advantage the trials did not get (their examples were only
passing programs). This would, if anything, *inflate* the reference's
`examples_quality`/coverage impression — yet even discounting that criterion the
reference still leads on the ×2 `design_soundness` and ×1.5 `core_arr_operations`
axes, so the ordering is not an artifact of the mapping.
