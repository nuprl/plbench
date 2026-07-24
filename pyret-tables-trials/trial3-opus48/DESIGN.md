# Static Type Checking for Tables in Pyret

This document describes a table-aware extension to the **TypeScript** Pyret
type checker (`/app/pyret-lang/lang/src/ts-compiler/`). It adds *schema-carrying*
table and row types so that programs constructing and operating on tables — the
b2t2 Table API and the table helpers in Bootstrap's `core.arr` — are checked
with column-level precision, while remaining sound and leaving the runtime and
code generation untouched.

Everything here is exercised by:

* `/app/typecheck-example FILE.arr` — type-checks one program (exit 0 iff OK).
* `/app/typed-examples/*.arr` — worked programs adapted from b2t2 and `core.arr`.
* `/app/table-type-tests/` — a good/bad regression suite (`run-table-tests.sh`).

---

## 1. The type grammar

Two new *surface* type forms, written with Pyret's existing annotation syntax
(no parser changes were needed — record annotations are already legal type-app
arguments):

```
Table<{ c1 :: T1, c2 :: T2, ..., cn :: Tn }>     -- a table with those columns
Row<{ c1 :: T1, c2 :: T2, ..., cn :: Tn }>       -- one row of such a table
Table                                            -- a table of unknown schema
Row                                              -- a row of unknown schema
```

The type argument is an ordinary **record annotation** whose fields are the
column names and whose field types are the *element* types of those columns.
This directly models the b2t2 notion of a schema (a map from column name to
sort) and captures the two properties that make tables interesting: columns are
**heterogeneous** (each field may have a different type) and column names are
**first-class labels** (they are record field names).

### Internal representation

No new `Type` variant was introduced. A schema-carrying table/row reuses the
existing `t-app` and `t-record` machinery:

```
Table<{...}>   ==   TApp(TName "Table", [ TRecord({...}) ])
Row<{...}>     ==   TApp(TName "Row",   [ TRecord({...}) ])
Table          ==   TName "Table"            (bare: unknown schema)
Row            ==   TName "Row"              (bare: unknown schema)
```

Reusing `t-app(t-name, [t-record])` means substitution, free-variable
computation, alpha-equivalence, structural equality, hashing (`key()`), and
pretty-printing all work on table types **for free** — the record already
handles column-name/column-type book-keeping. The bare names `Table`/`Row`
(what `core.arr` writes, and what data from unknown sources gets) denote an
unknown schema. `Table`/`Row` were changed from aliases for `Any` to these named
types (`compile-structs.ts`, and a new `TS.tRow` constructor in
`type-structs.ts`).

### How to read/write the types

* You **write** `Table<{...}>` / `Row<{...}>` on `fun`/`lam` parameters, `let`
  bindings, and return annotations, exactly like any other annotation.
* You can annotate **table-literal headers** to *fix* a column's type:
  `table: name :: String, age :: Number ... end`. Cells are then checked against
  the declared column type.
* Omit the schema (`Table` / `Row`) whenever the columns are computed
  dynamically (e.g. a `String`-valued column-name parameter). This is the
  conservative "some table" and is what most `core.arr` helpers use.

---

## 2. Type rules

### 2.1 Table literals (schema synthesis)

Pyret desugars `table:` / `load-table` **before** type-checking, so the checker
sees a primitive application `makeTable(headers, rows)`. When `headers` is an
array of string **literals** and `rows` is an array of row-arrays (i.e. a real
table constant), the checker:

1. reads the column names from the header literals (rejecting **duplicate**
   columns — b2t2 requires distinct columns);
2. checks the table is **rectangular** (every row has one cell per column);
3. synthesizes each cell's type and computes each column's type:
   * if the header was annotated `c :: T`, every cell is checked against `T`
     (the desugarer wraps cells in an annotation check), and the column type is
     `T`;
   * otherwise the column type is inferred: identical cell types collapse to
     that type; a column that mixes two distinct closed scalar types (e.g.
     `Number` and `String`) is reported as **non-homogeneous** (this catches the
     b2t2 "swappedColumns"/malformed-constant error family even without
     annotations); anything else widens soundly to `Any`.

The result is `Table<{ c1 :: T1, ... }>`.

### 2.2 Row access

