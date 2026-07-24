#lang pyret

# Adapted from the Bootstrap "core" library (core.arr).  These are the
# consumer-style table helpers that take a table and *dynamic* (String-valued)
# column names.  Because the column name is not a literal, the exact column
# type is not known statically, so these are typed against the conservative
# bare `Table` / `Row` (unknown schema): sound, and enough to check arity,
# argument types, and the shape of results.

import lists as L

# core.arr: fun stack-table(t1 :: Table, t2 :: Table): t1.stack(t2) end
fun stack-table(t1 :: Table, t2 :: Table) -> Table:
  t1.stack(t2)
end

# core.arr: fun stack-tables(ts): L.fold(..., ts.first, ts.rest) end
# (rewritten to take the first table explicitly, since the TS checker does not
#  model the partial `.first`/`.rest` accessors on the `List` type.)
fun stack-tables(first-t :: Table, rest :: List<Table>) -> Table:
  L.foldl(lam(base, t): base.stack(t) end, first-t, rest)
end

# core.arr: fun build-column(t, col, fn): t.build-column(col, fn) end
fun build-column(t :: Table, col :: String, fn :: (Row -> Any)) -> Table:
  t.build-column(col, fn)
end

# core.arr: fun transform-column(t, col, fn): t.transform-column(col, fn) end
fun transform-column(t :: Table, col :: String, fn :: (Row -> Any)) -> Table:
  t.transform-column(col, fn)
end

# core.arr: fun row-n(t :: Table, n :: Number): t.row-n(n) end
fun nth-row(t :: Table, n :: Number) -> Row:
  t.row-n(n)
end

# core.arr statistics helpers reduce a named column to a list of values.
fun sorted-column(t :: Table, col :: String) -> List<Any>:
  t.column(col).sort()
end

fun num-rows(t :: Table) -> Number:
  t.all-rows().length()
end

# --- exercise the helpers on a concrete table ---
inventory = table: item, count
  row: "apple",  3
  row: "pear",   5
end

more = table: item, count
  row: "plum", 2
end

combined = stack-table(inventory, more)
tagged = build-column(combined, "fresh", lam(r): true end)

check:
  num-rows(combined) is 3
  nth-row(inventory, 0).get-value("item") is "apple"
end
