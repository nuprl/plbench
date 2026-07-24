#lang pyret

# Adapted from the B2T2 benchmark's `employees`/`departments` example tables
# (section 4, "designed for use in join operations") and the `selectRows`/
# `selectColumns`/`stack` entries of the Table api (section 5). B2T2 leaves
# join itself out of its api (section 5.1: "omits a handy subTable operation
# because that behavior can be expressed as a composition of two included
# operations"); this focuses on the parts of the example this checker can
# express precisely: selecting columns, and stacking two same-shaped tables.

employees :: Table<{name :: String, department :: String, salary :: Number}> =
  table: name, department, salary
    row: "Ren", "eng", 120000
    row: "Kai", "sales", 95000
  end

new-hires :: Table<{name :: String, department :: String, salary :: Number}> =
  table: name, department, salary
    row: "Sam", "eng", 110000
  end

# stack: combining two tables with the department :: String, salary ::
# Number, name :: String columns (a real `stack` also requires the same
# column *set*, order-independent; this checker leaves that exact-match
# check untyped and relies on stack's existing runtime check -- see
# DESIGN.md -- but the *result* schema is still the receiver's own).
all-employees :: Table<{name :: String, department :: String, salary :: Number}> =
  employees.stack(new-hires)

# selectColumns (via the `select` sugar): projecting to just the columns
# named, verified against the table's schema, with a corresponding
# narrower Table<...> result.
names-and-departments :: Table<{name :: String, department :: String}> =
  select name, department from all-employees end

fun total-payroll(t :: Table<{salary :: Number}>) -> Number:
  t.column("salary").foldl(lam(s, acc): acc + s end, 0)
end

# Table<{...}> subtyping is width-based: all-employees has more columns
# than total-payroll needs, so passing it is allowed.
print(total-payroll(all-employees))
print(names-and-departments.column-names())
