#lang pyret

# B2T2 example program: dotProduct.
#
# "Computes the dot product of two columns in a table.  A type system should
#  ensure that the columns are in the table and that the sorts of these columns
#  describe numbers."
#
# The schema annotation `Table<{ quantity :: Number, price :: Number }>` says the
# table must have (at least) those two numeric columns.  Because `get-column`
# is typed against the schema, `quantities` and `prices` are inferred to be
# `List<Number>`, so the numeric `map2`/`foldl` below type-check.  Passing a
# column name that is absent, or whose column is non-numeric, is a type error.

import lists as L

fun dot-product(
    t :: Table<{ quantity :: Number, price :: Number }>) -> Number:
  doc: "Sum over rows of quantity * price."
  quantities = t.get-column("quantity")   # inferred :: List<Number>
  prices     = t.get-column("price")       # inferred :: List<Number>
  products = map2(lam(q, p): q * p end, quantities, prices)
  L.foldl(lam(acc, x): acc + x end, 0, products)
end

shopping = table: item, quantity, price
  row: "pepper",  2, 3
  row: "eggs",   12, 4
  row: "bread",   1, 2
end

total :: Number = dot-product(shopping)

check "dot product":
  total is (2 * 3) + (12 * 4) + (1 * 2)
end
