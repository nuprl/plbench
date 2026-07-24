# Static Type Checking for Tables in Pyret — Design Report

This document explains the design and implementation of table type checking
added to Pyret's TypeScript-hosted compiler (`/app/pyret-lang/lang/src/ts-compiler/src`).
It assumes the reader has `/app/b2t2-paper.txt` and `/app/core.arr` at hand,
but has not seen the diff.

## 1. Summary of the approach

Tables in Pyret are, today, a fully opaque nominal type: `Table` and `Row`
carry no information about which columns exist or what they contain,
anywhere in either compiler. This project adds an **optional, backward
compatible column-schema layer** on top of that: a new annotation syntax
(`Table<{...}>` / `Row<{...}>`), and a **new, independent checking pass**
(`table-check.ts`) that statically tracks and verifies column names and
types wherever it has enough information to do so, while leaving every
program that does not use the new annotations to behave exactly as before.

The design is deliberately **additive, not replacement**: the pre-existing
bidirectional checker (`type-check.ts`) is left doing what it always did
(treating `Table`/`Row` as opaque), and the new pass runs *alongside* it,
contributing extra errors only when it has positive static evidence of a
column-shape mistake. A program with no table-type annotations gets zero
extra errors from this project, by construction (see §3.3).

## 2. Type grammar

### 2.1 Surface annotation syntax

```
ann ::= ... | Table<{ field (, field)* }>  |  Row<{ field (, field)* }>  |  Table  |  Row
field ::= name :: ann
```

This reuses **existing, unmodified grammar** — `Table<{...}>` parses as an
ordinary `a-app` (`Table`) applied to an ordinary `a-record` argument
(`{name :: String, age :: Number}`), exactly the same production used for
`List<Number>` and `{x :: Number}` respectively. No grammar or parser
changes were needed. Plain `Table` / `Row` (no argument) continue to mean
exactly what they mean today: an opaque table/row with no column
information.

Examples:

```
email :: Table = ...                                    # unchanged, opaque
people :: Table<{name :: String, age :: Number}> = ...  # new: known schema
row-handler :: (Row<{age :: Number}> -> Boolean) = ...  # a Row-typed param
```

### 2.2 Internal type representation

Column schemas are represented in `table-check.ts`, **not** added to the
shared `Type` union in `type-structs.ts`:

```ts
type ColumnMap = Map<string, TS.Type>;               // ordered: column order
type Schema = { tag: 'known'; columns: ColumnMap }
            | { tag: 'unknown' };                     // today's opaque Table/Row
type Val = { tag: 'table'; schema: Schema }
         | { tag: 'row';   schema: Schema }
         | { tag: 'scalar'; typ: TS.Type }
         | { tag: 'unknown' };
```

A **column's element type is a real `type-structs.Type`** — `Number`,
`String`, a user-defined `data` type, `List<Number>`, etc. — resolved via
the *existing, unmodified* `type-check.ts#toType` function. Only the outer
`Table<{...}>` / `Row<{...}>` wrapper is handled specially, in
`annToShape()`. This means column types get the full existing type
language for free: `Table<{tags :: List<String>}>` works with no extra
code.

I chose *not* to add `TTable`/`TRow` to the shared `Type` union in
`type-structs.ts` (which is a large, exhaustively-matched discriminated
union threaded through `substitute`/`freeVariables`/`equals`/`key`/
`toString`/`setLoc`/`setInferred`, and through the constraint solver in
`type-check-structs.ts`). Adding a variant there would have meant auditing
and extending every one of those switches, and — more importantly — feeding
table types into the general bidirectional checker's own unification, which
is not designed for width-subtyped, per-call-site column checking. Keeping
the representation local to `table-check.ts` confines the blast radius of
this feature to one new file plus a handful of small, targeted edits (see
§4), which was the right trade-off given the "cannot be unsound, everything
else must keep passing" constraint.

### 2.3 Type rules

Below, `Γ` is the local environment table-check.ts threads through the
program (`name -> Val`, plus a separate `name -> FuncSig` table for
`Table<{...}>`/`Row<{...}>`-annotated function signatures — see §4.2).
`sub ≤ sup` is the width-subtyping judgment (§2.4).

