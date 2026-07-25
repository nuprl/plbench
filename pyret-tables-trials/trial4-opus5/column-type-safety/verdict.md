# Round-3 targeted probe — Trial 4 (Opus 5): are `Column`/`NewColumn` safe as user-writable annotations?

## Attacker model (stated explicitly)

`Column` and `NewColumn` live in `compile-structs.ts` as **global type names**, so
ordinary user code may write them in annotations — not just the built-in method
types. The asymmetry under attack:

- `Column<S,C,T>` is a **positive** claim (`c ∈ header(S)` at sort `T`), and its
  consumers **read**: `get-column : (Column<S,C,T> -> List<T>)`,
  `get-value : (Column<S,C,T> -> T)`. A **vacuous positive claim yields a
  wrong-typed value with no runtime guard in the path** — `get-column` on a
  column that really exists does not error, it returns the wrong thing. That is
  the witness shape.
- `NewColumn<S,C>` is a **negative** claim whose only consumer is an append, so
  a vacuous `NewColumn` costs at most a clean runtime error (settled last round,
  A6 — **not** re-probed here).

**Witness definition (strict, unchanged):** type-checks, then a value observed at
a **wrong static type** at runtime. A clean runtime error of any kind — including
an internal "Abstraction breaking" crash — is **not** a witness.

**Method:** read the solver (`constrainColumnMembership`, the `t-column` /
`t-col-name` / `String`→`Column` subtyping cases, line refs below), form
hypotheses, then use the artifact's own compiler+runtime as oracle. Every
candidate was type-checked and, if accepted, **executed**. Programs in
`programs/`; raw output in `results.txt`.

## Primary result — the positive claim is DERIVED, not asserted: **NO WITNESS**

A hand-written `Column<S, Number>` on a parameter does **not** let a user assert a
sort the checker cannot see. The obligation is discharged at the **concrete call
site**, where the schema is known and the real sort is looked up and checked:

- **P1** `fun rd<S>(t :: Table<S>, c :: Column<S, Number>) -> List<Number>:
  t.get-column(c)` — the **body defines fine** (`P1def` accepts: it trusts `c`),
  but every **call** `rd(animals, "name")` on a `String` column is **rejected**
  (`String <: Number` fails). Same for `get-value` (**P2**) and the 3-parameter
  `Column<S, C, Number>` (**P3**).
- **P4** a name absent from the table, with a claimed sort, is rejected with a
  named error: *"The table does not have a column named `nonexistent`."* The call
  site checks **membership**, not just sort.

**Why (code).** `constrainColumnMembership` (type-check-structs.ts:935): when the
schema is unknown it adds `Top <: sup.sort`. If `sup.sort` is an inference
variable (the *method* types' `∀T`) it solves to `Top` → `List<Any>` (sound
degradation). If `sup.sort` is a **concrete** type a user wrote (`Number`), the
constraint is `Top <: Number`, and the solver's `t-top` case
(type-check-structs.ts:1098) makes `Top <: <non-Top>` a **`TypeMismatch`**. So a
concrete sort simply cannot be asserted against an unknown schema — only `Any`
survives.

### Direct answers to Q1 / Q2

- **Q1 — `NewColumn` freshness against a *rigid* schema variable is discharged
  VACUOUSLY** (confirmed in code). `constrainColumnMembership`, `present=false`,
  `sch === undefined` → `default` branch adds only `Top <: sort`, **no freshness
  error**; and because a rigid `∀S`-body is generalized once, it is **not**
  re-checked per call (this is exactly why A6 type-checks even when called with a
  colliding table). It is safe **only** because `NewColumn`'s consumer is a
  runtime-guarded append.
- **Q2 — `Column` membership against a rigid prefix is NOT dangerously vacuous.**
  Same code path, but for the *positive* read: an inference-variable sort
  degrades to `Any` (`Top <: ?T` ⇒ `?T = Top`), and a **concrete** sort is
  **rejected** (`Top <: Number` fails). So `get-column` inside a
  schema-polymorphic function does **not** blindly trust a concrete sort — the
  wider surface Q2 worried about does not exist. This is the precise reason the
  positive/negative asymmetry does **not** become a witness.

## Secondary — subtyping laundering between the constructors: all closed

- **P5** `NewColumn<S,C> <: Column<S,C,T>` — **rejected**. `Column <: Column`
  requires equal `present` flags (type-check-structs.ts:1226); a freshness claim
  cannot be converted to a presence claim.
- **P6a** a **non-literal `String` variable** passed as `Column<S, Number>` —
  **rejected**. `NAME-STR` (type-check-structs.ts:1060) sets `Top <: sort`;
  against a concrete `Number` that is `Top <: Number` → fail. **The `Any` floor
  holds** — the single most important negative result here.
