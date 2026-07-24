# Adapted from the B2T2 "students" example table and its selectColumns /
# selectRows discussion (b2t2-paper.txt, "What Is a Table?" and the
# `selectColumns`/`selectRows` API entries). Demonstrates:
#  - a table literal checked against an explicit `Table<{...}>` annotation
#    (the new table-type annotation syntax; see DESIGN.md)
#  - `select`/`extract`/`order` keyword-sugar, which table-check.ts checks
#    the requested column names against the table's known schema for
#  - `.column-names()` and `.length()`, ordinary (unproblematic) methods

students :: Table<{name :: String, age :: Number, gpa :: Number}> =
  table: name, age, gpa
    row: "Alicia", 30, 3.9
    row: "Meihui", 40, 3.4
    row: "Jamal", 25, 3.7
  end

# selectColumns: pick out a subset of columns by (real) name.
names-and-ages = select name, age from students end

# selectRows via `extract`: pull one column out as a plain list.
all-names = extract name from students end

# orderBy, single key.
by-age = order students: age ascending end

num-students = students.length()
col-names = students.column-names()