**Table/row literals.** `table: c1 :: A1, c2 :: A2, ... end` with rows
produces `Table<{c1 :: A1, c2 :: A2, ...}>`. An unannotated header's element
type is inferred from the *first* data row's corresponding cell if that
cell has an inferable scalar type, else defaults to `Any`. Column *names*
are always statically known from the header syntax, regardless of
annotations — this is true for `table:` and for `load-table:` alike, since
both list their columns syntactically.

```
Γ ⊢ table: c1 :: A1, ..., cn :: An  row: e1, ..., en  ...end  :  Table<{c1 :: A1, ..., cn :: An}>
```

**Column-name-checked operations.** `select`, `extract`, `order`,
`sieve`/`filter` (`using` clause), `extend` (`using` clause), and the
method-style equivalents (`.select-columns`, `.drop`, `.rename-column`,
`.get-column`/`.column`, `.filter-by`, `.order-by`/`.order-by-columns`,
`.row.get-value`/`.get`, and bracket access `r["col"]` with a literal
string) all check the referenced column name(s) against the operand's
`Schema`, when it is `known`:

```
Γ ⊢ e : Table<{..., c :: T, ...}>                    Γ ⊢ e : Table<{...}>   c ∉ columns
────────────────────────────────────── (found)      ─────────────────────────────────── (not found)
Γ ⊢ select c from e end : Table<{c :: T}>            Γ ⊢ select c from e end : ERROR TableTypeColumnNotFound
```

When the operand's schema is `unknown`, no check is performed and no error
is produced (see §3.3) — this is the "leave it dynamic" fallback.

**Column-appending operations.** `extend` (per-field form), `.build-column`,
`.add-column` compute a new schema = old columns, with the new
name/type appended, **after checking the new name is not already present**:

```
Γ ⊢ e : Table<{cols}>     name ∉ cols     Γ ⊢ body : T (declared ann, or inferred)
──────────────────────────────────────────────────────────────────────────────────
Γ ⊢ e.build-column(name, lam(r): body end) : Table<{cols, name :: T}>

Γ ⊢ e : Table<{cols}>     name ∈ cols
────────────────────────────────────────────────────── ERROR TableTypeDuplicateColumn
```
This mirrors the *existing* type rule for record extension (`x.{y: 5}`,
`synthesisExtend` in `type-check.ts`) which computes a new `TRecord` = old
fields ∪ new fields — table-check.ts's `build-column`/`add-column`/`extend`
rules are the same idea specialized to tables.

When `build-column`'s/`transform-column`'s/`filter`'s callback is a bare,
*unannotated* `lam`, its single parameter is automatically given type
`Row<{cols}>` (build-column/filter) or the target column's element type
(transform-column) from the receiver's own known schema — no annotation
required on the callback parameter itself. This is a genuine ergonomic
win over having to write `lam(r :: Row<{...}>): ...` everywhere.

**Column-removing/renaming operations.** `.drop(name)` requires `name` present,
result = columns minus name. `.rename-column(old, new)` requires `old`
present and `new` either equal to `old` or absent, result = columns with
`old` renamed to `new` (**order preserved**).

**Row access.** `r["col"]` (a literal string key) on a `Row<{..., col :: T,
...}>` has type `T`; on a missing column, `TableTypeColumnNotFound`. A
*non*-literal key (`r[computed-name]`) is not checked at all — see §5.

**Multi-table operations.** `.stack(other)` requires `other`'s column
**name set** (order-independent) to equal the receiver's, matching the
runtime's own `stack` semantics (`table.js`'s `stack` sorts and compares
both header lists). `.add-row(row)` requires the same, against a `Row`'s
schema. Both report `TableTypeSchemaMismatch` on mismatch.

**Function signatures.** A `fun`/`lam` binding whose parameters and/or
return are annotated `Table<{...}>`/`Row<{...}>` gets a `FuncSig`. At a call
site, each `Table<{...}>`/`Row<{...}>`-annotated parameter's declared schema
must be a superset-with-compatible-types of ("≤", §2.4) the argument's
*known* schema; if the argument's schema is `unknown`, no check happens (permissive).
The call's result type is the function's declared return schema (if any),
otherwise `unknown`.

**Ordering.** `order t: c1 dir1, c2 dir2, ... end` checks every `ci` exists
in `t`'s known schema, **and** — regardless of whether the schema is known —
checks that no column name is repeated in the ordering list itself (a
compile-time version of the runtime's own `multi-order` duplicate-column
check; see §5, "Bugs found").

