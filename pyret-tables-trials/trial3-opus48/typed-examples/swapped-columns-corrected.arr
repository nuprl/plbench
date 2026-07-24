#lang pyret

# B2T2 Errors: "swappedColumns" (Figure 5) -- corrected version.
#
# The malformed constant declared a schema (name :: String, age :: Number,
# favorite-color :: String) but put the *values* in the wrong order, so a row
# had a Number where a String was expected.  Our type checker catches that in
# two ways:
#
#   (1) With per-column annotations on the headers, each cell is checked against
#       its column's declared type, so a swapped cell is a type error.
#   (2) Even WITHOUT annotations, a column that mixes (say) Number and String
#       cells is reported as non-homogeneous.
#
# This file is the corrected constant; it type-checks.  Its schema is carried
# forward so downstream row/column access is precisely typed.

students = table: name :: String, age :: Number, favorite-color :: String
  row: "Bob",   12, "blue"
  row: "Alice", 17, "green"
  row: "Eve",   13, "red"
end

r = students.row-n(1)
who   :: String = r["name"]
years :: Number = r["age"]
color :: String = r["favorite-color"]

check:
  who is "Alice"
  years is 17
  color is "green"
end
