# Demonstrates function definitions annotated with the new `Table<{...}>` /
# `Row<{...}>` types, and the width-subtyping rule table-check.ts gives them
# (mirroring the pre-existing width subtyping already used for plain record
# types by the general checker's t-record constraint case): a table with
# *more* columns than a function requires is still an acceptable argument,
# and inside the function only the declared columns are assumed to exist.
#
# This is the practical form of "row polymorphism" this project implements
# (see DESIGN.md, "Alternate designs" for the full row-*variable*
# polymorphism this stops short of): each individual function's parameter
# schema is closed/fixed, but callers are not required to match it exactly.

fun average-gpa(t :: Table<{gpa :: Number}>) -> Table<{gpa :: Number}>:
  # Body deliberately does not exercise arithmetic on table cell values --
  # see DESIGN.md ("Bugs found" / getBracket) for why that specific
  # combination cannot yet pass the *general* checker; the point of this
  # example is the width-subtyping call-site check below.
  t
end

fun add-hair-color(t :: Table<{name :: String}>, colors :: List<String>) -> Table<{name :: String, hair-color :: String}>:
  t.add-column("hair-color", colors)
end

students :: Table<{name :: String, age :: Number, gpa :: Number}> =
  table: name, age, gpa
    row: "Alicia", 30, 3.9
    row: "Meihui", 40, 3.4
  end

# `students` has more columns (name, age, gpa) than `average-gpa` requires
# (just gpa) -- an unannotated `Table` couldn't be checked this way, since
# it carries no column information for table-check.ts to compare.
just-gpas = average-gpa(students)

with-colors = add-hair-color(students, [list: "brown", "red"])
