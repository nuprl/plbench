import Lean
import Lean.Util.CollectAxioms

open Lean Meta

private def requireDefinition (env : Environment) (name : Name) : IO ConstantInfo := do
  match env.find? name with
  | some info@(.defnInfo _) => pure info
  | some info@(.opaqueInfo _) => pure info
  | some _ => throw <| IO.userError s!"{name} must be a definition"
  | none => throw <| IO.userError s!"missing declaration {name}"

private def requireDefEqType
    (env : Environment) (name : Name) (actual expected : Expr) : IO Unit := do
  let context : PPContext := { env := env }
  let same ← context.runMetaM <| withTransparency .all <| isDefEq actual expected
  unless same do
    let actualText ← context.runMetaM <| ppExpr actual
    let expectedText ← context.runMetaM <| ppExpr expected
    throw <| IO.userError s!"{name} has the wrong type:\n  actual: {actualText}\n  expected: {expectedText}"

private def requireAllowedAxioms (env : Environment) (name : Name) : IO Unit := do
  let context : PPContext := { env := env }
  let axioms ← context.runCoreM <| collectAxioms name
  let allowed : Array Name := #[`propext, `Classical.choice, `Quot.sound]
  for axiomName in axioms do
    unless allowed.contains axiomName do
      throw <| IO.userError s!"{name} depends on forbidden axiom {axiomName}"

def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Semantics }] {} 0

  let developmentInfo ← requireDefinition env `development
  requireDefEqType env `development developmentInfo.type
    (mkConst `SemanticsTemplate.Development)
  requireAllowedAxioms env `development
  IO.println "checked development : SemanticsTemplate.Development"

  if env.contains `main then
    throw <| IO.userError "Semantics.lean must not define a root main"
  pure 0
