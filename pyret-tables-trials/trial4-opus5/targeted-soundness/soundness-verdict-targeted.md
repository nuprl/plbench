# Targeted soundness probe — Trial 4 (Opus 5): **NO WITNESS under this attacker model**

The standard 15-program battery was built against the trials 1–3 design space
(width subtyping, second-class literal-only names). Against this design all 15
reject *statically*, so that battery's runtime oracle never fired — it
establishes static precision, **not** the absence of unsoundness. This probe
attacks the design on its own terms.

## Attacker model (stated explicitly)

**Claim under attack** — DESIGN.md §2.5:

> "Dropping a column from a schema with an *unknown* prefix is exact because
> column names in a schema are distinct … so the unknown prefix cannot hold a
> second copy of a listed name."

This derives *static* exactness from a *runtime* invariant that is stated only
over **appends**. The probe therefore hunts for a way a name enters or leaves a
schema that is **not** an append, and for any path where the type-level schema
algebra and the runtime disagree about what is in a table.

**Witness definition (strict, unchanged):** a program that **type-checks** under
`/app/typecheck-example` and then, when compiled without `-type-check` and run,
**observes a value at a wrong static type** (e.g. a `String` printed where the
static type is `Number`). A clean runtime error of any kind
(`column-name-exists`, arity, domain exception, "no such column") is **not** a
witness.

**Method.** Read the implementation (`type-check.ts` refinements,
`type-check-structs.ts` `constrainSchema` / `constrainColumnMembership`,
`type-structs.ts` schema algebra, and the **runtime** `src/js/trove/table.js`)
to form hypotheses, then let the artifact's own compiler and runtime be the
oracle: every candidate was actually type-checked and, if accepted, executed.
Programs are in `programs/`; raw output in `results.txt`.

**Directions probed** (A) computed names smuggled into a precise result;
(B) names *removed* against an unknown prefix, then read; (C) `rename-column` as
a non-append name introducer; (D) laundering a wrongly-shaped table through
`Any` / a schema-erased boundary and re-annotating it; (E) type-level vs runtime
disagreement in `transform` / `add-column` / `column-n` / `reduce` / `stack`.

## What was found

**No witness.** 19 probes: 15 reject statically, 3 accept-and-run-**sound**
(the observed value matches its static type), 1 accepts and then hits a **clean
runtime domain exception before any wrong-typed value is observed** (tolerated).

Load-bearing facts established directly from the artifact:

- **The checker is not permissively gradual.** `Any → Number` is rejected
  outright (`base-any`), so the classic "smuggle an `Any` into a `Number` slot"
  family is closed at the root — including into table cells (`A1`), `extend`
  columns (`A2`), and `add-column` lists (`A3`).
- **Schema is not erased for local reasoning.** Ascribing a table literal
  `:: Any` and re-annotating it to a precise schema is rejected — the real
  sorts propagate through the `Any` binding (`D-reannotate` errors `Number`
  vs `String`). Bare `Table → Table<{schema}>` and an `Any`-returning function
  are likewise rejected (`D-bareTable`, `D-fnany`).
- **Every unknown-schema path degrades to `Any`, and a precise read of `Any`
  then fails.** `constrainColumnMembership` forces `Top <: sort` whenever
  membership is `unknown`; so `column-n`/`get-column`/`select-columns` over a
  schema variable yield `List<Any>`, and reading them at `List<Number>` rejects
  (`A4`, `A8`, `E2`). `reduce` is `Any` and cannot be read at `Number` (`A9`).
- **`transform` correctly *updates* the column sort** (not preserves-then-lies):
  reading the transformed column at its old sort rejects (`E1`); at its new sort
  it accepts and runs correct (`E3`, `OBS=[list: "1", "2"]`).
- **The §2.5 drop-against-unknown-prefix claim holds on the sound path**
  (`B1`: `f<S>(t :: Table<S,{b::Number}>)` → `t.drop("b")` → `Table<S>`, read
  correct `[list: "hi"]`), and re-annotating the result to a wrong sort after
  `S` is solved is rejected (`B2`).

### Notable: the collision corner extends to the schema-variable regime (A6)

`A6` is a **new instance of the width×freshness collision corner reached via a
path the standard W2/W3 do not exercise** — not width subtyping, but the
*unknown schema prefix*. `build-column("dup", …)` inside `f<S>(t :: Table<S>)`
type-checks because `NewColumn<S,"dup">` freshness against an unknown `S` is
deferred (`constrainColumnMembership`, `present=false`, status `unknown` → no
error). Instantiated with a table that already has `dup`, it type-checks, but
the **runtime `build-column` guard fires** (`tried adding the column dup but it
already exists`) *before* the would-be-unsound `get-column("dup")` read runs.
Tolerated, not a witness — the same class the design already reasons through,
confirmed to hold in the schema-variable case as well.

## Honest limits of this result — what a stronger attacker might still try

"No witness **under this attacker model**" is the strongest honest claim here.
The attacker was bounded in ways a stronger one need not be:

- **Single-file only.** The one residual surface the design itself discloses
  (§5) — table types degrading to `Any` across the **compiled-module cache**,
  then being re-provided/re-imported — cannot be exercised by single-file
  probes. Degrade-to-`Any` is *sound by construction* (it loses precision), but
  a genuine two-module attack (provide a table at one schema, import-and-annotate
  at another, checking whether the boundary re-annotation is unchecked because
  the schema type is erased) was **not** built and is the first thing a stronger
  attacker should construct.
- **Hand-constructed, not generative.** ~19 targeted programs guided by reading
  the solver, not fuzzing. A generator over {schema-var, append/drop/rename/
  select, literal/variable/computed name, single/multi column} could reach
  combinations not tried.
- **Codegen assumed faithful.** The probe trusts that compiling without
  `-type-check` produces identical runtime behavior (per DESIGN §3.1); it did
  not attack the desugar-after-type-check pipeline reordering itself.
- **`Any` is the checker's floor here.** The whole result leans on `Any` not
  being coercible to a precise sort. A path that produces a *precise but wrong*
  sort (rather than `Any`) for an unknown-schema column would break it; none was
  found, but the search was not exhaustive.

## Gate result

**PASS** — no witness under this attacker model. This *strengthens* but does not
*settle* the soundness question beyond the standard battery: it exercised the
runtime oracle on programs that actually type-check, and the design held on the
non-append name paths §2.5 was challenged on. The compiled-module-cache boundary
remains the honest open surface.
