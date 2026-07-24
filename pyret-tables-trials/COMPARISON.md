# Comparative design analysis — Pyret typed tables (3 trials)

Three independent Claude Code runs on the identical hardened task (same
`instruction.md`, high reasoning effort, `-type-check` TypeScript compiler):

| | Trial 1 | Trial 2 | Trial 3 |
|---|---|---|---|
| Model | Sonnet 5 | Sonnet 5 | Opus 4.8 |
| Agent wall-clock | 2h23m | 1h42m | 55m |
| Compiler diff | +1413 | +443 | +673 |
| Typed examples | 6 | 6 | 8 |
| **Objective** | **1.0** | **1.0** | **1.0** |
| **Subjective** (wtd mean) | **0.731** | **0.611** | **0.673** |
|   design_soundness (w2) | 0.80 | 0.50 | 0.78 |
|   b2t2_alignment (w1.5) | 0.72 | 0.55 | 0.78 |
|   core_arr_operations (w1.5) | 0.50 | 0.60 | 0.32 |
|   limitations_honesty (w1) | 0.87 | 0.85 | 0.85 |
|   examples_quality (w1) | 0.82 | 0.70 | 0.65 |

(Objective note: Trials 2 and 3 first scored 0 in-container from two
now-removed over-strict table probes — a positive probe assuming `get-column`
element-type precision, and a `select`-missing probe. Both were verifier false
negatives against legitimately sound designs; see "Verifier lessons" below.
All three solutions genuinely satisfy the objective floor: real schema-tracking
checker, the regression suite passes, and `get-column` of a column absent from
a known schema is rejected.)

## The headline: strong convergence on the core, divergence on completeness

**They converged on essentially the same type system.** With no shared context,
all three independently chose:

- **Record-schema table/row types** — `Table<{col :: Ann, ...}>` /
  `Row<{...}>` — reusing Pyret's *existing* generic-application (`Name<...>`)
  and record-annotation syntax, with **no grammar change**. A new internal
  `Type` variant carrying a `column → Type` map (none reused `TRecord`
  directly, all for the same reason: tables need distinct nominal identity and
  different method behaviour).
- **Width subtyping** as the core relation (axis i) — *not* exact schemas and
  *not* row-variable polymorphism.
- **Literal-string column names** at method call sites (axis ii), precise when
  the name is a literal and degrading to `Any`/opaque otherwise — the
  load-bearing "leave untypable, not unsound" fallback that keeps `core.arr`'s
  `fun mean(t :: Table, col :: String)` style compiling.
- **Bare `Table`/`Row` = opaque/`Any`-equivalent** for legacy and
  external-source data, which must be annotated before precise use.
- **Row polymorphism named as the principled, unimplemented next step** — all
  three explicitly identify `Table<{c :: T | R}>` with a rest-variable as the
  design they stopped short of, and use width subtyping as its practical proxy.

The divergence is almost entirely about **how completely each recovers table
structure after Pyret desugars it**, which drives precision and the subjective
spread. Details per axis follow.

## (i) Subtyping choice and how it is kept sound

All three use **width subtyping** (a table with more columns is usable where
fewer are required), implemented by reusing Pyret's existing record-width
subtyping path against the schema map.

- **Trial 1** drops **column order** from a table type's identity as a
  considered choice (its `key()` sorts columns, like `TRecord`): the paper
  requires order for *presentation*, not typing, and honouring it would
  needlessly reject column-reordering and reordered annotations.
- **Trial 3** is the only one to state **width + depth** (covariant column
  types) explicitly, and gives the cleanest soundness argument: tables/rows are
  immutable, so reading through a narrower view is safe; operations that need
  the exact column set (`stack`, `add-row`) require schema **equality**.
- **Trial 2**'s rule is the leanest, defined as `checkSubSchema` mirroring the
  pre-existing `t-record` width rule, with an explicit "`unknown` on either
  side ⇒ unchecked" escape.

