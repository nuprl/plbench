#lang pyret

# Demonstrates every table syntactic sugar form (table:/row:, select, sieve
# (filter), extend, order, extract, transform (update)) type-checking
# against statically-known column shapes, in the style of
# lang/tests/pyret/tests/test-tables.arr (the runtime behavioral spec these
# forms lower to -- see DESIGN.md's "implementation strategy" section for
# how desugaring was moved to run after type-checking so these forms are
# visible to the checker at all).

gradebook :: Table<{name :: String, quiz1 :: Number, quiz2 :: Number}> =
  table: name, quiz1, quiz2
    row: "Bob", 8, 9
    row: "Alice", 6, 8
    row: "Eve", 9, 7
  end

# select / sieve (filter): both preserve/narrow column *types* precisely.
names-only :: Table<{name :: String}> =
  select name from gradebook end

high-quiz1 :: Table<{name :: String, quiz1 :: Number, quiz2 :: Number}> =
  sieve gradebook using quiz1: quiz1 >= 8 end

# extend: using-bound names project the *current row's* column values (by
# the bind's own identifier, matching the column name); the new column's
# type comes from its annotation (if given) or is inferred from the value
# expression.
with-total :: Table<{name :: String, quiz1 :: Number, quiz2 :: Number, total :: Number}> =
  extend gradebook using quiz1, quiz2:
    total :: Number: quiz1 + quiz2
  end

# order: schema-preserving; only the named columns are checked for
# existence.
by-total :: Table<{name :: String, quiz1 :: Number, quiz2 :: Number, total :: Number}> =
  order with-total: total descending end

# extract: the one form that produces a List<T> (of the column's element
# type) instead of a Table.
totals :: List<Number> = extract total from with-total end

# transform (table-update sugar; note the surface keyword is "transform",
# not "update" -- see DESIGN.md): using-bound names are visible in the new
# values, which must match each updated column's existing type.
curved :: Table<{name :: String, quiz1 :: Number, quiz2 :: Number}> =
  transform gradebook using quiz1, quiz2:
    quiz1: quiz1 + 1,
    quiz2: quiz2 + 1
  end

print(names-only)
print(high-quiz1)
print(by-total)
print(totals)
print(curved)
