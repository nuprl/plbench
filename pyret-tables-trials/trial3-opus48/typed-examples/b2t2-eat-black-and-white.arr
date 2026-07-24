#lang pyret

# B2T2 error entry: "blackAndWhite" (Figure 6).
#
# Context: the jellyAnon dataset (all boolean columns).  The task is to build a
# column that is true when a participant ate BOTH black and white jelly beans.
#
# The BUGGY program wrote `r["black and white"]` -- a single, non-existent
# column -- instead of `r["black"] and r["white"]`.  With schema-carrying rows,
# `r["black and white"]` is a *type error* (no such column), caught statically.
# This file is the CORRECTED program, which type-checks.

jelly-anon = table: black, white, red, green
  row: true,  false, true,  false
  row: false, true,  true,  true
  row: true,  true,  false, false
end

eat-black-and-white =
  jelly-anon.build-column(
    "eat-black-and-white",
    lam(r): r["black"] and r["white"] end)

# The new boolean column is now part of the schema:
result :: Boolean = eat-black-and-white.row-n(2)["eat-black-and-white"]

check:
  result is true
  eat-black-and-white.row-n(0)["eat-black-and-white"] is false
end
