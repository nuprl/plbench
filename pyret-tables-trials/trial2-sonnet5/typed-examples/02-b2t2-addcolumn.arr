# Adapted from the B2T2 "Sample API Entry" for `addColumn` (b2t2-paper.txt,
# Figure 3, the `hairColor` example): "Consumes a column name and a Seq of
# values and produces a new Table with the columns of the input Table
# followed by a column with the given name and values." b2t2 requires the
# column name be fresh and the value sequence's length match the table's
# row count; table-check.ts checks the freshness statically (the length
# match is still a dynamic check, exactly like Table's existing dynamic
# checks for e.g. column existence -- see DESIGN.md).
#
# This is also the paper's own suggested fallback for languages (like this
# checker) that cannot give `buildColumn`'s row-computing callback a fully
# generic type: "ask for a...pre-built sequence" instead (b2t2-paper.txt
# lines 612-618). Building `hairColor` here from an ordinary, independently
# well-typed `List<String>` keeps the whole example inside what both the
# general checker and table-check.ts can verify.

import lists as L

students :: Table<{name :: String, age :: Number}> =
  table: name, age
    row: "Alicia", 30
    row: "Meihui", 40
    row: "Jamal", 25
  end

hair-color = [list: "brown", "red", "blonde"]

with-hair-color :: Table<{name :: String, age :: Number, hair-color :: String}> =
  students.add-column("hair-color", hair-color)

# A column can also be computed from other in-scope, ordinarily-typed data
# (not the table itself) -- e.g. an "is-adult" flag derived from a parallel
# list of ages built independently of the table.
ages = [list: 30, 40, 25]
adult-flags = L.map(lam(a :: Number): a >= 18 end, ages)

with-adult-flag :: Table<{name :: String, age :: Number, is-adult :: Boolean}> =
  students.add-column("is-adult", adult-flags)
