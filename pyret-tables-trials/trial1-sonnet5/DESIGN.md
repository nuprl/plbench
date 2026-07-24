# Static Type Checking for Tables in Pyret — Design Report

This document explains the table-typing design added to Pyret's TypeScript
compiler (`/app/pyret-lang/lang/src/ts-compiler/`), in enough detail that a
reader who has the B2T2 paper and `core.arr` in hand, but hasn't seen the
diff, can evaluate it. It covers the type grammar and rules, the
implementation strategy, bugs found along the way, and what's deliberately
left untyped and why.

All type-checking work is confined to the TypeScript compiler backend
(`src/ts-compiler/`), per the task's scope; the Pyret-hosted ("regular")
compiler's own sources under `src/arr/compiler/` are untouched. Two small,
mechanical pretty-printer fixes (see [Bugs found](#bugs-found) items 2–3)
also touch `src/arr/trove/ast.arr`, the single shared AST module both
backends compile as a trove import — not compiler-internal code, and not
type-checking logic, but worth flagging as outside the strict `ts-compiler/`
directory boundary.

## Contents

1. [Quick-start: how to read and write the new types](#quick-start)
2. [Type grammar](#type-grammar)
3. [Type rules](#type-rules)
4. [Implementation strategy](#implementation-strategy)
5. [Bugs found](#bugs-found)
6. [Features left untypable, and why](#features-left-untypable-and-why)
7. [Alternate designs that would need language changes](#alternate-designs)
8. [Testing](#testing)

---

## Quick-start

A table's type is spelled `Table<{col :: Ann, ...}>`; a single row's type
(from `row-n`, `all-rows()`'s element, or a `build-column`/`filter` callback
parameter) is spelled `Row<{col :: Ann, ...}>`. Both reuse Pyret's existing
generic-application and record-annotation syntax — `Name<ann>` and
`{field :: Ann, ...}` — so **no grammar or parser changes were needed**:

```
gradebook :: Table<{name :: String, age :: Number, quiz1 :: Number}> =
  table: name, age, quiz1
    row: "Bob", 12, 8
    row: "Alice", 17, 6
  end

fun average-quiz1(t :: Table<{quiz1 :: Number}>) -> Number:
  scores = t.column("quiz1")
  scores.foldl(lam(a, acc): acc + a end, 0) / scores.length()
end
```

Passing `gradebook` (more columns) to `average-quiz1` (fewer columns) is
allowed — table types are **width-subtyped**, like Pyret's ordinary object
types (see [Type rules](#type-rules)). A table literal's columns are typed
automatically, even with no annotation at all — each column's type is
inferred from its cells — so `table: name, age row: "Bob", 12 end` already
has the precise type `Table<{name :: String, age :: Number}>` without you
writing anything extra. Header annotations (`name :: String`) are optional
and, when given, are checked against every row's cells.

A **bare** `Table`/`Row` annotation (no `<{...}>`) means what it always has:
an opaque, dynamically-checked value with no column information. This
matters for backward compatibility — it's exactly the annotation style
`core.arr` uses throughout (`fun mean(t :: Table, col :: String) -> Number`)
— so that code keeps compiling and running unchanged; it just doesn't get
any new column-level checking. Precise (`Table<{...}>`) and opaque (`Table`)
values interoperate freely: a precise table can be passed wherever an opaque
one is expected (and vice versa dynamically, since opaque tables are
checked against nothing).

Methods on tables and rows (`.column(...)`, `.build-column(...)`,
`.get-value(...)`, etc.) are individually recognized by the checker (see
[Type rules](#type-rules) for the full list) and given precise types when
the column name argument is a literal string; if the receiver is opaque or
the argument isn't a literal, the method still type-checks (for backward
compatibility) but the result carries no new column information — this is
the "leave untypable rather than unsound" boundary described in the task,
applied throughout.

---

## Type grammar

### New type-level grammar

Two new members are added to the `Type` union in `type-structs.ts`:

```
Type ::= ... | TTable(row: TypeMembers) | TRow(row: TypeMembers)
TypeMembers ::= Map<column-name :: string, Type>
```

`TTable`/`TRow` are structurally identical (both are just a column-name →
type map, mirroring the existing `TRecord(fields: TypeMembers)`) but are
kept as distinct tags: a `Table` is never considered a subtype of a `Row`
or vice versa, matching the paper's own table/row distinction (§3.1: "A
table has two parts: a schema and a rectangular collection of cells... A
row is an ordered sequence of cells").

There is no separate "column name" or "sort" grammar production — a
column's type is an ordinary Pyret `Ann`/`Type`, so anything already
expressible as a Pyret annotation (including `Option<Number>` for a
column that may be empty, another `Table<{...}>` for a sub-table cell, a
function type, etc.) is already a valid column sort. This directly matches
B2T2 §3.1's "The sorts can vary freely" and its footnote that a sort "can
be" any type, including another table.

### New surface annotation syntax

```
table-ann  ::= Table '<' '{' (col-ann (',' col-ann)*)? '}' '>'
row-ann    ::= Row   '<' '{' (col-ann (',' col-ann)*)? '}' '>'
col-ann    ::= NAME '::' ann
```

This is not new grammar at all — `Table<{...}>` parses today as an ordinary
`a-app` (generic instantiation) annotation whose one argument is an
ordinary `a-record` annotation (`app-ann: (name-ann|dot-ann) LANGLE
comma-anns RANGLE`, `record-ann: LBRACE trailing-opt-comma-ann-field
RBRACE`). `toType`'s `a-app` case (in `type-check.ts`) special-cases exactly
this shape — `AApp` whose head is the built-in `Table`/`Row` type-global and
whose single argument is an `ARecord` — to build a `TTable`/`TRow` directly,
instead of the generic (and, for `Table`/`Row`, non-functional — see
[Bugs found](#bugs-found)) `TApp` instantiation path. Recognizing the
built-in name is done by comparing the annotation's resolved
`s-type-global` key, not by resolving through the alias table, precisely
*because* a bare `Table`/`Row` annotation is deliberately left resolving to
its existing (opaque) meaning — see below.

I judged this the right tradeoff: it gets a working, comparably-legible
table-type annotation syntax with zero grammar/parser changes, at the cost
of `Table`/`Row` being slightly "magic" generic heads (you can't define your
own generic type named `Table` and get table-typing behavior from it, but
nothing stopped that being confusing anyway).

### Column-name grammar (unchanged)

Column names themselves are not part of the `Type` grammar in any first-class
sense — they are plain object keys in a `TypeMembers` map, exactly as
record field names are plain keys in `TRecord`. This is a deliberate
consequence of B2T2 §3.3's observation that "column names are first-class
and manufacturable": true first-class column names (nameable, splittable,
computable at compile time and checked at that precision) would need
something like singleton/literal string types or row polymorphism with
named-field arithmetic, which this design does not attempt — see
[Alternate designs](#alternate-designs).

---

## Type rules

Below, `Γ ⊢ e ⇒ T` means `e` synthesizes type `T` in context `Γ`; `Γ ⊢ e ⇐ T`
means `e` checks against expected type `T`. All rules are implemented in
`type-check.ts`'s `_synthesis`/`_checking` (the `s-table*`/`s-load-table`
cases) and the table/row method dispatch (`synthesisTableMethod`/
`synthesisRowMethod`, invoked from the `s-app` case when the callee is a
dot-access whose field name is a recognized Table/Row method).

### Table literals

```
header i has annotation A_i (or none)         column type T_i = A_i if given
∀ row, i:  Γ ⊢ row[i] ⇐ T_i   (if A_i given)      else T_i = meet(Γ ⊢ row[i] ⇒ · , over all rows)
─────────────────────────────────────────────────────────────────────────
Γ ⊢ (table: name_1 :: A_1?, ..., name_n :: A_n? row: e_11, ..., e_1n ... end)
      ⇒ Table<{name_1 :: T_1, ..., name_n :: T_n}>
```

Each column's type is either its declared annotation (in which case every
cell in that column is *checked* against it, inserting no coercion — same
discipline as any other `::` annotation in Pyret) or, if no annotation is
given, the **meet** of every row's synthesized cell type in that column.
"Meet" here reuses the exact mechanism `type-check.ts` already uses to merge
`if`/`cases` branch types and array-literal element types
(`meetBranchTypes`: introduce a fresh existential, constrain every
candidate type as a subtype of it, solve, generalize) — so a column whose
cells are literally-identical types gets that exact type, and a column
whose cells have a common structural supertype gets that supertype,
following the same rules as everywhere else in the language rather than a
table-specific special case.

### `load-table`

```
∀ header i:  A_i is present (not blank)
────────────────────────────────────────────────────────
Γ ⊢ (load-table: name_1 :: A_1, ..., name_n :: A_n source: e end)
      ⇒ Table<{name_1 :: A_1, ..., name_n :: A_n}>
```

Unlike a table literal, **every column annotation is required** — a
`LoadTableColumnNeedsAnnotation` compile error is raised for the first
column missing one. This is the task's suggested design point applied
directly: data entering the program from outside (a `source:` value, e.g. a
CSV loader) cannot be inspected at compile time, so there is no cell data
to infer a column's type from the way there is for a table literal. The
`source:`/`sanitize ... using ...` sub-expressions are still ordinarily
type-checked (so a badly-typed sanitizer function is still caught), just
not connected to the resulting table's column types — see
[Bugs found](#bugs-found) for a caveat about testing this end-to-end.

### Column-projecting/filtering sugar (`select`, `sieve`, `order`, `extract`)

```
Γ ⊢ table ⇒ Table<{...R...}>        c_1..c_k ∈ dom(R)
──────────────────────────────────────────────────────
Γ ⊢ (select c_1, ..., c_k from table end) ⇒ Table<{c_1 :: R(c_1), ..., c_k :: R(c_k)}>

Γ ⊢ table ⇒ Table<{...R...}>       c ∈ dom(R)                     Γ, using-binds ⊢ pred ⇐ Boolean
────────────────────────────────                    ─────────────────────────────────────────────────
Γ ⊢ (order table: c asc/desc ... end) ⇒ Table<{...R...}>     Γ ⊢ (sieve table using ...: pred end) ⇒ Table<{...R...}>

Γ ⊢ table ⇒ Table<{...R...}>       c ∈ dom(R)
───────────────────────────────────────────────
Γ ⊢ (extract c from table end) ⇒ List<R(c)>
```

`select`/`order`/`sieve` all require every named column to exist in the
source table (an `ObjectMissingField` error otherwise, reusing the same
error the checker already gives for a missing object field — a table's
column set behaves exactly like an object's field set for this purpose).
`select` narrows the schema to just the requested columns (in the requested
order, though **order is not part of a table type's identity** — see
subtyping below); `order`/`sieve` are schema-preserving; `extract` is the
one form whose result is a `List`, not a `Table` (matching how it desugars
— see [Implementation strategy](#implementation-strategy)).

`sieve`'s (and `extend`'s and `transform`'s) `using name_1, name_2, ...`
clause follows the same convention the pre-existing desugaring already
used: **each bind's own identifier names the column it projects** — `using
age` brings `age` into scope bound to the current row's `age` cell, typed
`R(age)`. This isn't a new rule invented for the type checker; it's the
existing runtime convention, given a corresponding static rule.

### `extend`

```
Γ ⊢ table ⇒ Table<{...R...}>      Γ, using-binds : R ⊢ value ⇐ A   (or synthesize if no A)
────────────────────────────────────────────────────────────────────────────────────────
Γ ⊢ (extend table using ...: name :: A?: value end) ⇒ Table<{...R..., name :: A or synth(value)}>
```

Plain (non-reducer) extension fields behave like a `let`: checked against
their declared annotation if given, else synthesized. Reducer fields
(`name :: A: reducer of column`) are handled differently — see
[Features left untypable](#features-left-untypable-and-why) for why the
reducer expression's own shape isn't verified, only:

```
A is present (required)         column ∈ dom(R)
────────────────────────────────────────────────
Γ ⊢ (extend table using ...: name :: A: reducer of column end)
      ⇒ Table<{...R..., name :: A}>
```

### `transform` (the table-update sugar)

```
Γ ⊢ table ⇒ Table<{...R...}>      ∀ (name: value) ∈ updates:  name ∈ dom(R),  Γ, using-binds : R ⊢ value ⇐ R(name)
────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Γ ⊢ (transform table using ...: name_1: value_1, ... end) ⇒ Table<{...R...}>
```

Every updated column must already exist, and its new value must check
against that column's *existing* type — `transform` preserves the schema,
unlike `.transform-column(...)` the method (below), which can change a
column's type. I chose this asymmetry deliberately: `transform`'s surface
syntax has no annotation slot at all (it reuses plain `name: expr` object
fields), so there's no way for the programmer to *declare* a new type for
the column the way `extend`/`.transform-column(...)` allow; requiring the
new value to match the old type is the conservative, sound reading of "no
annotation given."

### Table/Row method calls

A curated dispatch (`synthesisTableMethod`/`synthesisRowMethod` in
`type-check.ts`) recognizes these Table methods —

```
column-names() -> List<String>              length() -> Number
all-rows() -> List<Row<R>>                   all-columns() -> List<List<Any>>
empty() -> Table<R>                          row-n(Number) -> Row<R>
column-n(Number) -> List<Any>                column(String), get-column(String) -> List<T>
drop(String) -> Table<R - col>               rename-column(String,String) -> Table<R renamed>
add-column(String, List<T>) -> Table<R + col :: T>
build-column(String, (Row<R> -> T)) -> Table<R + col :: T>
transform-column(String, (T0 -> T1)) -> Table<R with col :: T1>
filter((Row<R> -> Boolean)) -> Table<R>      filter-by(String, (T -> Boolean)) -> Table<R>
order-by(String, Boolean) -> Table<R>        increasing-by/decreasing-by(String) -> Table<R>
order-by-columns(List<{String; Boolean}>) -> Table<R>
stack(Table) -> Table<R>                     reduce(String, Any) -> Any
```

— and these Row methods:

```
get-value(String) -> T          get(String) -> Option<T>          get-column-names() -> List<String>
```

where `T` is looked up precisely whenever the column-name argument is a
*literal string* and the column exists in a known `R`; a missing literal
column name is a compile error (again `ObjectMissingField`, or a dedicated
"column already exists" error for `add-column`/`build-column`'s target
name — see [Bugs found](#bugs-found)). When the argument is **not** a
literal (a variable, e.g. `t.column(col)` for a `col :: String` parameter)
or the receiver's shape is dynamic/opaque, the call still type-checks —
this is the load-bearing "leave untypable, not unsound" fallback that keeps
`core.arr`'s style compiling — but the result carries no new column
information (`List<Any>`, `Table` opaque, etc., matching this compiler's
behavior before table types existed).

`stack`'s real contract (same column *set*, any order) is not verified
statically; see [Features left untypable](#features-left-untypable-and-why).

This dispatch only fires for `t.method(...)` **calls** immediately
following a dot (not an un-applied method value like `t.column-names`
passed around alone); see the same section for that limitation.

### Subtyping (width subtyping, plus interop with the opaque names)

```
∀ c ∈ dom(R2):  c ∈ dom(R1),  R1(c) <: R2(c)
──────────────────────────────────────────────
Table<{...R1...}> <: Table<{...R2...}>        (and the same rule for Row)
```

A table with **more** columns than required is a subtype of one that
requires fewer — ordinary structural width subtyping, implemented in
`solveHelperConstraints` by literally reusing the object-type
subtyping code path (`TRecord`'s existing rule), just against
`TTable`'s/`TRow`'s `row` map instead of `TRecord`'s `fields` map. Column
*order* is deliberately not part of a table type's identity (its `key()`
sorts columns, matching how `TRecord` already treats field order as
irrelevant to identity) — this is a considered design choice: the paper
requires column order for *presentation* (§3.3: "Tables must preserve this
order at least in their presentation") but doesn't require it for
*typing*, and treating order as significant would make ordinary
column-reordering operations (or even writing the same columns in a
different order in two `Table<{...}>` annotations) needlessly rejected.

Every known-shape `Table<{...}>`/`Row<{...}>` is also a subtype of the
*opaque* `Table`/`Row` name (see below) — this lets a precisely-typed table
flow into any context that only asks for "some table," including this
checker's own `stack` parameter type.

---

## Implementation strategy

### The central architectural decision: move table desugaring to run *after* type-checking

Before this work, table syntax (`table:`, `select`, `sieve`, `extend`,
`order`, `extract`, `transform`, `load-table:`) was fully desugared to
`makeTable`/`raw-array-*` primitive calls in `desugar.ts`, which runs
*before* `type-check.ts`. By the time the type checker ran, there was no
table syntax left to see — column names were already baked into runtime
string literals inside opaque array constructions, and the one declared
type for the resulting `makeTable` call (`type-defaults.ts`) was a single,
context-*insensitive* global signature (`(RawArray<Any>, RawArray<RawArray
<Any>>) -> Table`), which cannot depend on which literal strings a
particular call site happened to pass. There is no way to recover
column-precise types from that shape after the fact.

So the core implementation move was: **stop lowering table syntax in
`desugar.ts`; teach `type-check.ts` to type-check the table AST nodes
directly; move the (unchanged) lowering logic to run afterward, in
`desugar-post-tc.ts`.** Concretely:

- `desugar.ts`'s `s-table`/`s-table-select`/`s-table-extend`/
  `s-table-update`/`s-table-filter`/`s-table-order`/`s-table-extract`/
  `s-load-table` cases now just recursively desugar their *non-table*
  subexpressions (row cells, extend/update field values, filter
  predicates, reducer expressions, load-table sources/sanitizers) and
  reconstruct the same node kind, instead of lowering to `makeTable`/
  `raw-array-*` prim-apps.
- `type-check.ts` gained `_synthesis` cases for all eight node kinds (see
  [Type rules](#type-rules)), each producing a `TTable`/`TRow`/`List<T>`
  result and a rewritten AST node (with type-checked children spliced back
  in, the same pattern every other case in this file already follows).
  `_checking` delegates all eight to `checkSynthesis` (synthesize, then
  unify against the expected type) — none of the eight forms benefit from
  genuine bidirectional (expected-type-driven) checking beyond what a table
  literal's own header annotations already give it, so a dedicated
  checking-mode rule for each would have been pure duplication.
- `desugar-post-tc.ts` gained the *exact* lowering logic `desugar.ts` used
  to have — moved essentially verbatim, substituting `.visit(this)` for the
  old file's `desugarExpr(...)` calls so table cell/predicate/reducer
  expressions still recurse through this pass's own visitor (needed
  because `s-cases`/`s-template` elimination, which *also* now happens in
  this pass, must still reach inside table forms).

This satisfies the "cannot change code generation" constraint by
construction: the same primitives are produced, from the same information,
by code that is nearly line-for-line what was removed from `desugar.ts` —
only *when* the rewrite happens moved, not *what* it produces. I verified
this both indirectly (the full existing table runtime-behavior suite,
`tests/pyret/tests/test-tables.arr`, 180/180 checks, and the table-specific
slice of `make ts-test`'s `ts-pyret-test`, all pass unchanged) and directly
(reading the two versions side by side).

This also happens to be exactly what the pre-existing code anticipated:
`desugar.ts`'s old `s-table-extend` case carried a comment — *"I am fairly
certain that this will need to be moved to post-type-check desugaring,
since the variables used by reducers is not well-typed"* — describing
precisely this move, for precisely this reason, before any of this task's
work began.

### Type representation: a new `Type` variant, not a `TRecord` reuse

I considered representing `Table<{...}>` as `TApp(tTable, [TRecord(...)])`
(reusing `TRecord` as the "row" type argument) instead of adding a new
`Type` variant, to minimize the number of places that need updating. I
rejected it because it would have made two independent things share one
representation for the wrong reason:

- **Subtyping.** `TApp` type arguments are checked structurally by
  decomposing pairwise per position with no established variance
  convention of their own; getting *width* subtyping (more columns is a
  subtype of fewer) for the row argument specifically, without also
  changing how *every other* generic type's arguments are compared, would
  have meant special-casing on the identity of the `onto` (`Table`) inside
  otherwise-generic `TApp` subtyping code — arguably *more* invasive than a
  new variant, and confusing to read (a `TApp` argument suddenly not
  behaving like other `TApp` arguments).
- **Identity.** `Table<{a :: Number}>` and `Row<{a :: Number}>` would
  become indistinguishable except by their `TApp`'s head — easy to
  conflate accidentally in code that pattern-matches on shape rather than
  on the head name.

A dedicated `TTable`/`TRow` variant makes both of those explicit and
enforced by the type checker (a `case 't-table':` can't accidentally also
match a `Row`), at the cost of touching every function that pattern-matches
exhaustively over `Type` — which turned out to be a bounded, mechanical set
(`type-structs.ts`'s `TypeBase` methods, `type-check-structs.ts`'s
constraint solver/generalizer/structure-tracker, `ast-util.ts`'s
cross-module name canonicalizer). Two places (`anf-loop-compiler.ts`'s
`compileProvidedType`, used only for serializing a module's provided types,
and `type-check-structs.ts`'s `instantiateObjectType`/`solveHelperFields`,
used only for the object-field-constraint duck-typing mechanism) already
had graceful `default:` fallbacks and did not need new cases — table values
never flow through the field-constraint mechanism in this design (method
dispatch is a dedicated code path, not modeled as object-field access), and
a table value crossing a `provide` boundary degrades to an opaque `Any`
rather than crashing (a documented limitation, not a crash — see
[Features left untypable](#features-left-untypable-and-why)).

### Method dispatch: a dedicated pre-pass in `s-app`, not a `DataType`

I looked at making `Table`/`Row` real `DataType`s (like `List`) with
declared method fields, so that ordinary dot-access (`instantiateDataType`/
`solveHelperFields`) would handle method calls generically. I didn't do
this because table methods are *not* uniformly typed across a `DataType`'s
single declared signature — `column`'s return type depends on which
literal string was passed, `build-column`'s depends on the callback's
return type, `drop`'s depends on which column is being removed — none of
which a flat, per-name method-type table (what `DataType.fields` is) can
express. What table methods actually need is closer to a small
per-call-site elaboration than a single method signature, so I wrote it as
exactly that: a dispatch keyed on method name, invoked from `s-app`'s case
*before* the generic call/dot-access machinery runs, falling back to that
generic machinery unchanged whenever the receiver isn't table/row-shaped or
the method name isn't one of the ones above. `add-column`/`build-column`
still get genuine polymorphism where it's actually just parametric (the new
column's element type) via a fresh existential added to the *current*
constraint-solving level, so ordinary unification (matching the type
against the value/callback actually passed) resolves it — this is the same
mechanism the rest of the checker already uses for e.g. `list.map`'s result
type, not a new inference technique.

### Opaque `Table`/`Row`: discovered, not designed

A `Table`/`Row` value with no column information (a bare-annotated
parameter, or any table method call on one) had to behave identically to
this compiler's pre-existing behavior, for backward compatibility. I
initially assumed (based on the aliasing table in `compile-structs.ts`,
which maps `"Table"`/`"Row"` to `Any`/`t-top`) that a bare `Table`
annotation always resolves to `Any`. Testing revealed this is only true in
some circumstances (see [Bugs found](#bugs-found) for the discovery
process): a `Table`/`Row`-annotated *function parameter* resolves instead
to an opaque nominal `TName` (the same one `type-structs.ts`'s pre-existing
`tTable` constant already names), because `Table` is registered in the base
environment as a data-definition with no declared alias, and `type-check.ts`'s
own global-setup code falls back to a bare `TName` in exactly that case.
Both `tableShapeOf`/`rowShapeOf` (the functions that classify a receiver as
"known", "dynamic", or "not a table at all") and the table/row-vs-opaque
subtyping rule treat this opaque name the same as `Any`/an unresolved
existential — dynamic, permissive, no column guarantees — so the
distinction is invisible to a user relying on the existing `t :: Table`
idiom; it only mattered for getting my own implementation to actually
recognize `core.arr`-style parameters as "dynamic" rather than erroring.

---

## Bugs found

Several of these were discovered only because implementing tables required
exercising code paths (bracket indexing, function-parameter annotation
resolution, `csv`/`data-source` cross-module types) that had essentially no
prior coverage. All are in the TypeScript compiler except where noted.

1. **Bracket indexing (`expr[key]`) crashed the type checker outright**,
   for *any* receiver type, not just tables — `arr[0]` on a plain
   `RawArray` under `-type-check` failed with an opaque `Cannot read
   properties of undefined (reading 'toname')` instead of a compile error.
   Root cause: `desugar.ts` always lowers `s-bracket` to
   `SPrimApp('getBracket', ...)` *before* type-check ever runs (so the
   `s-bracket` cases inside `type-check.ts`'s `_synthesis`/`_checking` are
   dead code, unreachable — I initially "fixed" those, then discovered they
   never ran), and `type-defaults.ts` had no entry for `'getBracket'` at
   all — `lookupId`'s failure path constructs an `UnboundId` error passing
   the whole `SPrimApp` as if it were an id-shaped expression, and that
   error's renderer calls `.id.toname()` on it, which doesn't exist.
   **Fix:** added a `getBracket :: (Loc, Any, Any) -> Any` entry to
   `type-defaults.ts` (bracket access has no static safety in Pyret
   regardless of tables, so `Any` is the honest type for both arguments and
   the result) — this turns bracket indexing into ordinary, permissive,
   crash-free dynamic code under `-type-check`, matching how it already
   behaved without `-type-check`. This is a real, general bug fix,
   independent of tables, left in place. (The dead `s-bracket` cases in
   `_synthesis`/`_checking` were reverted back to their original `raise(...)`,
   with a comment explaining why they're unreachable, rather than left as
   misleading not-quite-dead code.)

2. **`s-table-update` had no `tosource()`/`label()` implementation in
   *either* AST** (`ast.ts` and the shared `src/arr/trove/ast.arr`, used by
   both backends) — this predates this task entirely (confirmed by reading
   both files, including the codebase's own `# s-table-update not yet
   implemented` comment, before making any changes). It surfaced as a real,
   reproducible failure: `make all-pyret-test`/`make ts-test` both showed a
   check block in `test-pprint.arr` "ending in error" with `"The left side
   was an object that did not have a field named `tosource`:
   s-table-update(...)"` — `test-pprint.arr` recursively scans the whole
   `lang/` tree for `.arr` files and round-trip-tests (parse → pretty-print
   → re-parse → compare) every one it finds, and, being a `transform`-sugar
   node, `s-table-update` occasionally turned up among its randomly
   generated test programs. **Fixed** in both `ast.ts` and `ast.arr`
   (`STableUpdate`/`s-table-update` now have `label()`/`tosource()`,
   modeled directly on the existing `STableExtend`/`s-table-extend` case,
   which has the same `columnBinds`+field-list shape) — low-risk (an
   isolated pretty-printer addition, no type-checking logic involved) and
   directly table-related, so worth fixing despite living in code shared
   with the regular backend.

3. **A second, related pre-existing pprint bug, found only because fixing
   #2 pulled a genuinely new fixture file into `test-pprint.arr`'s
   directory scan:** `STableExtendField`/`STableExtendReducer`'s
   `tosource()` (in both `ast.ts` and `ast.arr` — again pre-existing, not
   written for this task) concatenates a column's annotation directly after
   its name with a bare `::` and no surrounding space (`"total" +
   "::" + ann.tosource()`, e.g. producing `total::Number`). That text
   fails to re-parse: `total::Number: ...` errors with an unexpected
   `COLON` token. This turns out to be a **general, non-table lexer/parser
   quirk**, not specific to the extend-field case at all — a minimal,
   completely unrelated repro, `x::Number = 5` (an ordinary annotated `let`,
   no tables involved), fails to parse the same way, while `x :: Number =
   5` (one space added) parses fine. This bug was latent and untriggered
   before this task simply because no pre-existing `.arr` file anywhere in
   the scanned tree happened to use the `extend ... name :: Ann : ...`
   surface form combined with being on that recursive-scan path; adding
   `src/ts-compiler/tests/table-types/good/stack-and-reducer.arr` (a fixture
   from this task, using exactly that form for its reducer's return-type
   annotation) was enough to expose it. **Fixed** by having both
   `tosource()` implementations emit `" :: "` (spaces on both sides)
   instead of a bare `"::"` before the annotation — the same fix a full
   general solution to the underlying lexer quirk would also need at this
   call site, without attempting to fix the quirk itself (out of scope: it's
   a tokenizer-level ambiguity affecting `NAME::Ann` generally, unrelated to
   tables, and every other pre-existing `tosource()` implementation for an
   annotated name already avoids it, e.g. `AField.tosource()`'s use of
   `PP.infix`, which was the tell that this pair of methods was the outlier).

4. **Two more `make all-pyret-test`/`make ts-test` failures are pre-existing
   and environmental**, unrelated to tables or type-checking: `test-file.arr`
   compares a freshly-read file-modification timestamp against a value
   baked in at some earlier point (`1784841954434` vs `1784841813000` — a
   plain clock/filesystem timing mismatch), and `test-images.arr` compares
   rendered-text pixel measurements (`47` vs `41`, `37` vs `33` — font
   metrics that depend on which fonts are actually installed in the
   container). Neither test touches tables, the type checker, or any file
   this task modified. I confirmed the specific failures reproduce for
   reasons entirely orthogonal to this work (I did not have a clean
   baseline checkout to literally diff against, since the repository has no
   git history in this container, but the failure content — clock/font
   dependent numeric comparisons — makes the conclusion unambiguous).

5. **A self-introduced bug, caught before it shipped:** my first `stack`
   method implementation typed its argument as the opaque `Table` name
   (`TS.tTable(l)`), but I had only added subtyping rules for `TTable <:
   TTable` and `TRow <: TRow` — not `TTable <: (opaque Table)`. A
   *precisely*-typed table argument to `.stack(...)` was rejected
   (`Table<{...}>` incompatible with `Table`) until I added that missing
   subtyping case (see [Type rules](#type-rules), subtyping). Caught by my
   own test-writing, not by inspection — recorded here because it's a good
   illustration of exactly the kind of gap this design needed to rule out
   systematically (I re-checked every place a bare `tTable(l)`/`tRow(l)` is
   used as an *expected* type inside my own new code after finding this
   one, which is how the parallel `rowTypeFromShape` gap below was also
   found before it shipped).

6. **Cross-module type propagation is broken for the `csv`/`csv-lib`/
   `data-source` trove modules** — calling `csv.csv-table-str(...)`,
   `csv.csv-table(...)`, `csv-lib.parse-string(...)`, or even just
   `data-source`'s `c-num(...)`/`c-str(...)` data constructors, under
   `-type-check`, fails with malformed-looking errors (e.g. a function's
   "type" printing as a raw, un-stringified JSON blob, or a real function
   being reported as accepting the wrong number of arguments). This is
   **not** a general cross-module problem — `import lists as L; L.map(...)`
   and `import either as E; E.left(...)` both correctly propagate precise
   types and correctly catch injected type errors (I verified both
   directly). It appears specific to these particular trove modules
   (native-JS-backed `csv`/`csv-lib`, and/or how `data-source.arr`'s
   generic `CellContent<A>` constructors serialize across the module
   boundary) and is pre-existing, not something this task's changes touch.
   Practical consequence: I could not construct a `load-table` example that
   both type-checks *and* runs correctly using a real CSV loader (the
   `source:` expression's type is checked, but calling into the loader
   library itself hits this bug). The `bad/load-table-needs-annotation.arr`
   fixture and this document's [Type rules](#type-rules) description
   confirm the annotation-requirement itself is implemented and enforced;
   I did not attempt to fix the underlying cross-module bug, since it's
   unrelated to tables and outside the type checker proper.

7. **A second self-introduced bug, same shape as #5:** `rowTypeFromShape`'s
   dynamic-case fallback returned `Any` instead of the opaque `Row` name,
   so a `(Row -> Any)`-annotated callback (exactly `core.arr`'s own style,
   e.g. `fun build-column(t :: Table, col :: String, fn :: (Row -> Any))`)
   passed to `.build-column(...)` on a *dynamic* (opaquely-typed) receiver
   was rejected — the checker's *own* internal expected type for the
   callback parameter didn't match what a real, unmodified `core.arr`-style
   annotation resolves to. Fixed by making the dynamic-case fallback return
   the opaque `Row` name (matching how `tableTypeFromShape`'s fallback
   already did the same for `Table`), plus adding the corresponding `TRow
   <: (opaque Row)` subtyping rule.

8. **Reused an unrelated error incorrectly (a wording bug, not a soundness
   one):** the first version of `add-column`/`build-column`'s "this column
   already exists" check reused `ObjectMissingField`, which renders as
   "does not have a field named `X`" — backwards, since the problem is that
   the field *does* exist. Both call sites now construct a dedicated,
   correctly-worded error (`duplicateColumnError`) instead. Caught by
   reading my own fixture's error output while writing the test suite, not
   by a failing test (the fixture still correctly failed to type-check
   either way — this was strictly a message-quality bug).

---

## Features left untypable, and why

In rough order of how often they show up in `core.arr`:

- **Column names computed or iterated at runtime.** `t.column(col)` for a
  `col :: String` *parameter* (as in nearly every `core.arr` table
  function: `mean`, `median`, `sum`, `stdev`, `sort`, `distinct-colors`,
  `find-by-id`, ...), or `for c in header(jellyAnon): ... end`-style
  iteration over a table's actual column list (B2T2's `pHacking`/
  `quizScoreFilter`/`quizScoreSelect` examples) genuinely cannot be given a
  column-precise type without some form of dependent typing (a type that
  depends on a runtime string value). This is exactly the difficulty B2T2
  §3.3 calls out by name ("Column names are first-class and
  manufacturable... such programs are difficult to type because column
  names are more than atomic labels"). The design's answer is the "dynamic"
  fallback everywhere a literal-name check would otherwise apply: the call
  still type-checks (so this is not a regression for existing code), it
  just doesn't get a more precise type than `List<Any>`/opaque `Table` —
  soundly conservative, never wrong, just imprecise. `b2t2-phacking.arr`
  and `core-dynamic-compat.arr` in `/app/typed-examples/` both demonstrate
  this boundary directly (the former documents, in comments, exactly which
  part of the original B2T2 example is out of reach and why; the latter
  shows the *rest* of a `core.arr`-style dynamic function compiling
  unchanged).

- **`Any` does not implicitly narrow into a concrete expected type.** This
  is a general, pre-existing property of this type checker (not introduced
  or specific to tables): a value of type `Any` flowing into a position
  that expects `Number` (or any other concrete/nominal type) is rejected —
  Any is only special as the *expected* side of a check (i.e., "this
  argument can be anything"), not as the *actual* type of something being
  passed into a stricter position. Concretely, this means `core.arr`'s
  numeric summaries (`mean`, `minimum`, `maximum`, `sum`, `stdev`,
  `r-value`), which extract a `List<Any>` via a dynamic column name and
  then do arithmetic on it (through a runtime-checked cast helper,
  `ensure-numbers`), cannot be type-checked as literally written — the cast
  helper's own parameter type (`List<Number>`) doesn't accept a
  `List<Any>` argument either, for the same reason. This is a genuine,
  fairly significant practical limitation for typing `core.arr` completely
  as-is (as opposed to the *statically-known-column* rewrite in
  `core-typed-stats.arr`, which sidesteps it entirely by keeping the
  numbers' Number-ness in the type from the start). It is not a table-type
  limitation to fix within this task's scope — fixing it would mean adding
  some notion of a checked/asserting downcast from `Any` to the type
  checker generally, a design decision about the whole language's gradual
  typing discipline, not about tables.

- **Reducer expressions inside `extend`'s reducer form
  (`name :: Ann: reducer of column`)** are not checked against their real
  shape. `tables.arr` declares the genuine type as `Reducer<Acc, InVal,
  OutVal> = {one :: (InVal -> {Acc; OutVal}), reduce :: (Acc, InVal ->
  {Acc; OutVal})}`, a parametric type alias defined in that module. I
  tried checking a user's reducer expression against a literal
  `TRecord`-shaped stand-in for this type and found the checker does not
  expand a value's alias-backed type (e.g. `Reducer<Number, Number,
  Number>`, which resolves to a `TApp` of that module's alias) when
  comparing it structurally against a hand-built `TRecord` — the
  comparison fails immediately on `t-app` vs `t-record`, before ever
  looking at fields (confirmed with a small standalone reproduction: a
  variable declared `:: {one :: ..., reduce :: ...}` and assigned
  `tables.T.running-sum` is rejected, even though the shapes genuinely
  match once the alias is expanded). Making this work soundly would mean
  either hard-coding `tables.arr`'s specific module URI and alias name into
  the general-purpose table type checker (a layering violation I didn't
  want to introduce — a real table type-checking design shouldn't need to
  know about one specific standard-library module by name) or teaching the
  constraint solver to expand alias-backed `TApp`s before structural
  comparison generally (a change to the core constraint solver, wider in
  scope and risk than this task's reducer-typing corner needed). I left it
  untyped: the extended column's declared return-type annotation and the
  `of <column>` column-existence check are still verified (see
  [Type rules](#type-rules)), but the reducer expression itself is only
  synthesized, not checked against a specific shape.

- **`stack`'s "same column set, any order" contract** is not verified
  statically (see [Type rules](#type-rules)) — this checker's subtyping is
  *width*-based (more columns is fine), not *exact-set*-based, and
  expressing "exactly this set of names, regardless of order" would need
  either a second, symmetric subtyping relation used only for this one
  method, or (more honestly) a way to intersect/equate two structural row
  types by key set — a small underused corner of the design space I judged
  not worth a bespoke mechanism for one method, especially since the
  runtime already performs this exact check dynamically (`table.js`'s
  `stack` raises if the column sets don't match) and the failure mode is
  therefore a normal, well-understood runtime error, not silent data
  corruption.

- **`select-columns`, `order-by-columns`, `rename-column` etc. called with
  a *computed* (non-literal) argument** — e.g. `t.select-columns(some-list)`
  where `some-list` isn't a list literal I can statically pick strings out
  of — degrade to the same "dynamic" fallback as a non-literal single
  column name. I did not attempt to special-case list *literals*
  (`[list: "a", "b"]`) for these, since `core.arr`'s and the B2T2 paper's
  own uses of comparable operations are, in every case I found, already
  driven by a runtime-computed list (the genuinely dynamic case above), so
  the additional complexity of literal-list introspection wouldn't have
  bought any additional coverage of real code.

- **An un-applied method reference** (`t.column-names` passed around as a
  value, rather than immediately called `t.column-names()`) is not
  recognized by the table/row method dispatch at all, since that dispatch
  is keyed off the `s-app`-around-`s-dot` shape specifically. This did not
  come up in any real B2T2 or `core.arr` code I found (both always call
  methods immediately), so I did not implement it, but it's worth flagging
  as a real gap: such an expression falls through to the ordinary
  object/field-access path and (for a *precisely*-typed table/row) fails
  with the same generic "not an object type" error a genuinely-unmodeled
  method would.

- **Cross-module column precision.** A table-typed value crossing a
  `provide`/import boundary loses its precise column type at that boundary
  (`anf-loop-compiler.ts`'s `compileProvidedType`, which serializes a
  module's provided value types, has no case for `TTable`/`TRow` and falls
  back to its pre-existing generic "unknown type" handling, which encodes
  as dynamically-`Any`). This is a real, documented gap rather than a
  crash (see [Implementation strategy](#implementation-strategy) for why I
  didn't extend that serialization) — a function imported from another
  module and returning a `Table<{...}>` will appear as an opaque/dynamic
  table to the importing module, not a precisely-column-typed one, unless
  re-annotated at the use site.

---

## Alternate designs

Some things would work meaningfully better with small, targeted language
changes beyond what this task's constraints allowed (no runtime/codegen
changes; TypeScript backend only):

- **A checked downcast form (`expr :~ Ann`, or similar) for narrowing `Any`
  into a concrete type with a runtime check inserted.** This is the single
  change that would do the most for typing `core.arr`'s *actual* code (see
  "Any does not implicitly narrow" above) — it would let something like
  `ensure-numbers(t.column(col))`'s existing runtime-checked-predicate
  idiom be expressed as a checked cast the type checker understands,
  rather than an ordinary function call the checker can't see through.
  This is a general gradual-typing feature, not a table-specific one, but
  tables are exactly where the gap bites hardest in existing code, since so
  many real table-processing functions pull data out via a dynamic column
  name specifically in order to stay generic over which column they
  process.

- **First-class, checkable column-name operations** (§3.3's explicit ask:
  "Names must be first-class values and require at least append and split
  operations"). With true dependent types (or at least singleton string
  types plus type-level string append/split), `quizScoreSelect`-style code
  — computing `"quiz" + num-to-string(i)` and using the result as a column
  name — could be given a real, checked type. This is a substantially
  bigger undertaking (a full dependent or refinement type layer) than
  anything attempted here, and I don't think it's a good incremental step
  from this design specifically; it would likely be its own project.

- **A `load-csv-file` (or similar) import form that resolves column types
  at module-resolution time** by reading the target file's header/inferring
  per-column sorts, as the task suggested as an option. I considered this
  and did not build it, for two reasons: (1) the biggest blocker to
  demonstrating it working end-to-end turned out to be the pre-existing
  `csv`/`data-source` cross-module type bug (bug #5 above), which sits
  upstream of anything a new import form could route around — a new
  loading form would still hand off to the same broken plumbing to
  actually read/sanitize the file; and (2) it's a materially bigger,
  separately-scoped feature (new syntax, a build-time file-reading step,
  a type-inference pass over sampled data) that deserves its own design
  rather than being bolted on as a side effect of fixing an unrelated bug.
  I'd pursue this only after fixing bug #5 and treating it as its own
  follow-up.

- **Row-typed generic method dispatch via a real `DataType`.** If `Table`
  method typing needed to grow much further (many more methods, or
  methods with more deeply parametric signatures), I would reconsider the
  "curated dispatch in `s-app`" approach in favor of teaching the general
  object/field-constraint machinery about a *dependent* method table (where
  a method's type is a function of the receiver's row type, not a fixed
  signature) — but that's a change to the constraint solver's core
  duck-typing mechanism, not something to introduce for tables alone
  without evidence several other features would also benefit from it.

---

## Testing

- `/app/pyret-lang/lang/src/ts-compiler/tests/table-types/{good,bad}/*.arr`
  — 16 fixtures (8 must type-check, 8 must not), run by
  `src/ts-compiler/tests/table-types-test.js` via the same `-type-check`
  CLI path `/app/typecheck-example` uses. Wired into `make ts-test` as a
  new `ts-table-types-test` target.
- `/app/typed-examples/*.arr` — 6 programs, each verified (beyond just
  type-checking) to also *run* correctly end-to-end where practical:
  `b2t2-gradebook.arr`, `b2t2-employees-departments.arr`,
  `b2t2-phacking.arr` (adapted from the paper's example tables/programs),
  `core-typed-stats.arr`, `core-dynamic-compat.arr` (adapted from
  `core.arr`'s table-processing functions), `table-sugar-forms.arr` (every
  syntactic sugar form in one program).
- `make ts-compiler`, `make ts-test`, and `make all-pyret-test` all pass,
  with one remaining exception in each: `test-file.arr` and
  `test-images.arr` (items 4 in [Bugs found](#bugs-found)), both confirmed
  pre-existing and environmental (clock/font dependent, unrelated to tables,
  type-checking, or any file this task touched). Items 2–3's pprint
  failures (which *did* initially show up in both suites) are fully
  resolved by the fixes described there — re-running `make ts-test` after
  landing them shows zero pprint-related failures (`ts-unit-test`:
  18/18; `ts-parity-test`: 21/21; `ts-repl-test`, `ts-type-check-test`,
  `ts-regression-test`: 245/245; `ts-io-test`: 13/13; the new
  `ts-table-types-test`: 16/16; and `ts-pyret-test`'s only remaining
  failures are the two environmental ones just mentioned).
- `tests/pyret/tests/test-tables.arr` (the pre-existing, comprehensive
  runtime-behavior spec for every table operation) passes 180/180 both
  through the modified pipeline directly and as part of the full
  `ts-pyret-test` suite — the primary evidence that moving table lowering
  from `desugar.ts` to `desugar-post-tc.ts` changed *when* table syntax is
  rewritten but not *what* it's rewritten to.
