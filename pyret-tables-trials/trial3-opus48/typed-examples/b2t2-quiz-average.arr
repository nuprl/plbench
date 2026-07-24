#lang pyret

# B2T2 example programs: quizScoreFilter / quizScoreSelect.
#
# "Compute the average quiz score for each student in a gradebook.  The
#  gradebook contains a mix of numeric and non-numeric fields."
#
# This is the `gradebookMissing`-style table (Figure 2), minus the empty cells.
# The schema is genuinely heterogeneous: String `name`, Number grades.  We build
# a `quiz-average` column whose row function reads the four quiz columns.  Every
# `r["quizN"]` access is checked against the schema and known to be a Number, so
# the arithmetic type-checks and the appended column has type Number.

gradebook = table: name, quiz1, quiz2, quiz3, quiz4, midterm, final
  row: "Bob",   8, 9, 7, 9, 77, 87
  row: "Alice", 6, 8, 8, 7, 88, 85
  row: "Eve",   9, 7, 8, 8, 84, 77
end

with-average =
  gradebook.build-column(
    "quiz-average",
    lam(r):
      (r["quiz1"] + r["quiz2"] + r["quiz3"] + r["quiz4"]) / 4
    end)

# `quiz-average` is now a Number column, and `name` is still a String column.
bob = with-average.row-n(0)
bob-avg  :: Number = bob["quiz-average"]
bob-name :: String = bob["name"]

# Extracting the whole column is typed List<Number>.
averages :: List<Number> = with-average.get-column("quiz-average")

check:
  bob-avg is (8 + 9 + 7 + 9) / 4
  bob-name is "Bob"
  averages.length() is 3
end
