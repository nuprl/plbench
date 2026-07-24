# Adapted from core.arr's `group` (lines ~1923-1930) and `count`
# (~1932-1938), which build a two-column `value`/`subtable` table by
# filtering the source table for each distinct value of a chosen column,
# then stacking the results together.
#
# Two adaptations from the original were needed to make this pass under
# /app/typecheck-example (see DESIGN.md, "Bugs found"):
#  - core.arr uses `for fold(...)`; this checker's general (unmodified)
#    bidirectional checker cannot yet infer the accumulator's type through
#    that specific desugaring when it is table-shaped, so this version uses
#    `L.fold` with an explicit lambda instead (semantically identical).
#  - `filter-by`'s predicate here uses equality (`cell == v`) rather than
#    core.arr's dynamically-dispatched `val == v` on possibly-non-String
#    values; kept to String columns so the predicate's own operand types are
#    unambiguous.
#  - core.arr's `count` reads the row-bound `subtable` cell out of a Row via
#    bracket access (`r["subtable"]`) and calls `.length()` on it. Every
#    table/row cell access necessarily synthesizes as `Any` to the general
#    checker (see DESIGN.md, "Bugs found" -- getBracket has no way to know
#    it is being used on a Row with a statically-known schema), and `Any`
#    cannot itself be the target of a further dot-call under the general
#    checker (`Any` is not "an object type"). table-check.ts *does* give
#    `r["subtable"]` its precise `Table` element type, but that extra
#    precision is not (in this implementation) threaded back into the
#    general checker's own judgment of the same subexpression -- seeing
#    both agree is what /app/typecheck-example ultimately reports. So
#    `count` below builds one single-row table per distinct value (in the
#    same style as `group`, just computing the row's length directly)
#    instead of reading a subtable back out of a cell.
#
# core.arr's own `group`/`count` are intentionally left untouched/unadapted
# in place -- see DESIGN.md for why (they take a bare `Table`/String column
# name with no static schema, which is a legitimate, still-supported way to
# write table code that this project's checker simply does not add
# precision to).

import lists as L

fun make-group-row(source :: Table<{status :: String}>, v :: String) -> Table<{value :: String, subtable :: Table}>:
  table: value, subtable
    row: v, source.filter-by("status", lam(cell): cell == v end)
  end
end

fun group(source :: Table<{status :: String}>, distinct-values :: List<String>) -> Table<{value :: String, subtable :: Table}>:
  L.fold(
    lam(grouped, v): grouped.stack(make-group-row(source, v)) end,
    table: value, subtable end,
    distinct-values)
end

fun count-row(source :: Table<{status :: String}>, v :: String) -> Table<{value :: String, frequency :: Number}>:
  matching = source.filter-by("status", lam(cell): cell == v end)
  table: value, frequency
    row: v, matching.length()
  end
end

fun count(source :: Table<{status :: String}>, distinct-values :: List<String>) -> Table<{value :: String, frequency :: Number}>:
  L.fold(
    lam(acc, v): acc.stack(count-row(source, v)) end,
    table: value, frequency end,
    distinct-values)
end

people :: Table<{name :: String, status :: String}> =
  table: name, status
    row: "Alicia", "active"
    row: "Meihui", "inactive"
    row: "Jamal", "active"
  end

grouped-by-status = group(people, [list: "active", "inactive"])
status-counts = count(people, [list: "active", "inactive"])
