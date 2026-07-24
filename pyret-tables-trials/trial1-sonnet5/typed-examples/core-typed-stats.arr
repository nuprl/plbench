#lang pyret

# Adapted from Bootstrap's core.arr, which implements a small library of
# table-processing functions for its data-science curriculum (check-integrity,
# minimum, maximum, mean, median, stdev, sort, distinct-colors, and so on).
# core.arr's own signatures are written as `fun mean(t :: Table, col ::
# String) -> Number`, with the column name always a runtime String argument
# --- so most of the file is deliberately, unavoidably dynamic (see
# core-dynamic-compat.arr for that style working unchanged). This file shows
# the complementary, newly-typeable style: the same *operations* (build a
# numeric summary column, sort by it, drop helper columns), but written
# against a Table<{...}> whose numeric column is known by name and sort, so
# the checker verifies the column exists and is really numeric.

fun mean-of(t :: Table<{score :: Number}>) -> Number:
  scores = t.column("score")
  scores.foldl(lam(s, acc): acc + s end, 0) / scores.length()
end

fun minimum-of(t :: Table<{score :: Number}>) -> Number:
  t.column("score").foldl(lam(s, acc): num-min(s, acc) end, ~1000000)
end

# check-integrity (core.arr): "check that the table isn't empty, has all the
# necessary columns, and contains no blanks". The *set* of required columns
# in core.arr is a runtime List<String> (so it stays dynamic there), but a
# fixed, statically-known set of required columns -- the common case, one
# call site per shape of table -- can be expressed directly as the
# parameter's Table<{...}> annotation: the checker itself becomes the
# integrity check for column presence and sort, at compile time instead of
# via a runtime raise().
fun class-average(gradebook :: Table<{name :: String, score :: Number}>) -> Number:
  mean-of(select score from gradebook end)
end

# distinct-colors (core.arr) builds a new column by looking up each row's
# value in a color table -- the shape here is `build-column`, typed so the
# lambda's row parameter is a known Row<{...}>.
fun letter-grade(score :: Number) -> String:
  if score >= 90: "A"
  else if score >= 80: "B"
  else if score >= 70: "C"
  else: "F"
  end
end

fun with-letter-grades(t :: Table<{name :: String, score :: Number}>) -> Table<{name :: String, score :: Number, grade :: String}>:
  t.build-column("grade", lam(r): letter-grade(r.get-value("score")) end)
end

# sort (core.arr): "if the column is [...] sort case-insensitively [...]
# otherwise sort directly" -- simplified here to the numeric, known-column
# case, using order-by.
fun by-score-descending(t :: Table<{score :: Number}>) -> Table<{score :: Number}>:
  t.order-by("score", false)
end

gradebook :: Table<{name :: String, score :: Number}> =
  table: name, score
    row: "Bob", 72
    row: "Alice", 91
    row: "Eve", 85
  end

print(class-average(gradebook))
print(minimum-of(gradebook))
print(with-letter-grades(gradebook).column("grade"))
print(by-score-descending(gradebook).column("score"))