* `r.col` (dot) and `r["col"]` (bracket; desugars to a `getBracket` primitive)
  on a `Row<S>` with a **literal** column name resolve to `S[col]`. An unknown
  column is a type error listing the row's columns.
* On a bare `Row`, or with a non-literal column name, the result is `Any`
  (sound: reading is always safe).

### 2.3 Table methods

Table/row **method calls** survive desugaring intact (`t.get-column("x")` is an
ordinary method application), so they are typed directly, keying off literal
string column-name arguments. Given a receiver of type `Table<S>` (`S` may be
unknown), for literal column names `c`:

| method | result | notes |
|---|---|---|
| `row-n(n)` | `Row<S>` | |
| `all-rows()` | `List<Row<S>>` | |
| `length()` | `Number` | |
| `column-names()` | `List<String>` | |
| `get-column(c)` / `column(c)` | `List<S[c]>` | `c` must be in `S` |
| `column-n(n)` | `List<Any>` | column unknown by index |
| `order-by(c, asc)` / `increasing-by(c)` / `decreasing-by(c)` | `Table<S>` | `c` must be in `S` |
| `filter(f)` | `Table<S>` | `f` checked at `(Row<S> -> Boolean)` |
| `filter-by(c, f)` | `Table<S>` | `f` checked at `(S[c] -> Boolean)` |
| `drop(c)` | `Table<S \ c>` | `c` removed from the schema |
| `build-column(c, f)` | `Table<S ++ {c : V}>` | `c` fresh; `f : (Row<S> -> V)`, `V` inferred |
| `add-column(c, vs)` | `Table<S ++ {c : V}>` | `c` fresh; `vs : List<V>` |
| `transform-column(c, f)` | `Table<S[c := V]>` | `c` in `S`; `f : (Row<S> -> V)` |
| `rename-column(a, b)` | `Table<S renamed>` | `a` in `S`, `b` fresh |
| `stack(t2)` | `Table<S>` | `t2`'s schema must **equal** `S` |
| `add-row(r)` | `Table<S>` | `r`'s schema must **equal** `S` |
| `empty()` | `Table<S>` | |

Row methods: `get-value(c) : S[c]`, `get(c) : Option<S[c]>`,
`get-column-names() : List<String>`.

The interesting b2t2 constraints fall out of these rules: `build-column`
enforces "`c` is not in `header(t1)`" (freshness) and produces
`concat(header(t1), [c])` with the new column's sort equal to the row function's
result sort; `transform-column`/`drop`/`rename-column` track the schema through
the operation; `get-column` enforces "`c` is in the table and describes numbers"
by giving the caller a `List<Number>` only when the schema says so.

### 2.4 Subtyping

* `Table<S> <: Table` and `Row<S> <: Row` — a known schema may be used where an
  unknown one is expected (so tables print, pass to `Any`, etc.).
* `Table<S1> <: Table<S2>` and `Row<S1> <: Row<S2>` use **record (width +
  depth) subtyping** on the schema: `S1` may have *more* columns than `S2`, and
  each shared column's type is covariant. This is what lets `dot-product`
  (needs `{quantity, price}`) accept a `{item, quantity, price}` table.
* Bare `Table`/`Row` is **not** a subtype of any specific schema (you cannot
  invent columns), so unknown-source data must be annotated before precise use.

**Soundness of width subtyping.** Tables and rows are immutable, so reading
columns through a narrower view is safe. The operations that inspect the *exact*
column set (`stack`, `add-row`) require schema *equality* (checked with
bidirectional constraints), and `build-column`/`add-column` freshness is a
best-effort static check. When a narrowed static view hides a column, the worst
that can happen is a **domain exception** at runtime ("column already exists",
"tables have different columns") — the same class of runtime error Pyret already
permits for `empty.first`, out-of-range indexing, or empty cells. No value ever
flows at a type it doesn't have, which is the soundness property the checker
guarantees. (An alternative that removes even these domain exceptions — full row
polymorphism — is discussed in §6.)

---

## 3. Implementation strategy

Table syntax is desugared **before** type-checking
(`compile-lib.ts`: `desugar` then `typeCheck`), so the checker never sees
`s-table*` nodes; it sees `makeTable` primitive applications and runtime method
calls. Rather than re-order desugaring (which would risk code-generation
changes, which are forbidden), the design **recovers schemas from the desugared
form**:

