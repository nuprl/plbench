#lang pyret

# Writing and reading the new table types.
#
#   Table<{ c1 :: T1, ..., cn :: Tn }>   a table with (at least) those columns
#   Row<{ c1 :: T1, ..., cn :: Tn }>     a row of such a table
#   Table   /   Row                       a table/row of unknown schema
#
# This program shows:
#   * annotating function parameters with schema types
#   * width subtyping: a table with MORE columns is accepted where FEWER are
#     required (sound because tables are immutable)
#   * schema tracking through row-preserving (order-by) and schema-changing
#     (drop) operations

# Requires a numeric `score` column; ignores any other columns.
fun best-score(t :: Table<{ score :: Number }>) -> Number:
  sorted = t.order-by("score", false)   # keeps the schema: Table<{score :: Number}>
  sorted.row-n(0)["score"]
end

# Consumes a specific row shape.
fun label(r :: Row<{ name :: String, score :: Number }>) -> String:
  r["name"] + ": " + num-to-string(r["score"])
end

results = table: name, score, notes
  row: "Bob",   77, "ok"
  row: "Alice", 91, "great"
  row: "Eve",   84, "good"
end

# `results` has columns name/score/notes; `best-score` only needs `score`.
top :: Number = best-score(results)

# `drop` removes a column from the schema; the result no longer has `notes`.
trimmed = results.drop("notes")
first-label :: String = label(trimmed.row-n(0))

check:
  top is 91
  first-label is "Bob: 77"
end
