#lang pyret

# Adapted (close to verbatim) from Bootstrap's core.arr. Its table functions
# are written against a bare `Table` and a runtime `col :: String` column
# name (e.g. `fun mean(t :: Table, col :: String) -> Number`, `r[col]`
# inside `build-column`/`sort`), which a type system cannot verify precisely
# without dependent types (see DESIGN.md's "left untypable" section: which
# column `col` names isn't known until the program runs). Since a bare
# `Table`/`Row` annotation is treated as an opaque, columnless value (see
# tableShapeOf/rowShapeOf in type-check.ts) -- not rejected, just given no
# column-level guarantees -- this core.arr-style code continues to compile
# completely unchanged. This file exists to demonstrate exactly that
# backward-compatibility guarantee, side by side with core-typed-stats.arr's
# newly-precise style for the statically-known-column case.

fun check-integrity(t :: Table, cols :: List<String>) block:
  t-cols = t.column-names()
  for each(c from cols):
    when not(t-cols.member(c)):
      raise("'" + c + "' is not a column in this table. Columns are: " + t-cols.join-str(", "))
    end
  end
  if (t.all-rows().length() == 0):
    raise("This table contains no data rows (it's empty!)")
  else:
    nothing
  end
end

# core.arr's numeric summaries (mean, minimum, maximum, sum, stdev, ...) go
# one step further than this file's other functions: they pull a List<Any>
# out via a dynamic column name and then do arithmetic on its elements (via
# a cast helper, `ensure-numbers :: (List<Number>%(is-all-numbers)) ->
# List<Number>`, whose *runtime* predicate double-checks what the type
# system can't). That last step is where this checker's gradual typing
# stops helping: Any does not implicitly narrow into a concrete expected
# type such as Number/List<Number> (a general property of this checker, not
# particular to tables -- seeAny is only permissive as an *expected* type,
# not as an *actual* one flowing into a concrete position), so a literal
# `ensure-numbers(t.column(col))` does not type-check here. See DESIGN.md's
# "left untypable" section. The rest of core.arr's table-processing
# functions below are unaffected and compile exactly as originally written.

# core.arr's `sort`, simplified to its `else` branch: `col` and the row
# bracket-index `r[col]` are both dynamic (a runtime String, not a literal),
# exactly the style tableShapeOf/rowShapeOf keep permissive rather than
# rejecting. (core.arr's other branches additionally call `string-to-lower`
# on the looked-up cell -- `r[col]`'s type is Any, since `col` isn't a
# literal, and Any does not implicitly narrow into `string-to-lower`'s
# concrete String parameter, the same general limitation noted above for
# `ensure-numbers`; omitted here for that reason, not a table-specific one.)
fun sort-by(t :: Table, col :: String, asc :: Boolean):
  t.order-by(col, asc)
end

fun build-col(t :: Table, col :: String, fn :: (Row -> Any)):
  t.build-column(col, fn)
end

# Another general (non-table-specific) consequence of Any not narrowing
# into a concrete position: inside a callback typed `(Row -> Any)` for a
# fully dynamic Table/Row (build-col above doesn't know the column names),
# `r.get-value(...)`'s result is Any, and Any does not support the magic
# `_plus`/`_greaterequal`/etc. operator dispatch (`>=`, `+`, ...) that a
# concrete Number would -- only ordinary function application on it, like
# `is-number` below, which just takes Any and returns Boolean.
fun is-adult-row(r :: Row):
  is-number(r.get-value("age"))
end

fun stack-tables(first-table :: Table, rest-tables :: List<Table>):
  rest-tables.foldl(lam(t, base): base.stack(t) end, first-table)
end

tbl = table: name, age
  row: "Bob", 12
  row: "Alice", 15
  row: "Eve", 13
end

check-integrity(tbl, [list: "age"])
print(sort-by(tbl, "name", true).column("name"))
print(build-col(tbl, "is-adult", is-adult-row).column("is-adult"))
print(stack-tables(tbl, [list: tbl]).length())