* **`makeTable`** literal → schema synthesis (`synthesisMakeTable`), hooked into
  the `s-prim-app` case of `synthesis`.
* **`getBracket`** (desugared `r["c"]`) → row column type (`synthesisGetBracket`),
  same hook.
* **`obj.method(args)`** → intercepted in the `s-app` case (`synthesisDotApp`).
  It synthesizes the receiver once; if it is a table/row, precise method typing
  runs (`synthesisTableMethod`); otherwise (and for methods not modelled
  precisely) it replays the normal field-access-then-apply path, so non-table
  code is completely unaffected.
* **Field access / deferred inference.** When a table/row is reached through
  inference rather than syntactically (e.g. a polymorphic `foldl` accumulator
  of type `List<Table>`), the receiver's type is an unsolved existential at
  access time. For these, `instantiateObjectType` presents a Table/Row as a
  **record of its methods** (`tableRowMethodRecord`), so the ordinary
  field-constraint solver resolves the method conservatively.

Almost all the new logic lives in three places:

* `type-check.ts` — schema synthesis, method typing, row access, and the two
  synthesis hooks (one self-contained section, ~430 lines).
* `type-check-structs.ts` — Table/Row subtyping in `solveHelperConstraints`,
  the method-record presentation in `instantiateObjectType`.
* `type-defaults.ts` / `compile-structs.ts` / `type-structs.ts` — `Row`
  constructor, `Table`/`Row` as named types, and sound types for the primitives
  that table sugar desugars into.

Key principle: **literal column names are the source of precision.** Wherever a
column name is a string literal it is checked against the schema; wherever it is
a dynamic `String` the result degrades soundly to `Any`/bare `Table`. This is
why `core.arr`'s dynamic-column helpers type-check at the bare-`Table` level
while table *literals* and literal-name method calls are checked precisely.

---

## 4. Bugs found

* **`UnboundId.renderReason` crash (`compile-errors.ts`).** The renderer assumed
  the unbound expression is an `s-id` (`this.id.id.toname()`); for an unbound
  **primitive application** (`s-prim-app`, whose name is in `._fun`) this threw
  `Cannot read properties of undefined (reading 'toname')`, turning a clean type
  error into a compiler crash. Fixed with a small `idName()` fallback that reads
  `._fun` when there is no `.id`. This is a general robustness fix (any unbound
  primitive now reports cleanly), independent of tables.

* **Untyped table-sugar primitives.** `checkWrapTable` and several `raw_array_*`
  primitives emitted by the table desugarings had no type in the checker, so any
  program exercising that sugar produced an unbound-id (and, via the bug above,
  a crash). They now have sound, conservative types (`type-defaults.ts`).

---

## 5. Features left untypable (and why)

* **`extend` / `transform` / `sieve` / `order` sugar.** These desugar (before
  type-checking) into low-level `raw-array-map-1` / `raw_array_get` loops and
  heterogeneous `[raw-array: bool, string]` literals that the checker cannot
  reconstruct a schema from; some also hit an unrelated limitation (the checker
  requires array literals to be homogeneous). They are left to type at the
  conservative bare-`Table` level or, where the desugaring is intractable,
  rejected soundly. **The precise, schema-tracking path for every one of these
  is the equivalent method** (`build-column`/`transform-column`/`filter`/
  `order-by`), which *is* fully typed. (`select ... from` and `extract ... from`
  do type-check.) Moving table desugaring to *after* type-checking would fix
  this — see §6.

* **Fully dynamic (manufacturable) column names.** b2t2's `quizScoreSelect`
  builds column names by string append (`"quiz" + n`) and selects them. Because
  the name is not a literal, the schema cannot be computed; such code types at
  the bare-`Table` / `List<Any>` level (sound, imprecise). Precisely typing it
  needs singleton-string types or first-class name types (§6).

* **Empty cells / missing data.** b2t2 allows blank cells (`gradebookMissing`).
  Pyret has no literal for an empty cell, so this benchmark table cannot be
  written as a constant; a column that a program fills with `Option` values is
  typeable as `Table<{c :: Option<T>}>`, but there is no automatic
  null-propagation.

