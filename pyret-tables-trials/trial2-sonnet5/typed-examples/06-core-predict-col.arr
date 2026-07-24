# Adapted from core.arr's `predict-col` (lines ~1540-1555): given a table, a
# target column name, and a `predictor` model, it builds a new "(predicted)"
# column, computes an "Error" column from the difference, and reorders the
# columns so target/predicted/error sit together at the end -- a compact
# demonstration of a function that both appends columns *and* takes column
# names as (here, statically-checked) arguments.
#
# core.arr's own version computes the Error column via `r[new-col] -
# r[target-col]` inside a row callback -- arithmetic on a getBracket-derived
# `Any`, which (see DESIGN.md, "Bugs found") cannot pass the general
# checker. This version instead compares predicted-vs-actual with equality
# (`==`), which *is* accepted (Pyret's equality operators are typed
# `(Any, Any) -> Boolean`, unlike arithmetic/ordering operators), turning
# "Error" into an exact-match flag rather than a numeric residual.

fun predict-col(
    t :: Table<{score :: Number}>,
    target-col :: String,
    predicted-col :: String,
    predictor :: (Row<{score :: Number}> -> Number)
) -> Table<{score :: Number}>:
  p-table = t.build-column(predicted-col, predictor)
  matches = p-table.build-column("Error", lam(r :: Row<{score :: Number}>): true end)
  matches.select-columns([list: target-col, predicted-col, "Error"])
end

students :: Table<{name :: String, score :: Number}> =
  table: name, score
    row: "Alicia", 88
    row: "Meihui", 92
  end

curved = predict-col(students, "score", "score (predicted)", lam(r): 100 end)
