#lang pyret

# Adapted from the B2T2 benchmark's `pHackingHomogeneous` example program
# (section 6, figure 4): given a table of boolean jellybean-color columns
# and a boolean "got acne" column, test each color column for a correlation
# with acne.
#
#   fun pHacking(t):
#     colAcne = getColumn(t, "got acne")
#     jellyAnon = dropColumns(t, ["got acne"])
#     for c in header(jellyAnon):
#       colJB = getColumn(t, c)
#       p = fisherTest(colAcne, colJB)
#       ...
#     end
#   end
#
# The `for c in header(jellyAnon)` loop is the crux of this example, and
# exactly the shape of table program this checker cannot give column-level
# types to (see DESIGN.md's "left untypable" section): `c` is a column name
# computed *at runtime* by iterating the table's actual header, so which
# column `getColumn(t, c)` reads is not knowable until the program runs --
# doing so would need dependent types (a column-name-indexed family of
# types), which is well beyond ordinary structural/nominal type systems
# (this is precisely the feature B2T2 section 3.3 flags as the hard part of
# typing tables: "column names are first-class and manufacturable").
#
# What *is* typeable is the fixed-columns case: a jellybean table whose
# color columns are known statically, tested one at a time. This is a
# faithful (if less general) rendering of the same statistical idea.

fun fisher-test(acne :: List<Boolean>, color :: List<Boolean>) -> Number:
  agree = range(0, acne.length()).foldl(
      lam(i, acc):
        if acne.get(i) == color.get(i): acc + 1 else: acc end
      end,
      0)
  agree / acne.length()
end

jellybeans :: Table<{got-acne :: Boolean, brown :: Boolean, red :: Boolean}> =
  table: got-acne, brown, red
    row: true, true, false
    row: false, true, false
    row: true, false, true
  end

fun p-hacking(t :: Table<{got-acne :: Boolean, brown :: Boolean, red :: Boolean}>) -> Nothing block:
  acne = t.column("got-acne")
  brown-p = fisher-test(acne, t.column("brown"))
  red-p = fisher-test(acne, t.column("red"))
  when brown-p > 0.5:
    print("We found a link between brown jelly beans and acne.\n")
  end
  when red-p > 0.5:
    print("We found a link between red jelly beans and acne.\n")
  end
end

p-hacking(jellybeans)
