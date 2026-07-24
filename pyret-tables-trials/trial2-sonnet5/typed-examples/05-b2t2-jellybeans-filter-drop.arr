# Loosely adapted from the B2T2 "p-hacking" example (b2t2-paper.txt, Figure
# 4/6, `jellyAnon`/`pHacking`/`eatBlackAndWhite`) and its emphasis on
# column-name-indexed Row access (`r["black"]`) and `dropColumns`/`header`
# enumeration. Demonstrates:
#  - Row<{...}> as a first-class parameter type for a row-processing
#    callback, with literal-string bracket access checked against it
#  - .filter (whole-row predicate) and .drop (remove a column)
#  - .column-names() enumerating a table's columns (paper's `header`)
#
# As in 04, the predicate below is equality-based rather than arithmetic on
# a cell value -- see DESIGN.md ("Bugs found") for why arithmetic/comparison
# on a getBracket-derived value cannot currently pass the *general* checker
# even though table-check.ts itself infers it precisely.

jelly-beans :: Table<{participant :: String, black :: Boolean, white :: Boolean}> =
  table: participant, black, white
    row: "P1", true, true
    row: "P2", true, false
    row: "P3", false, true
  end

eat-black-and-white = lam(r :: Row<{black :: Boolean, white :: Boolean}>):
  (r["black"] == true) and (r["white"] == true)
end

ate-both = jelly-beans.filter(eat-black-and-white)

# dropColumns: project away a column by name (b2t2's dropColumns, restricted
# to a single column here since that's what .drop provides).
anonymized = jelly-beans.drop("participant")

# header: enumerate the remaining columns.
remaining-columns = anonymized.column-names()
