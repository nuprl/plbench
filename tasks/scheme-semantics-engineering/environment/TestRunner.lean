import Semantics

namespace TestRunner

/-- The verifier's fixed interpreter fuel allowance. --/
private def fuel : Nat := 500000

/-- Emit one byte-length-framed string field. --/
private def emitField (label value : String) : IO Unit := do
  IO.println s!"{label} {value.toUTF8.size}"
  IO.print value

/-- Emit one test-case outcome in the verifier's stable text protocol. --/
private def emitOutcome (index : Nat) (status output : String) : IO Unit := do
  IO.println s!"CASE {index}"
  IO.println s!"STATUS {status}"
  emitField "OUTPUT" output

/-- Run one source file through the submitted development. --/
private def runOne (index : Nat) (programFile : System.FilePath) : IO Unit := do
  let source ← IO.FS.readFile programFile
  match development.parse source with
  | .error _ =>
      emitOutcome index "REJECT" ""
  | .ok program =>
      match development.interpret fuel (development.initial program) with
      | none => emitOutcome index "FUEL" ""
      | some output => emitOutcome index "TERMINATED" output

/-- Return the `.scm` files in a case directory in lexical order. --/
private def sourceFiles (caseDirectory : System.FilePath) : IO (List System.FilePath) := do
  let entries ← caseDirectory.readDir
  pure <| (entries.toList.filterMap fun entry =>
    if entry.path.extension == some "scm" then some entry.path else none).mergeSort
      (fun left right => left.toString < right.toString)

/-- Run all Scheme cases in a directory with a fixed fuel allowance. --/
private def runDirectory (caseDirectory : System.FilePath) : IO UInt32 := do
  let programs ← sourceFiles caseDirectory
  if programs.isEmpty then
    IO.eprintln s!"no .scm test cases in {caseDirectory}"
    pure 2
  else
    for (program, index) in programs.zipIdx do
      runOne index program
    pure 0

end TestRunner

/-- Run the trusted test runner on `CASE_DIRECTORY`. --/
def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | [caseDirectory] =>
      TestRunner.runDirectory caseDirectory
  | _ =>
      IO.eprintln "usage: TestRunner CASE_DIRECTORY"
      pure 2
