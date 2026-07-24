# Adversarial soundness battery — all three trials

**Gate model.** Soundness is a multiplicative gate that fires only on a
**witness**: a program that *type-checks under the submitted checker* but at
runtime produces genuine **type confusion** — a wrong-typed value *observed at a
static type* (e.g. a `String` seen where the static type is `Number`), with **no
runtime error**. A merely well-defined runtime error (a domain exception Pyret
raises by design) does **not** count — Pyret tolerates those. Judge doubt does
not zero; a witness does.

**Method.** For each program and each artifact: (1) type-check it with the
submitted `/app/typecheck-example`; (2) if accepted, compile it **without**
`-type-check` (runtime codegen is identical) and **run** it, observing whether a
wrong-typed value is printed (witness), a clean runtime error occurs (tolerated),
or it runs correctly (sound). Harness: `harness.sh`. Programs: `programs/`.

## Adaptations (documented per the ask)

- **`List.first` is untypable in all three checkers** (field access `lst.first`
  is rejected as "List<…> does not have a field named `first`", independent of
  table logic). Every observation was therefore rewritten to avoid it — using
  `to-repr` on the whole `get-column(...)` list, or `row-n(0).get-value(...)` /
  bracket access for a single cell. This adaptation is uniform across all three
  (not design-specific) so comparability holds.
- **No design-specific syntax adaptation was needed.** All three accept the same
  `Table<{col :: Ann, ...}>` annotation syntax and the same table vocabulary
  (`table:`, `select…from`, `transform-column`, `build-column`, `add-column`,
  `rename-column`, `drop`, `stack`, `row-n`, `get-value`, `["col"]`). Where the
  designs differ it is **accept-vs-reject** (a precision difference), and every
  ACCEPT was run to confirm the runtime outcome.
- **Pivotal runtime fact** (established directly): Pyret's runtime `add-column`
  onto an existing column raises `column-name-exists`, and `rename-column` /
  `transform-column` onto an existing name raises "new name already exists".
  These are clean domain exceptions — so the width×collision corner, even when it
  type-checks, is tolerated, not a witness.

## Results matrix (TC = type-check; → = runtime outcome when accepted)

| probe | targets | Trial 1 (S5) | Trial 2 (S5) | Trial 3 (O4.8) | witness? |
|---|---|---|---|---|---|
| R1 get-column missing | column existence | REJECT | REJECT | REJECT | no |
| R2 post-drop access | schema tracking | REJECT | REJECT | REJECT | no |
| R3 wrong-sort arg | depth / sort | REJECT | REJECT | REJECT | no |
| W1 cell vs header ann | literal cell check | REJECT | REJECT | REJECT | no |
| W1b cell via get-value | literal cell check | REJECT | REJECT | REJECT | no |
| **W2 add-column collision** | **width × freshness** | ACCEPT → `column-name-exists` | ACCEPT → `column-name-exists` | ACCEPT → `column-name-exists` | **no (tolerated)** |
| **W3 rename collision** | **width × freshness** | ACCEPT → "name already exists" | ACCEPT → "name already exists" | ACCEPT → "name already exists" | **no (tolerated)** |
| W4 depth mismatch | depth subtyping | REJECT | REJECT | REJECT | no |
| D2 transform-retype→num | sort tracking | REJECT | REJECT | REJECT | no |
| D3 build-column sort | new-column sort | REJECT | REJECT | REJECT | no |
| F1 select-dropped col | select recovery | REJECT | ACCEPT → "no column `b`" | ACCEPT → "no column `b`" | no (tolerated) |
| F2 drop-then-select col | chained recovery | REJECT | REJECT | ACCEPT → "no column `b`" | no (tolerated) |
| F3 bracket after retype | getBracket sort | REJECT | REJECT | REJECT | no |
| F4 stack mismatch | stack contract | ACCEPT → "different column sizes" | ACCEPT → "different column sizes" | REJECT | no (tolerated) |
| F5 empty-table infer | empty schema sort | REJECT | REJECT | REJECT | no |

## Per-trial verdict

- **Trial 1 (Sonnet 5): NO WITNESS.** Every schema/sort error is caught
  statically except the width×collision corner (W2/W3) and `stack` mismatch
  (F4), which type-check and then raise clean runtime domain exceptions. The
  most statically precise of the three (rejects F1/F2 at compile time).
- **Trial 2 (Sonnet 5): NO WITNESS.** This was the prime suspect (schema
  reverse-engineered from desugared primitives; judge scored its soundness
  argument 0.50). Its recovery is looser on `select` results (F1 accepted →
  runtime error) but never fabricates a wrong sort: cell checks (W1/W1b),
  depth (W4), transform/build sort tracking (D2/D3), and bracket (F3) all reject
  statically, and its precise claims are all derived from statically-checked
  expressions, so no wrong-typed value is ever observed. Its `get-column` is
  `List<Any>` (imprecise but sound). No witness.
- **Trial 3 (Opus 4.8): NO WITNESS.** Its partial structure recovery (methods +
  table literals precise; sugar loose) means `select`/`drop` existence errors
  land at runtime (F1/F2 accepted → clean error), but it is the *most* precise
  on `stack` (F4 rejected statically). Cell, depth, sort-tracking, and bracket
  probes all reject statically. No witness. (Minor quality nit: the `extend`
  error path renders a raw internal AST object rather than a user message; still
  a rejection, not a soundness issue.)

## What the divergences show

The three designs draw the **static/dynamic boundary in different places** — Trial
1 catches select/drop-existence statically but defers `stack`; Trial 3 defers
select/drop-existence but catches `stack` statically; Trial 2 is in between. Every
boundary is **sound**: on the dynamic side of each design's line sits a clean
Pyret domain exception, never a wrong-typed value. The width×add-column/rename
collision corner Joe flagged is, concretely, in the tolerated class for all three
(runtime `column-name-exists`).

## Summary: gate architecture applied to the cohort

| trial | objective gate | soundness gate (witness) | subjective |
|---|---|---|---|
| Trial 1 — Sonnet 5 | PASS (reward 1.0) | PASS (no witness) | 0.731 |
| Trial 2 — Sonnet 5 | PASS (reward 1.0) | PASS (no witness) | 0.611 |
| Trial 3 — Opus 4.8 | PASS (reward 1.0) | PASS (no witness) | 0.673 |
| *(reference, calibration)* | n/a (predates contract) | not run | 0.836 |

Under the proposed architecture (final score = objective_gate × soundness_gate ×
subjective), none of the three soundness gates fire, so each trial's score is its
subjective score — 0.731 / 0.611 / 0.673 — cleanly below the reference's 0.836.
The gate did its job by *not* firing on designs that are genuinely sound (no false
witness), including on the exact collision corner that motivated it.