* **`orderBy` with per-key existential comparators** (the b2t2
  `Seq<Exists K. getKey * compare>` signature) is not expressible; the
  Pyret-idiomatic `order-by(column, ascending)` method is typed instead.

* **`load-table` from external sources** yields a bare `Table`; its schema is
  unknown at compile time and must be annotated. (§6 sketches a CSV import form
  that could compute it.)

---

## 6. Alternate designs that would need language changes

* **Row polymorphism instead of width subtyping.** Writing
  `Table<{ score :: Number | R }>` with an explicit *rest* row variable `R`
  would make "a table with at least these columns" first-class and remove even
  the domain-exception cases in §2.4: `build-column` could then *require* a
  closed schema (no `R`) to guarantee freshness statically, while read-only
  consumers quantify over `R`. This needs new annotation syntax (a rest variable
  in record annotations) and row-variable inference in the solver. It is the
  principled endpoint of this design.

* **Singleton string / first-class column-name types.** Typing
  manufacturable names (`"quiz" + num-to-string(n)`) precisely needs the type of
  a `String` *literal* to be a singleton, plus type-level append/compare on
  those singletons (à la TypeScript template-literal + `keyof`). This would let
  `select-columns`/`get-column` be precise for computed names. It is a
  significant type-system addition.

* **Desugar tables *after* type-checking.** The single biggest structural
  improvement: keep `s-table` / `s-table-extend` / `s-table-select` / … as AST
  nodes through type-checking (desugaring them in `desugar-post-tc.ts` instead of
  `desugar.ts`). The checker could then give `extend`/`transform`/`sieve`/`order`
  the same precise schema tracking the methods already get, and report errors
  in terms of the surface syntax (e.g. point at the offending cell of a
  malformed constant). The desugarer's own comments flag this as the intended
  eventual structure. It was avoided here only because reordering desugaring
  risks perturbing code generation, which the task forbids changing.

* **A schema-computing CSV import form.** A new `import table("data.csv")`
  resolver that reads the header row (and samples cells) at module-resolution
  time could synthesize a `Table<{...}>` type for external data, removing the
  need to hand-annotate `load-table` results. This is additive (a new import
  form + locator) and does not affect the core type rules above.

---

## 7. Test status

* `/app/table-type-tests/run-table-tests.sh` — 8 positive examples + 14 negative
  programs, all behaving as expected (positives type-check, negatives are
  rejected with a specific error).
* `make all-pyret-test` and `make ts-test` — the type-checker unit tests
  (`18/0`), parity (`21/0`), repl, and type-check corpus pass. Two check-blocks
  fail **identically under both the untouched regular `.arr` compiler and the
  modified TypeScript compiler**, so they are pre-existing and environmental,
  not caused by this work:
  * `tests/pyret/tests/test-file.arr` — asserts `ctime <= mtime` on a source
    file; on a freshly extracted checkout the change-time exceeds the archived
    modification-time, so the predicate is false.
  * `tests/pyret/tests/test-images.arr` — asserts exact pixel metrics of rendered
    text, which depend on the host's font rasterization.

  The failing set is byte-for-byte identical between the two backends
  (`test-file.arr:4`, `test-images.arr:172`), confirming the table type checker
  introduces no new failures. (These compile and *run*; only their runtime
  values differ from the hard-coded expectations, which no type-checker change
  can affect.)

## 8. File-by-file summary of changes

* `src/type-structs.ts` — add `tRow` constructor (mirror of `tTable`).
* `src/compile-structs.ts` — `Table`/`Row` are named types, not aliases for
  `Any`.
* `src/type-defaults.ts` — sound types for `checkWrapTable` and the
  `raw_array_*` / `raw-array-*` table-sugar primitives.
* `src/type-check.ts` — the table-typing section: schema synthesis from
  `makeTable`, `getBracket` row access, precise method typing, and the
  `s-app` / `s-prim-app` hooks.
* `src/type-check-structs.ts` — Table/Row subtyping (schema forgetting + width),
  and the method-record presentation of Table/Row in `instantiateObjectType`.
* `src/compile-errors.ts` — robustness fix for `UnboundId` rendering.
