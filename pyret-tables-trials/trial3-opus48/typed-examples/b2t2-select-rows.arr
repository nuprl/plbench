#lang pyret

# B2T2 Table API: selectRows / filter, plus a schema-preserving pipeline.
#
#   filter :: t1:Table * f:(r:Row -> Boolean) -> t2:Table
#
# The predicate's parameter is typed as a `Row` of the table's schema, so column
# accesses inside it are checked.  `filter`/`order-by` preserve the schema, so
# the whole pipeline stays precisely typed and the final row access is checked.

gradebook = table: name, age, midterm, final
  row: "Bob",   12, 77, 87
  row: "Alice", 17, 88, 85
  row: "Eve",   13, 84, 77
end

# selectRows: keep students who passed the midterm.  `r["midterm"]` is Number.
passed = gradebook.filter(lam(r): r["midterm"] >= 80 end)

# schema-preserving order + column extraction
ranked = passed.order-by("final", false)
top-name :: String = ranked.row-n(0)["name"]
finals   :: List<Number> = ranked.get-column("final")

check:
  top-name is "Alice"
  finals.length() is 1
end