Soundness is maintained in all three by the same discipline: never *narrow* an
opaque table into a schema (you cannot invent columns), trust column element
types like `List<Number>` (dynamic, per the task's stated baseline), and fall
back to `Any`/opaque wherever the schema is not statically known.

## (ii) Column-name treatment — and its trade-off with (i)

This is where Joe's predicted (i)×(ii) trade-off shows up: **none of the three
made column names first-class/type-indexed** (no `Col<S, T>` label type). All
chose **literal-only / second-class** column names and lean on width subtyping
+ literal-string call-site rules instead. The observable difference is how
precisely each types `get-column("c")` on a known schema:

- **Trial 1 & Trial 3**: precise — `get-column(c) : List<S[c]>` for a literal
  `c` in `S` (so `ages :: List<Number> = t.get-column("age")` type-checks; a
  missing literal is a compile error).
- **Trial 2**: imprecise — `get-column` returns `List<Any>` even for a literal
  column of a known schema (the same program is *rejected*: `Number` vs `Any`).
  Trial 2 buys back column-*existence* checking but not column-*element*
  precision on this accessor.

All three collapse to `Any`/opaque when the column name is a **non-literal**
(a `String` parameter), which is exactly the `core.arr` idiom (see iv).

## (iii) Schema polymorphism

**None** implements true schema/row polymorphism (a quantified schema variable
`fun f<S>(t :: Table<S>) ...` with a rest variable). All three use **width
subtyping as the practical substitute** ("a table with at least these columns")
and each explicitly writes up row polymorphism as the principled extension it
did not build (Trial 2 §6, Trial 3 §6, Trial 1 in its alternate-designs
section). So on this axis the three are essentially identical: same choice, same
stated reason (it needs new annotation syntax for a rest variable plus
row-variable inference in the solver).

## (iv) Which `core.arr` idioms (column-name string parameters) each can type

The task's specific ask — functions like `group()`/`mean()` that take a **column
name as a `String` argument** — is the hardest case, and **all three handle it
the same way: soundly but without precision.** When the column name is a
non-literal parameter, every design type-checks the call (so `core.arr`
compiles) but yields `Any`/opaque results — the "leave untypable, not unsound"
fallback. None types a `fun group(t, col :: String)` precisely; precision is
available only when the column name appears as a *literal* at the call site.

The rubric spread on this axis reflects how much each *demonstrated* with
literal-name examples rather than a genuine capability difference:

- **Trial 2 (0.60)** — highest; its `04-core-group-and-count.arr` and
  `06-core-predict-col.arr` exercise column-name-parameterised grouping/counting
  and column-appending with precise result schemas (via literal names).
- **Trial 1 (0.50)** — mid; adapts `mean`/`median`/`sum`/`sort` but does not
  show a `group()`-by-column-name example.
- **Trial 3 (0.32)** — lowest; a single `core-table-functions.arr` types the
  helpers but covers the least `core.arr` surface.

## (v) Does the soundness argument acknowledge the width × add-column / rename hidden-column-collision corner?

This is the sharpest differentiator, and it splits by model.

- **Trial 3 (Opus): YES — explicitly and correctly.** Its §2.4 soundness
  paragraph states that because width subtyping can **hide** a column, the
  `build-column`/`add-column` freshness check (`c ∉ header(t)`) is only a
  *best-effort* static check; when a narrowed view hides a colliding column the
  worst outcome is a **runtime domain exception** ("column already exists"), not
  a value at a wrong type — "No value ever flows at a type it doesn't have." It
  even points at row polymorphism (a *closed* schema with no rest variable) as
  the way to recover static freshness.
- **Trial 1 (Sonnet): NO.** It describes `add-column`/`build-column` freshness
  (the "column already exists" error) and width subtyping in separate sections
  but never connects them — it does not observe that width subtyping makes
  freshness unverifiable in general. (Consistent with the audit of Trial 1.)
- **Trial 2 (Sonnet): NO.** Its soundness argument is the "strictly additive /
  `unknown ≤ anything`" invariant; it computes the extended schema for
  `add-column`/`build-column` but does not discuss the hidden-column collision
  under width subtyping.

So only the Opus run reasoned about this corner unprompted.

## (vi) Scores — reading the spread

- **Trial 1 (Sonnet, 0.731)** is the most **complete**: it made the biggest
  architectural move (below) and therefore types the most surface precisely,
  scoring highest on examples (0.82) and tying the honesty lead (0.87). Its gap
  is axis (v) and no `group()`-by-name demo.
- **Trial 3 (Opus, 0.673)** is the most **principled**: best soundness narrative
  (0.78, the only one to handle the collision corner) and best B2T2 alignment
  (0.78), but the leanest `core.arr` coverage (0.32) drags the weighted mean.
- **Trial 2 (Sonnet, 0.611)** is the most **minimal**: it works and is honest
  (0.85) and actually leads on `core.arr` demonstration (0.60), but its imprecise
  `get-column` and thinner soundness story (0.50) cost it.

The weighting (soundness ×2, alignment/core ×1.5) rewards Trial 1's completeness
and Trial 3's rigour over Trial 2's minimalism.

## The one real architectural divergence: where table structure is recovered

Pyret desugars `table:` / `select` / `extend` / … into primitive
`makeTable`/array operations **before** type-checking. How each run coped is the
root cause of nearly every difference above:

- **Trial 1** made "the central architectural decision" to **move table
  desugaring to run *after* type-checking** (it touches `desugar-post-tc.ts`),
  so the checker sees the real `s-table*` nodes and types **every** sugar form
  (`select`/`extend`/`sieve`/`order`/`transform`) *and* methods precisely. Most
  code, most precision.
- **Trial 2** kept pre-TC desugaring but **reverse-engineers** the schema from
  the desugared `makeTable`/select/extend **primitives** — so it still catches
  `select` of a missing column, but pays for it with an imprecise `get-column`
  (`List<Any>`).
- **Trial 3** kept pre-TC desugaring and recovers only **table *literals*** (from
  `makeTable(headers, rows)`) plus **method calls** (which survive desugaring
  intact) — so `t.get-column("nope")` is caught but `select nope from t` is
  **not** (the unknown column is typed `Any` and deferred to the runtime error:
  sound, imprecise). Trial 3 lists "desugar tables after type-checking" as the
  single biggest unrealized improvement — i.e. it *identified* Trial 1's move
  but chose not to make it, to avoid perturbing code generation.

## Verifier lessons this cohort exposed

Running three designs stress-tested the objective verifier and forced two
corrections, both instructive about the limits of an *objective* table-soundness
gate:

1. A **positive** table probe assumed `get-column` element-type precision and
   wrongly failed Trial 2 (which soundly returns `List<Any>`). Removed —
   a reject-everything checker is already caught by the design-agnostic positive
   probes and by the agent's own examples having to type-check.
2. A **`select`-missing** negative probe wrongly failed Trial 3 (whose `select`
   is sound-but-imprecise). Removed.

The surviving table probe is a single, robust check — `get-column` of a column
absent from a statically known schema, the one accessor all three designs check
and a `Table = Any` checker does not. The deeper lesson: because table typing
admits many *sound but imprecise* choices (any given operation may legitimately
defer to the dynamic `Any`), objective probes can only robustly gate the
**existence** floor; genuine table-soundness and precision are the province of
the LLM rubric and the audit, exactly as the task's design intends.
