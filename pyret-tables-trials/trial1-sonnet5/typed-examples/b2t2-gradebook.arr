#lang pyret

# Adapted from the B2T2 benchmark (Lu, Greenman, Krishnamurthi): the
# `gradebookMissing` example table (section 4.1) and the `dotProduct`
# example program (section 6, "This function computes the dot product of
# two columns in a table... A type system should ensure that the columns
# are in the table and that the sorts of these columns describe numbers.").
#
# gradebookMissing has two empty cells (Alice's quiz3, Eve's quiz2); B2T2
# leaves the encoding of missing data to implementors (section 3.4). This
# encoding uses Option<Number>, so a column that may be empty is typed
# Table<{... :: Option<Number> ...}> and dotProduct below requires *plain*
# Number columns -- i.e., columns known not to contain blanks -- which the
# type checker verifies statically.

gradebook :: Table<{
    name :: String,
    age :: Number,
    quiz1 :: Number,
    quiz2 :: Number,
    midterm :: Number,
    quiz3 :: Option<Number>,
    quiz4 :: Number,
    final :: Number
  }> =
  table: name, age, quiz1, quiz2, midterm, quiz3, quiz4, final
    row: "Bob", 12, 8, 9, 77, some(7), 9, 87
    row: "Alice", 17, 6, 8, 88, none, 7, 85
    row: "Eve", 13, 9, 84, 8, some(8), 8, 77
  end

# dotProduct: the type system ensures both column names exist in the table
# and that their sorts are Number (the paper's exact requirement); calling
# this with a column that doesn't exist, or one with a non-Number sort
# (like quiz3 above, an Option<Number>), is a compile-time type error.
fun dot-product(t :: Table<{quiz1 :: Number, quiz2 :: Number}>) -> Number:
  xs = t.column("quiz1")
  ys = t.column("quiz2")
  range(0, xs.length()).foldl(lam(i, acc): acc + (xs.get(i) * ys.get(i)) end, 0)
end

# Table<{...}> subtyping is width-based (see DESIGN.md): a table with *more*
# columns than dot-product needs is still an acceptable argument, matching
# ordinary structural/duck-typed usage of the Table api.
result :: Number = dot-product(gradebook)

# addColumn (paper figure 3): appends a column of the given name and
# values, and the checker gives the extended table's type an extra column.
with-passed = gradebook.add-column("passed", [list: true, true, false])
passed-col :: List<Boolean> = with-passed.column("passed")

print(result)
print(passed-col)