**`load-table:`.** Column *names* come from the header syntax (always
statically known); each column's *element type* comes from its `:: Ann` if
given, else defaults to `Any`. This is the concrete form of "for table data
from unknown sources, require annotations" — column existence is checked
for free from the syntax; only the finer per-column *type* needs annotation
because the source (a CSV, a URL, ...) genuinely isn't known until runtime.

**Extend reducers** (`name: reducer of col`) check that `col` is a `using`
column (already enforced by the pre-existing well-formedness pass) and
exists in the base schema; the new column's type is the reducer's `:: Ann`
if given, else `Any` — the reducer's own output type is not inferred (§5).

### 2.4 Width subtyping (`checkSubSchema`)

```
sup = {c1 :: T1, ..., cn :: Tn}      ∀ i. ci ∈ dom(sub)  and  sub(ci) compatible-with Ti
───────────────────────────────────────────────────────────────────────────────────────
                                  sub ≤ sup

sup = unknown   or   sub = unknown
──────────────────────────────────  (always compatible: unverifiable, so unchecked)
            sub ≤ sup
```

where `compatible-with` is `T.equals()` after erasing `Any`/`Top` on either
side. This directly mirrors the *pre-existing* record-width-subtyping rule
already in `type-check-structs.ts`'s constraint solver (the `t-record`
case: a subtype's record may have additional fields beyond what the
supertype requires). A table/row with **more** columns than required is an
acceptable value wherever fewer are required — the practical form of "row
polymorphism" this project implements (see §6 for the *general*, row-
*variable* form it stops short of).

## 3. Implementation strategy

### 3.1 Why a separate pass, and where it runs

By the time `type-check.ts` runs, table syntax no longer exists: the pre-
existing `desugar.ts` (which runs *before* `type-check.ts`, confirmed by
tracing `compile-lib.ts#compileModule`) rewrites `s-table`, `s-table-
extend`, `s-table-select`, `s-table-filter`, `s-table-order`, `s-table-
extract`, and `s-load-table` into raw `makeTable`/`checkWrapTable`/
`_column-index` primitive calls before the general checker ever sees them.
`Table` is typed as a single opaque `TName` throughout (`type-defaults.ts`),
with `makeTable :: (Array<Any>, Array<Array<Any>>) -> Table`, so nothing
about column shape survives desugaring.

Two implementation strategies were available:

  (a) Move table desugaring to run *after* type checking (mirroring how
      `s-cases`/`s-var`/`s-fun` are deliberately kept intact through type-
      check.ts and only erased by the later `desugar-post-tc.ts` pass), so
      the *existing* checker's own AST dispatch could grow new cases for
      table syntax.

  (b) Add a **new, independent pass** that runs on the pre-desugar AST (the
      same point `well-formed.ts` and `resolve-scope.ts` already operate
      at), with its own environment and its own bespoke `Val`/`Schema`
      representation, contributing to the same `CompileError` list.

(a) is more architecturally "pure" but is a much larger, riskier change:
`desugar.ts`'s table-handling code (~350 lines) is deeply entangled with
its private helpers (`mkId`, `checkTable`, `getTableColumn`, ANF-adjacent
lambda construction for the "using" clause), and moving it would touch
code generation timing in a way the task's constraints ("cannot change code
generation") make me want to avoid entirely. (b) is explicitly sanctioned
by the task ("You have free reign to ... add extra passes") and keeps
100% of the existing pipeline, including `desugar.ts`, completely
untouched. I chose (b).

Concretely, `table-check.ts#checkTables(program, compileEnv, postCompileEnv,
modules)` is called from `compile-lib.ts#compileModule` on `spied` — the
AST right after `resolveNames`, immediately before `D.desugar(spied!)` — and
only when `options.typeCheck` is set. Its returned errors are merged into
the same `anyErrors` array that already gates whether `T.typeCheck` runs
afterward. The insertion is four lines in `compile-lib.ts`.

### 3.2 A self-contained recursive-descent checker, not a visitor + separate inferencer