- **P6b** round-trip `Column → String → Column<S, Number>` — **rejected** (same
  `Top <: Number`). **P7** aliasing (`type NumCol = Column<…, Number>`) does not
  erase the constraint to its head — still checked.

## Tertiary — the `C` binding escaping its append justification: closed

- **P9a** append with a wrong sort while the return type claims `Number` —
  **rejected** (`String <: Number`). **P9c** append a *different* name than `C` —
  **rejected**. **P10** two `NewColumn` args sharing one `C`, passed different
  names — **rejected**. The return schema is tied to an actual, correctly-typed
  append; it cannot be faked.

## Full classification (19 probes + 10 delivered examples)

- **Reject-statically:** P1, P2, P3, P4, P5, P6a, P6b, P7, P9a, P9c, P10, M5.
- **Accept + run sound:** P1def, M3, M4.
- **Accept + internal crash (not a witness — see below):** M1, P9b, P10b.
- **Witnesses (accept + wrong-typed value observed): 0.**

## Incidental but SEVERE: the marquee annotations crash at runtime

Not a soundness witness — but it must be stated plainly. The `Column`,
`NewColumn`, and `{C; T}` (column-named-by-type-variable) forms compile to **no
runtime annotation object** (`undefined`), yet the code generator still emits a
`_checkAnn` for any function argument/return carrying them. `isCheapAnnotation`
(runtime.js:2703) is literally `return ann.flat`, so on `undefined` it throws
`TypeError: Cannot read properties of undefined (reading 'flat')` —
*"Abstraction breaking: Uncaught JavaScript error"*.

Consequence, measured by **running the agent's own 10 delivered examples**
end-to-end (Part B of `results.txt`):

| runs clean (5) | crashes on execution (4) | self-guarded (1) |
|---|---|---|
| b2t2-example-tables, b2t2-p-hacking, b2t2-quiz-scores, b2t2-table-api, table-syntax-forms | **b2t2-dot-product, b2t2-group-by, core-summary-stats, core-table-helpers** | load-table-annotations (`raise("only type checked, not run")`) |

The four crashers are the ones whose functions carry `Column<S,C,T>` /
`Column<S,Number>` / `{C; T}` parameter or return annotations. They include
**`b2t2-group-by` and `core-summary-stats`** — the two examples this trial's
grading cited as the decisive evidence for the design's headline differentiators
(schema-polymorphic group-by, and typing `core.arr`'s `mean(t, col)` as
`col :: Column<S, Number>`). `Table<S>` (M3) and concrete `Table<{…}>` (M4) run
fine; the defect is specific to the type-level-only column-name machinery in a
runtime-checked position.

**Why every grader missed it.** `typecheck-example`, the objective verifier's
`examples:type-check` check, the subjective judge (reads source, does not run),
and the agent's own `table-type-test.js` driver (`typeCheckFile`, `typeCheck:
true, checks: 'none'`) **all only type-check**. DESIGN §0's claim that
`ts-table-type-test` "runs every program in `/app/typed-examples`" is inaccurate:
the driver type-checks them. So objective reward=1 and subjective 0.885 were both
awarded to a design whose flagship examples do not execute. The agent partially
knew this — it hard-guarded `load-table-annotations` with an explicit "only type
checked, not run" raise, but not the other four.

**Relation to soundness.** This does not manufacture a witness: the broken check
always *crashes*, never silently mis-accepts, and the static checker independently
prevents wrong-typed values from reaching these positions (Part A). The soundness
verdict therefore stands. But it sharply qualifies "the design *delivers* these
capabilities": it **type-checks** first-class column names and schema
polymorphism; it does **not** run them.

## Honest limits of this result

- "No witness **under this attacker model**." The primary/secondary/tertiary
  probes are hand-constructed from reading the solver, not exhaustive; a
  generator over {rigid vs existential schema, literal/variable/computed name,
  concrete vs inference-var sort, single/multi column} could reach untried
  combinations.
- The runtime-crash finding was reached with the standalone `build-runnable`
  pipeline. It reproduces on the agent's own examples with the same flags that
  run other examples cleanly, and localizes to `isCheapAnnotation` reading a
  `undefined` annotation — but a full root-cause in the annotation-compilation
  pass was not written.
- The cross-module compiled-cache boundary (round 2's open surface) remains
  un-probed here.

## Gate result

**Soundness gate: PASS** (no witness under this attacker model). The positive
`Column` claim is checked at instantiation, not asserted; the `Any` floor holds
against concrete-sort assertions; the constructor-subtyping and `C`-escape paths
are closed. **Separately flagged, non-gating: a severe runtime robustness defect**
— 4 of 10 delivered examples, including the two headline ones, crash on execution,
invisibly to every type-check-only grader.
