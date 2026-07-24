#lang pyret

# B2T2 Table API entry: addColumn / buildColumn.
#
#   addColumn :: t1:Table * c:ColName * vs:Seq<Value> -> t2:Table
#   buildColumn :: t1:Table * c:ColName * f:(r:Row -> v:Value) -> t2:Table
#
# Ensures:
#   header(t2) is equal to concat(header(t1), [c])
#   schema(t2)[c] is the sort of elements of vs / the result sort of f
#
# Our `build-column`/`add-column` typing implements exactly this: the new
# table's schema is the old schema extended with the new column, whose type is
# the return type of the row function (build-column) or the list element type
# (add-column).  The row function's parameter is typed as a `Row` of the input
# schema, so `r["age"]` inside is checked against the schema and is a Number.

students = table: name, age, favorite-color
  row: "Bob",   12, "blue"
  row: "Alice", 17, "green"
  row: "Eve",   13, "red"
end

# buildColumn: the "is-adult" column has type Boolean because the row function
# returns a Boolean.
with-adult =
  students.build-column("is-adult", lam(r): r["age"] >= 18 end)

# addColumn: hair-color has type String because the value list is List<String>.
with-hair =
  with-adult.add-column("hair-color", [list: "brown", "red", "blonde"])

# The extended schema is visible to subsequent row access:
first = with-hair.row-n(0)
adult  :: Boolean = first["is-adult"]
hair   :: String  = first["hair-color"]
who    :: String  = first["name"]

check:
  adult is false
  hair is "brown"
  who is "Bob"
end