`table-check.ts` is one class, `TableChecker`, with one big method,
`inferExpr(e): Val`, that recursively walks *every* expression form the
pre-desugar AST can contain (blocks, lets, letrecs, lambdas, if/cases/for,
tuples, objects, applications, ...), threading a mutable `env: Map<string,
Val>` with explicit save/restore around each new lexical scope (lambda
bodies, `using`-clause bodies, for-bindings). This was a deliberate
simplification over a two-tier design (a generic tree-walking visitor for
traversal, plus a separate small "value inferencer" for table-relevant
subexpressions): a single function makes the scoping discipline easy to get
right, and every expression kind gets *some* handling — the ones this
checker doesn't specially understand (`s-data`, `s-check`, `s-reactor`,
method literals' bodies aside, ...) simply return `Val = unknown` **without
recursing further into them**. This is a conscious best-effort trade-off:
it means a table literal buried inside, say, a `data` variant's shared
method is not examined by this pass — but it never produces an unsound
"OK" as a result (§3.3), only reduced coverage in rare/advanced constructs.

Column element types reuse the *real* `type-check.ts#toType`, which needs a
`Context` (aliases/dataTypes/modules) to resolve names like `Number` or a
user's own `data` type. Building that context is normally interleaved with
the rest of `type-check.ts#typeCheck`'s ~130-line body. I factored the
context-construction logic out into an exported `buildInitialContext`
(`type-check.ts`), leaving `typeCheck`'s own behavior unchanged (pure
extract-method refactor, verified by the full test suite), so
`table-check.ts` can obtain a real `Context` without duplicating that logic
or running the whole bidirectional checker.

### 3.3 Soundness and backward compatibility

The two invariants this project relies on, both by construction:

  1. **Never claim a false positive.** `checkSubSchema`, and every column-
     existence check, return "no error" whenever either side's schema is
     `unknown` — i.e. whenever this pass genuinely cannot verify something,
     it says nothing, rather than guessing. Column *element* types are
     trusted, not re-verified at runtime (same status quo as `List<Number>`
     today — the prompt's own stated baseline).
  2. **Strictly additive.** A program using no `Table<{...}>`/`Row<{...}>`
     annotations and no table literals never gives `table-check.ts` any
     schema information, so every one of its checks is `unknown ≤
     anything`/`unknown has no known columns to violate` — it contributes
     zero errors, for any such program. This is what makes it safe to wire
     into `compile-lib.ts` unconditionally (when `-type-check` is on) without
     re-auditing the entire existing test suite's table-touching programs
     by hand — verified in practice by `make ts-test` / `make all-pyret-test`
     (§7).

## 4. A few points on the implementation surface

### 4.1 `Table<{...}>` and the *general* checker

Because `Table<{...}>`/`Row<{...}>` reuse the existing `a-app`+`a-record`
grammar, `type-check.ts`'s own `toType` also parses them — as
`TApp(TName(Table), [TRecord(...)])`, since `Table` is not a generic/
`TForall`-aliased type. Left alone, this made the *general* checker reject
every use of the new syntax outright (a table literal always synthesizes
plain `TName(Table)`, which doesn't unify with `TApp(TName(Table), [...])`).
Rather than teach the general checker about tables, I made it treat the
column-record argument as **erased/inert**: `TApp(TName(Table|Row), [_])`
is treated exactly like the bare `TName(Table|Row)` everywhere the general
checker compares or instantiates types (`eraseTableTypeApp`, called from
`resolveAlias` and `solveHelperConstraints`, `type-check-structs.ts`). This
keeps the general checker's own judgment of tables *exactly* as opaque as
it always was — table-check.ts is the only thing that ever looks inside
the column record — while making the new annotation syntax invisible noise
to it instead of a hard error.

### 4.2 Function/method signatures live in `table-check.ts` itself, not `type-defaults.ts`

`table-check.ts` keeps its own `funcSigs: Map<string, FuncSig>` (populated
from `Table<{...}>`/`Row<{...}>`-annotated `fun`/`lam` bindings) and a
hand-written dispatch table of the practical `Table`/`Row` **method** API
(`build-column`, `transform-column`, `drop`, `rename-column`, `select-
columns`, `filter-by`, `filter`, `order-by`, `order-by-columns`, `stack`,
`add-column`, `add-row`, `get-column`/`column`, `row-n`, `length`, `empty`,
`.get-value`/`.get` on Row, ...). This directly targets the way `core.arr`
and idiomatic Pyret table code is actually written — overwhelmingly method
calls (`t.build-column(...)`, `t.filter-by(...)`), not the `extend`/`sieve`
keyword sugar (§5 explains why the sugar forms are, separately, hard to get
through the *general* checker at all today). These rules are deliberately
*not* expressed as `TArrow` entries in `type-defaults.ts`; that registry
feeds the general checker, which has no notion of per-call-site column
checking — the precision belongs in table-check.ts alone.

## 5. Bugs found (and fixed, or not)

Investigating why realistic table programs failed `-type-check` even before
this project's own annotations surfaced a cluster of **pre-existing gaps**
in the TS compiler's type checker: essentially *no* program that constructs
or manipulates a `Table` via the keyword-sugar syntax, or via a method call,
or via bracket access, could pass `-type-check` at all. These are documented
here because several were outright bugs (missing/wrong primitive type
registrations) that this project fixed, while a couple are deeper
algorithmic limits documented for future work rather than fixed (per the
task's own guidance to leave things untypable rather than force-fit an
unsound or overreaching change).

**Fixed** (all in `type-defaults.ts` / `src/js/trove/global.js`, purely
type-level metadata — no runtime/codegen files were touched):

  - `checkWrapTable` (the runtime check `desugar.ts` wraps around every
    `table-extend`/`select`/`filter`/`update` operand) had no registered
    type at all, unlike its sibling `checkWrapBoolean` — an `s-prim-app` to
    an unregistered primitive raises `UnboundId`. **Any program using
    table keyword syntax failed immediately** with this error before
    anything about table shapes was even relevant.
  - `Table`/`Row` had no method fields registered in `global.js`'s
    `datatypes.Table`/`Row` descriptors at all (only `Table.length` was
    present) — so **every dot-method call on a table** (`t.filter(...)`,
    `t.build-column(...)`, etc.) failed with `ObjectMissingField`. Added
    the practical method surface (§4.2) directly to the JSON-ish type
    descriptor in `global.js` (a declarative, compiler-consumed type
    catalog — not code the runtime executes; `theModule`'s actual JS
    implementation is untouched).
  - Table-extend/update/select/filter/order's desugaring (`desugar.ts`)
    also emits several other primitives with **no registered type at
    all**: `raw_array_get`, `raw_array_set`, `raw_array_concat`,
    `raw_array_to_list` (the underscore-named internal primitives, distinct
    from the dash-named public `raw-array-*` library functions). Added all
    four to `type-defaults.ts`.
  - `raw-array-map-1`'s registered type took **2** arguments
    (`(fn, RawArray<RawArray<a>>) -> RawArray<b>`); the actual runtime
    function (`runtime.js#raw_array_map1`) and its one call site
    (`table-extend`'s row-mapping) both use **3** (`(f1, f, arr)`) — an
    outright arity bug, giving `IncorrectNumberOfArgs` on any `extend`.
  - `multi-order`'s registered argument type was `RawArray<Any>`; the real
    desugared call passes `RawArray<RawArray<Any>>` (array of `[Boolean;
    String]` pairs) — fixed the nesting depth.
  - `getBracket` (`obj[key]`, i.e. **any** `s-bracket`/`r["col"]`
    expression in the whole language, not just on tables) had no
    registered type — every bracket-access expression failed with
    `UnboundId`. Registered as `(Any, Any, Any) -> Any` (see §5's
    discussion below for why this, while correct, is also a hard limit).
  - `instantiateDataType`/`resolveAlias` (`type-check-structs.ts`) did not
    account for `TApp(TName(Table|Row), [_])` at all, so **any dot-access
    on a `Table<{...}>`/`Row<{...}>`-annotated binding** (not just a call
    result) hit a spurious `BadTypeInstantiation("expected 0 type
    arguments, but it received 1")`, since `Table`'s `TData` has zero
    declared parameters. Fixed by the same `eraseTableTypeApp` erasure
    used for constraint solving (§4.1), applied at these two additional
    call sites.
  - A subtler one: registering `List<Any>` (as opposed to `List<tany>`) as
    a nested generic argument in `global.js`'s type descriptors produced
    spurious `TypeMismatch`es when a concretely-typed `List<String>` value
    was checked against it, while the *same* `Any` used as a bare,
    non-nested argument (`(Any) -> X`) or nested inside `RawArray<Any>`
    behaved fine. I did not fully chase the root cause in `type-util.js`'s
    alias-vs-literal (`"Any"` vs `"tany"`) expansion, but empirically
    `"tany"` (the literal-Top shorthand) is safe in **every** nesting
    position while `"Any"` (the alias-name shorthand) is not always; I used
    `"tany"` throughout my own additions and flag the inconsistency here
    for anyone extending this catalog further.

**Found, documented, deliberately not fixed** (these are the "leave it
untypable" cases, in the sense that *fixing* them would mean changing core
algorithm behavior well beyond this project's table-typing scope, which the
task asks me to avoid touching without being confident it stays sound):

  - **`extend`/`sieve` with a `using` clause cannot pass the general
    checker today**, independent of table-check.ts. Their desugaring
    (`desugar.ts`) passes the row-processing lambda (`dataPopMapfun`) as
    the callback argument to the *generic*, `forall`-quantified
    `raw-array-map`/`raw-array-map-1`, with the callback listed *before*
    the array argument. Pyret's bidirectional checker processes an
    application's arguments left-to-right; it tries to check the
    (unannotated) lambda's body before the array argument has pinned down
    what the generic element type actually is, so the lambda's parameter
    type remains an unsolved existential — `UnableToInfer` ("please add an
    annotation"). This is a classic hard case for local bidirectional
    inference of higher-order generic functions (the callback needs to be
    checked *after* its co-argument to know its own type) that specialized
    systems solve with argument-order heuristics this checker doesn't have.
    Fixing it would mean either reordering desugar.ts's emitted arguments
    (a code-generation change, out of bounds) or making the general
    checker's argument-processing order generic-function-aware (a
    meaningfully large, independently-risky change to the core algorithm,
    not a "clear bug"). Left untypable; table-check.ts still checks these
    forms' column names/shapes on its own (§2.3), so this is purely a gap
    in what the *general* checker can additionally verify about the same
    expression, not a gap in this project's own table-schema guarantees.
  - **Values read out of a table/row cell cannot be used in arithmetic,
    ordering comparisons, or further dot/method calls under the general
    checker**, ever, regardless of any local fix. `getBracket`, and every
    Table/Row method that returns a cell value (`.get-value`, `.column`,
    ...), can only be soundly and honestly typed as returning `Any` to the
    general checker (§4.2 — there is no static information about the real
    element type at that call site as far as the general checker's own
    primitive-signature mechanism is concerned). `Any` cannot itself be
    coerced back down to a concrete type for arithmetic/ordering (those
    desugar to per-type method dispatch requiring a real object/data type)
    or passed where a concrete type is expected (the constraint solver
    only accepts things *into* `Top`, never treats `Top` as a usable
    *source*). **Equality** (`==`/`is`/`<>`) is the one operation that
    *does* work on `Any`-typed cell values, since Pyret's equality
    operators are already typed `(Any, Any) -> Boolean` in the base
    language. table-check.ts *does* give `r["col"]` its precise element
    type (from the row's known schema) for its own purposes — but that
    extra precision is not threaded back into the general checker's
    independent judgment of the same subexpression in this implementation
    (see §6 for what would be needed to do so). Concretely, this means:
    `r["age"] >= 18` is something table-check.ts alone can verify, but the
    overall pipeline (both passes) will still reject the program, because
    the *general* checker's own opaque judgment of the same subexpression
    is unaffected by table-check.ts's findings, and both passes' verdicts
    are ANDed together by the compiler pipeline. All of `/app/typed-
    examples/`'s programs were written to avoid this specific combination
    (equality-based predicates instead of arithmetic ones, or computing
    values from ordinary non-table data instead of round-tripping through
    a cell) — see the comments in `04-core-group-and-count.arr` and
    `06-core-predict-col.arr` for worked-through examples of the
    adaptation this required.
  - **`s-table-update`** (the `update ... using ...: ... end` keyword form)
    has no corresponding runtime method (`table.js` implements no
    `.update`), and is marked `# s-table-update not yet implemented` in the
    Pyret-hosted `ast.arr` itself. table-check.ts treats it as fully
    opaque/unknown (visits it for nested-error-finding only, makes no
    schema claims) rather than attempt to type an incomplete, seemingly
    partially-dead feature.
  - **Module-qualified access to a `.arr`-hosted library's own exported
    *values*** (e.g. `import tables as T; T.table-from-column(...)`, or
    even `include tables; table-from-column(...)`) resolves to type `Any`,
    not the library function's real declared type, under `-type-check` —
    apparently because `src/arr/trove/tables.arr` itself does not pass
    `-type-check` as a standalone module (a pre-existing, unrelated
    `ShadowId` well-formedness issue: a local name collides with the
    `sets` library's `set`, present even without `-type-check`), and a
    dependency module that fails to type-check appears to make its own
    exports opaque rather than hard-failing the whole build (a reasonable
    fallback design, but one that meant this project's own examples could
    not use `tables.arr`'s convenience constructors like
    `table-from-column`/`raw-row`). Worked around in `/app/typed-examples/`
    by building tables via table literals + `.stack`/`.add-column` instead
    of the `tables` library's helpers.

## 6. Features left untypable, and why

Beyond the general-checker limitations in §5 (which are about what the
*existing* checker can verify, not about this project's own table-schema
guarantees), the following are genuinely outside table-check.ts's own
static reach, on purpose:

  - **Column names computed at runtime** (`t.get-column(some-string-
    variable)`, `r[row["coefficient-name"]]` from `core.arr`'s
    `regression-model-fun`, `id-col = t.column-names().get(0)` from
    `find-by-id`). This is exactly the B2T2 paper's own "first-class column
    names" challenge (b2t2-paper.txt, §3.3: "column names are more than
    atomic labels... require at least append and split operations"). A
    sound static treatment needs singleton/literal string types tracked
    through arbitrary string computation (concatenation, list indexing,
    ...) — essentially dependent typing on strings. Out of scope; these
    expressions are simply not checked (fall back to `Any`/`unknown`),
    which is sound (no claim is made) and consistent with how the b2t2
    paper itself frames this as one of the hardest parts of the benchmark.
  - **`core.arr`'s own `group`/`count`/`mean`/`predict-col`/etc.**, as
    written, take a bare `Table`/`String` column-name pair with no static
    schema (e.g. `fun mean(t :: Table, col :: String) -> Number`). Nothing
    about *this* project changes how those specific, already-written
    functions are checked — they remain exactly as typable/untypable as
    they were before this project (i.e., `Table`/`String` typecheck as
    written, with all the real column-existence work still happening
    dynamically at runtime, same as today). Getting *precision* out of them
    requires rewriting their signatures to use `Table<{...}>` — which is
    exactly what `/app/typed-examples/04-core-group-and-count.arr` and
    `06-core-predict-col.arr` demonstrate, as adaptations, per the task's
    "mine `core.arr` for representative examples" instruction.
  - **Reducers' own output type** (`s-table-extend-reducer`,
    `TS.Reducer<Acc, InVal, OutVal>` from `tables.arr`). Determining a
    reducer's `OutVal` without executing it requires tracking a record
    value's field type through to whatever `one`/`reduce` compute, which
    this checker does not attempt; an explicit `:: Ann` on the reducer
    field is honored if given, else `Any`.
  - **Loading a table from a genuinely dynamic, out-of-program source**
    (`load-spreadsheet`, live Google Sheets `sheet.load(columns, ...)`
    where `columns` is a runtime `List<String>`) is out of scope by design
    — the paper itself explicitly punts on I/O ("we ignore input-output:
    the benchmark does not stipulate how tables are entered into
    programs", b2t2-paper.txt lines 286-289). `load-table:`'s *own*
    header syntax is the one place this project *does* give a static
    answer (column names, since they're syntactically listed), matching
    the task's suggestion to "require annotations" for unknown sources —
    but a fully dynamic loader like `core.arr`'s `live-display` has no
    static header to check against at all, and stays opaque.
  - **Heterogeneous-column reflection** ("give me all the numeric columns
    of this table") is excluded by the b2t2 paper itself as out of the
    benchmark's ambition (`b2t2-paper.txt` lines 282-285: "Column sorts are
    not first class... a program cannot filter the numeric columns... by
    inspecting column sorts"), and is equally out of reach here for the
    same reason: it needs type-level reflection over the schema, which this
    (or most any) static type system does not provide.
  - **A designed-but-unimplemented column-name-polymorphism idea**: I
    considered (but did not build) a `Col<"name">` singleton-string
    annotation to let a function like `mean(t :: Table<R + {col :: Number}>,
    col :: Col<"col">)` type-check generically over which column it reads.
    This would require genuine row-*variable* polymorphism (see §7) as a
    prerequisite, so I did not pursue it standalone.

## 7. Alternate designs that would need language/implementation changes

  - **True row-variable polymorphism.** The width-subtyping this project
    implements (§2.4) is per-call-site and non-generic: a function's
    declared parameter/return schemas are fixed, closed records. There is
    no way, today, to write "a function that accepts a table with *at
    least* column `age`, and returns that same table with one *additional*
    column, whatever other columns it originally had" — calling such a
    function against a table with extra columns will type-check (width
    subtyping accepts the call), but the *declared return type* is still
    the fixed schema written in the annotation, silently "forgetting" the
    caller's extra columns in the static type (though not at runtime — the
    columns are still really there). Fixing this needs a genuine row-
    variable construct in the type language (`Table<{age :: Number | ρ}>`,
    a new kind of type variable distinct from the existing `TVar`/
    `TExistential`, with its own instantiation/generalization machinery in
    `type-check-structs.ts`'s constraint solver) — a substantial, novel
    addition to the core type system, not a table-specific tweak. This is
    the single biggest thing I would build next given more room.
  - **Threading table-check.ts's precision back into the general
    checker.** As discussed in §5, the two passes' verdicts are currently
    independent and ANDed: table-check.ts can know `r["age"] :: Number`
    precisely, but the general checker still only ever sees `Any` for the
    same subexpression (since `getBracket`/Table methods must be given a
    single, context-free primitive signature). Unifying them — so that
    once table-check.ts has established a Row's schema, the *general*
    checker's own treatment of bracket-access on that specific Row
    expression also narrows accordingly — would require either (a) folding
    `table-check.ts`'s schema tracking directly into `type-check.ts`'s
    `Context`/constraint system (undoing the "keep it a separate pass"
    decision in §3.1, with all the integration risk that was avoided by
    not doing so), or (b) a two-pass protocol where table-check.ts
    *rewrites* bracket-access nodes it can resolve into something the
    general checker can type precisely before desugaring — which edges
    into "changing what gets generated for type-checking purposes" and
    would need careful scoping to stay within "no code generation changes."
  - **A first-class `a-table`/`a-row` `Ann` AST variant**, instead of
    overloading `a-app`+`a-record`. I chose the overload specifically to
    avoid any grammar/parser changes (§2.1); a dedicated surface form
    (e.g. `Table[name :: String, age :: Number]` with its own token) would
    remove the need for the `eraseTableTypeApp` erasure trick in §4.1
    entirely (the general checker would simply never see it as a `TApp`),
    at the cost of a real grammar change and parser-table regeneration,
    which felt like a disproportionate risk for a syntax-only benefit given
    the existing syntax already reads naturally.
  - **A CSV-import-time schema inference form**, per the task's suggestion
    ("a new import form that can, at module resolution time, load a CSV
    file and calculate its types"). I scoped this out given time
    constraints once `load-table:`'s own header-based column-name checking
    (§2.3) covered the more common, syntactically-visible case; a genuine
    `import "data.csv" as T` that samples the file at compile time and
    synthesizes a `Table<{...}>` type would need new module-resolution
    machinery (reading and sniffing an arbitrary file during compilation,
    independent of the existing `.arr`/builtin module search) and its own
    story for what happens when the file changes between compiles — a
    reasonable follow-on project, but a substantial one in its own right.

## 8. How to read/write the new types

- Annotate any table-valued binding, parameter, or return type with
  `Table<{col1 :: Ann1, col2 :: Ann2, ...}>` to give it a known, checked
  schema. Use bare `Table` (as before) for values whose schema genuinely
  isn't known statically (opaque sources, results of functions that don't
  themselves use the new annotations, ...) — this remains completely valid
  and is not an error.
- Annotate a row-processing callback's parameter with `Row<{...}>` to check
  bracket access (`r["col"]`) and `.get-value`/`.get` calls against it.
  Unannotated callback parameters passed directly to `build-column`/
  `transform-column`/`filter`/`filter-by` get this automatically inferred
  from the receiving table's own schema.
- Column names in `select`/`extract`/`order`/the `using` clause of
  `extend`/`sieve`, and in every table/row method that takes a column name
  as a **literal string**, are checked against the operand's known schema
  when present.
- A function whose `Table<{...}>` parameter requires fewer columns than a
  caller's argument actually has still type-checks (width subtyping,
  §2.4) — you do not need to "widen" a table type by hand to pass it to a
  more specific function.
- Errors are reported through the same `CompileError` channel as every
  other type error (`compile-errors.ts`'s new `TableTypeColumnNotFound`/
  `TableTypeDuplicateColumn`/`TableTypeColumnMismatch`/
  `TableTypeDuplicateSortColumn`/`TableTypeSchemaMismatch`), so they render
  and are collected exactly like an ordinary `type-mismatch`.
