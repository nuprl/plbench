import SemanticsTemplate

/-!
A worked small-step semantics-engineering example for a typed, call-by-value MiniML.
The declarative typing and reduction relations are independent of the
executable checker and interpreter below.
-/

namespace MiniML

/-! ## Syntax -/

inductive Ty where
  | int
  | bool
  | fn (argument result : Ty)
deriving Repr, DecidableEq

inductive Expr where
  | int (value : Int)
  | bool (value : Bool)
  | var (name : String)
  | add (left right : Expr)
  | ite (condition yes no : Expr)
  | lam (parameter : String) (parameterType : Ty) (body : Expr)
  | app (function argument : Expr)
  | letE (name : String) (value body : Expr)
deriving Repr, DecidableEq

abbrev Context := String → Option Ty

def Context.empty : Context := fun _ => none

def Context.bind (context : Context) (name : String) (type : Ty) : Context :=
  fun candidate => if candidate == name then some type else context candidate

/-! ## Independent propositional static semantics -/

inductive HasType : Context → Expr → Ty → Prop where
  | int : HasType context (.int value) .int
  | bool : HasType context (.bool value) .bool
  | var : context name = some type → HasType context (.var name) type
  | add : HasType context left .int → HasType context right .int →
      HasType context (.add left right) .int
  | ite : HasType context condition .bool →
      HasType context yes type → HasType context no type →
      HasType context (.ite condition yes no) type
  | lam : HasType (context.bind parameter argument) body result →
      HasType context (.lam parameter argument body) (.fn argument result)
  | app : HasType context function (.fn argument result) →
      HasType context value argument →
      HasType context (.app function value) result
  | letE : HasType context value valueType →
      HasType (context.bind name valueType) body resultType →
      HasType context (.letE name value body) resultType

inductive IsValue : Expr → Prop where
  | int : IsValue (.int value)
  | bool : IsValue (.bool value)
  | lam : IsValue (.lam parameter type body)

/-! ## Substitution-based relational dynamics -/

def substitute (name : String) (replacement : Expr) : Expr → Expr
  | .int value => .int value
  | .bool value => .bool value
  | .var candidate => if candidate == name then replacement else .var candidate
  | .add left right =>
      .add (substitute name replacement left) (substitute name replacement right)
  | .ite condition yes no =>
      .ite (substitute name replacement condition)
        (substitute name replacement yes) (substitute name replacement no)
  | .lam parameter type body =>
      if parameter == name then .lam parameter type body
      else .lam parameter type (substitute name replacement body)
  | .app function argument =>
      .app (substitute name replacement function)
        (substitute name replacement argument)
  | .letE binder value body =>
      .letE binder (substitute name replacement value)
        (if binder == name then body else substitute name replacement body)

inductive Step : Expr → Expr → Prop where
  | addLeft : Step left left' → Step (.add left right) (.add left' right)
  | addRight : IsValue left → Step right right' →
      Step (.add left right) (.add left right')
  | addValues : Step (.add (.int left) (.int right)) (.int (left + right))
  | ifCondition : Step condition condition' →
      Step (.ite condition yes no) (.ite condition' yes no)
  | ifTrue : Step (.ite (.bool true) yes no) yes
  | ifFalse : Step (.ite (.bool false) yes no) no
  | appFunction : Step function function' →
      Step (.app function argument) (.app function' argument)
  | appArgument : IsValue function → Step argument argument' →
      Step (.app function argument) (.app function argument')
  | beta : IsValue argument →
      Step (.app (.lam parameter type body) argument)
        (substitute parameter argument body)
  | letValue : Step value value' →
      Step (.letE name value body) (.letE name value' body)
  | letSubstitute : IsValue value →
      Step (.letE name value body) (substitute name value body)

/-! ## Executable type checker -/

def infer (context : Context) : Expr → Except String Ty
  | .int _ => .ok .int
  | .bool _ => .ok .bool
  | .var name =>
      match context name with
      | some type => .ok type
      | none => .error s!"unbound variable: {name}"
  | .add left right =>
      match infer context left, infer context right with
      | .ok .int, .ok .int => .ok .int
      | .ok _, .ok _ => .error "an operand of + is not Int"
      | .error message, _ | _, .error message => .error message
  | .ite condition yes no =>
      match infer context condition, infer context yes, infer context no with
      | .ok .bool, .ok yesType, .ok noType =>
          if yesType == noType then .ok yesType
          else .error "if branches have different types"
      | .ok _, .ok _, .ok _ => .error "if condition is not Bool"
      | .error message, _, _ | _, .error message, _ | _, _, .error message =>
          .error message
  | .lam parameter parameterType body =>
      match infer (context.bind parameter parameterType) body with
      | .ok bodyType => .ok (.fn parameterType bodyType)
      | .error message => .error message
  | .app function argument =>
      match infer context function, infer context argument with
      | .ok (.fn expected result), .ok actual =>
          if expected == actual then .ok result
          else .error "function argument has the wrong type"
      | .ok _, .ok _ => .error "application operator is not a function"
      | .error message, _ | _, .error message => .error message
  | .letE name value body =>
      match infer context value with
      | .ok valueType => infer (context.bind name valueType) body
      | .error message => .error message

theorem inferSound (result : infer context expression = .ok type) :
    HasType context expression type := by
  induction expression generalizing context type with
  | int => simp [infer] at result; subst type; exact .int
  | bool => simp [infer] at result; subst type; exact .bool
  | var name =>
      simp only [infer] at result
      split at result <;> simp_all
      exact .var (by assumption)
  | add left right leftIH rightIH =>
      simp only [infer] at result
      split at result <;> simp_all
      subst type
      exact .add (leftIH (by assumption)) (rightIH (by assumption))
  | ite condition yes no conditionIH yesIH noIH =>
      simp only [infer] at result
      split at result <;> simp_all
      split at result <;> simp_all
      subst type
      exact .ite (conditionIH (by assumption))
        (yesIH (by assumption)) (noIH (by assumption))
  | lam parameter parameterType body bodyIH =>
      simp only [infer] at result
      split at result <;> simp_all
      subst type
      exact .lam (bodyIH (by assumption))
  | app function argument functionIH argumentIH =>
      cases functionResult : infer context function with
      | error message => simp [infer, functionResult] at result
      | ok functionType =>
          cases argumentResult : infer context argument with
          | error message => simp [infer, functionResult, argumentResult] at result
          | ok argumentType =>
              cases functionType with
              | int => simp [infer, functionResult, argumentResult] at result
              | bool => simp [infer, functionResult, argumentResult] at result
              | fn expected resultType =>
                  by_cases same : expected = argumentType
                  · have resultTypeEq : resultType = type := by
                      simpa [infer, functionResult, argumentResult, same] using result
                    subst argumentType
                    subst type
                    exact .app (functionIH functionResult)
                      (argumentIH argumentResult)
                  · simp [infer, functionResult, argumentResult, same] at result
  | letE name value body valueIH bodyIH =>
      cases valueResult : infer context value with
      | error message => simp [infer, valueResult] at result
      | ok valueType =>
          simp [infer, valueResult] at result
          exact .letE (valueIH valueResult) (bodyIH result)

theorem inferComplete (typed : HasType context expression type) :
    infer context expression = .ok type := by
  induction typed with
  | int | bool => rfl
  | var found => simp [infer, found]
  | add _ _ leftIH rightIH => simp [infer, leftIH, rightIH]
  | ite _ _ _ conditionIH yesIH noIH =>
      simp [infer, conditionIH, yesIH, noIH]
  | lam _ bodyIH => simp [infer, bodyIH]
  | app _ _ functionIH argumentIH =>
      simp [infer, functionIH, argumentIH]
  | letE _ _ valueIH bodyIH => simp [infer, valueIH, bodyIH]

theorem inferCharacterization :
    infer context expression = .ok type ↔ HasType context expression type :=
  ⟨inferSound, inferComplete⟩

/-! ## Type safety of the independent relational semantics -/

private theorem contextBindSame (context : Context) :
    (context.bind name first).bind name second = context.bind name second := by
  funext candidate
  by_cases same : candidate = name <;> simp [Context.bind, same]

private theorem contextBindSwap (context : Context)
    (different : firstName ≠ secondName) :
    (context.bind firstName firstType).bind secondName secondType =
      (context.bind secondName secondType).bind firstName firstType := by
  funext candidate
  simp only [Context.bind]
  by_cases candidate = firstName <;> by_cases candidate = secondName <;>
    simp_all

private theorem typingWeakening
    (typed : HasType source expression type)
    (extension : ∀ name type, source name = some type → target name = some type) :
    HasType target expression type := by
  induction typed generalizing target with
  | int => exact .int
  | bool => exact .bool
  | var found => exact .var (extension _ _ found)
  | add _ _ leftIH rightIH => exact .add (leftIH extension) (rightIH extension)
  | ite _ _ _ conditionIH yesIH noIH =>
      exact .ite (conditionIH extension) (yesIH extension) (noIH extension)
  | lam bodyTyped bodyIH =>
      apply HasType.lam
      apply bodyIH
      intro name type found
      simp only [Context.bind] at found ⊢
      split at found <;> split <;> simp_all
  | app _ _ functionIH argumentIH =>
      exact .app (functionIH extension) (argumentIH extension)
  | letE _ _ valueIH bodyIH =>
      exact .letE (valueIH extension) (bodyIH (by
        intro candidate candidateType found
        simp only [Context.bind] at found ⊢
        split at found <;> split <;> simp_all))

private theorem closedWeakening (typed : HasType Context.empty value type) :
    HasType context value type := by
  apply typingWeakening typed
  simp [Context.empty]

theorem substitutionPreservesTyping
    (bodyTyped : HasType (context.bind name replacementType) body bodyType)
    (replacementTyped : HasType Context.empty replacement replacementType) :
    HasType context (substitute name replacement body) bodyType := by
  induction body generalizing context name replacementType bodyType with
  | int => cases bodyTyped; exact .int
  | bool => cases bodyTyped; exact .bool
  | var candidate =>
      cases bodyTyped with
      | var found =>
          simp only [substitute]
          by_cases same : candidate = name
          · simp [same]
            have typeEquality : bodyType = replacementType := by
              symm
              simpa [Context.bind, same] using found
            cases typeEquality
            exact closedWeakening replacementTyped
          · simp [same]
            exact .var (by simpa [Context.bind, same] using found)
  | add left right leftIH rightIH =>
      cases bodyTyped with
      | add leftTyped rightTyped =>
          exact .add (leftIH leftTyped replacementTyped)
            (rightIH rightTyped replacementTyped)
  | ite condition yes no conditionIH yesIH noIH =>
      cases bodyTyped with
      | ite conditionTyped yesTyped noTyped =>
          exact .ite (conditionIH conditionTyped replacementTyped)
            (yesIH yesTyped replacementTyped) (noIH noTyped replacementTyped)
  | lam parameter argument body bodyIH =>
      cases bodyTyped with
      | lam innerTyped =>
          simp only [substitute]
          by_cases same : parameter = name
          · simp [same]
            apply HasType.lam
            simpa [same, contextBindSame] using innerTyped
          · simp [same]
            apply HasType.lam
            have reordered := innerTyped
            rw [contextBindSwap context (Ne.symm same)] at reordered
            exact bodyIH reordered replacementTyped
  | app function argument functionIH argumentIH =>
      cases bodyTyped with
      | app functionTyped argumentTyped =>
          exact .app (functionIH functionTyped replacementTyped)
            (argumentIH argumentTyped replacementTyped)
  | letE binder value body valueIH bodyIH =>
      cases bodyTyped with
      | letE valueTyped innerTyped =>
          simp only [substitute]
          apply HasType.letE (valueIH valueTyped replacementTyped)
          by_cases same : binder = name
          · simp [same]
            simpa [same, contextBindSame] using innerTyped
          · simp [same]
            have reordered := innerTyped
            rw [contextBindSwap context (Ne.symm same)] at reordered
            exact bodyIH reordered replacementTyped

private theorem canonicalInt
    (typed : HasType Context.empty value .int) (valueForm : IsValue value) :
    ∃ number, value = .int number := by
  cases valueForm <;> cases typed
  case int => exact ⟨_, rfl⟩

private theorem canonicalBool
    (typed : HasType Context.empty value .bool) (valueForm : IsValue value) :
    ∃ boolean, value = .bool boolean := by
  cases valueForm <;> cases typed
  case bool => exact ⟨_, rfl⟩

private theorem canonicalFunction
    (typed : HasType Context.empty value (.fn argument result))
    (valueForm : IsValue value) :
    ∃ name body, value = .lam name argument body := by
  cases valueForm <;> cases typed
  case lam => exact ⟨_, _, rfl⟩

theorem progress (typed : HasType Context.empty expression type) :
    IsValue expression ∨ ∃ next, Step expression next := by
  induction expression generalizing type with
  | int => exact .inl .int
  | bool => exact .inl .bool
  | var name => cases typed with | var found => simp [Context.empty] at found
  | add left right leftIH rightIH =>
      cases typed with
      | add leftTyped rightTyped =>
      rcases leftIH leftTyped with leftValue | ⟨left', leftStep⟩
      · rcases rightIH rightTyped with rightValue | ⟨right', rightStep⟩
        · obtain ⟨left, rfl⟩ := canonicalInt leftTyped leftValue
          obtain ⟨right, rfl⟩ := canonicalInt rightTyped rightValue
          exact .inr ⟨_, .addValues⟩
        · exact .inr ⟨_, .addRight leftValue rightStep⟩
      · exact .inr ⟨_, .addLeft leftStep⟩
  | ite condition yes no conditionIH yesIH noIH =>
      cases typed with
      | ite conditionTyped yesTyped noTyped =>
      rcases conditionIH conditionTyped with conditionValue | ⟨condition', conditionStep⟩
      · obtain ⟨condition, rfl⟩ := canonicalBool conditionTyped conditionValue
        cases condition
        · exact .inr ⟨_, .ifFalse⟩
        · exact .inr ⟨_, .ifTrue⟩
      · exact .inr ⟨_, .ifCondition conditionStep⟩
  | lam => exact .inl .lam
  | app function argument functionIH argumentIH =>
      cases typed with
      | app functionTyped argumentTyped =>
      rcases functionIH functionTyped with functionValue | ⟨function', functionStep⟩
      · rcases argumentIH argumentTyped with argumentValue | ⟨argument', argumentStep⟩
        · obtain ⟨name, body, rfl⟩ :=
            canonicalFunction functionTyped functionValue
          exact .inr ⟨_, .beta argumentValue⟩
        · exact .inr ⟨_, .appArgument functionValue argumentStep⟩
      · exact .inr ⟨_, .appFunction functionStep⟩
  | letE name value body valueIH bodyIH =>
      cases typed with
      | letE valueTyped bodyTyped =>
      rcases valueIH valueTyped with valueForm | ⟨value', valueStep⟩
      · exact .inr ⟨_, .letSubstitute valueForm⟩
      · exact .inr ⟨_, .letValue valueStep⟩

theorem preservation
    (typed : HasType Context.empty expression type)
    (step : Step expression next) :
    HasType Context.empty next type := by
  induction step generalizing type with
  | addLeft _ stepIH =>
      cases typed with | add leftTyped rightTyped =>
        exact .add (stepIH leftTyped) rightTyped
  | addRight _ _ stepIH =>
      cases typed with | add leftTyped rightTyped =>
        exact .add leftTyped (stepIH rightTyped)
  | addValues => cases typed; exact .int
  | ifCondition _ stepIH =>
      cases typed with | ite conditionTyped yesTyped noTyped =>
        exact .ite (stepIH conditionTyped) yesTyped noTyped
  | ifTrue => cases typed; assumption
  | ifFalse => cases typed; assumption
  | appFunction _ stepIH =>
      cases typed with | app functionTyped argumentTyped =>
        exact .app (stepIH functionTyped) argumentTyped
  | appArgument _ _ stepIH =>
      cases typed with | app functionTyped argumentTyped =>
        exact .app functionTyped (stepIH argumentTyped)
  | beta argumentValue =>
      cases typed with
      | app functionTyped argumentTyped =>
          cases functionTyped with
          | lam bodyTyped =>
              exact substitutionPreservesTyping bodyTyped argumentTyped
  | letValue _ stepIH =>
      cases typed with | letE valueTyped bodyTyped =>
        exact .letE (stepIH valueTyped) bodyTyped
  | letSubstitute valueForm =>
      cases typed with | letE valueTyped bodyTyped =>
        exact substitutionPreservesTyping bodyTyped valueTyped

def sourceResult : Expr → Option String
  | .int value => some (toString value)
  | .bool true => some "true"
  | .bool false => some "false"
  | .lam .. => some "<function>"
  | _ => none

def relationalWellFormed (expression : Expr) : Prop :=
  ∃ type, HasType Context.empty expression type

theorem relationalProgress :
    ∀ {expression}, relationalWellFormed expression →
      (∃ result, sourceResult expression = some result) ∨
      ∃ next, Step expression next := by
  intro expression wellFormed
  rcases wellFormed with ⟨type, typed⟩
  rcases progress typed with value | ⟨next, step⟩
  · left
    cases expression with
    | int => exact ⟨_, rfl⟩
    | bool boolean =>
        cases boolean
        · exact ⟨"false", rfl⟩
        · exact ⟨"true", rfl⟩
    | lam => exact ⟨_, rfl⟩
    | var | add | ite | app | letE => cases value
  · exact .inr ⟨next, step⟩

theorem relationalPreservation :
    ∀ {expression next}, relationalWellFormed expression →
      Step expression next → relationalWellFormed next := by
  intro expression next wellFormed step
  rcases wellFormed with ⟨type, typed⟩
  exact ⟨type, preservation typed step⟩

/-! ## Pure fuel-bounded big-step interpreter -/

/-- Evaluate an expression recursively. One fuel unit bounds one level of the
    evaluation tree; no executable one-step transition function is used. --/
private def evaluate : Nat → Expr → Option Expr
  | 0, _ => none
  | _fuel + 1, .int value => some (.int value)
  | _fuel + 1, .bool value => some (.bool value)
  | _fuel + 1, .var _ => none
  | _fuel + 1, .lam parameter type body => some (.lam parameter type body)
  | fuel + 1, .add left right =>
      match evaluate fuel left, evaluate fuel right with
      | some (.int leftValue), some (.int rightValue) =>
          some (.int (leftValue + rightValue))
      | _, _ => none
  | fuel + 1, .ite condition yes no =>
      match evaluate fuel condition with
      | some (.bool true) => evaluate fuel yes
      | some (.bool false) => evaluate fuel no
      | _ => none
  | fuel + 1, .app function argument =>
      match evaluate fuel function, evaluate fuel argument with
      | some (.lam parameter _ body), some argumentValue =>
          evaluate fuel (substitute parameter argumentValue body)
      | _, _ => none
  | fuel + 1, .letE name value body =>
      match evaluate fuel value with
      | some valueResult => evaluate fuel (substitute name valueResult body)
      | none => none

/-- Render the result of the recursive evaluator. --/
def interpret (fuel : Nat) (expression : Expr) : Option String :=
  (evaluate fuel expression).bind sourceResult

/-- A proof-oriented account of the recursive evaluator. It is used only to
    establish correspondence with the independent small-step relation. --/
private inductive Evaluates : Expr → Expr → Prop where
  | int : Evaluates (.int value) (.int value)
  | bool : Evaluates (.bool value) (.bool value)
  | lam : Evaluates (.lam parameter type body) (.lam parameter type body)
  | add : Evaluates left (.int leftValue) →
      Evaluates right (.int rightValue) →
      Evaluates (.add left right) (.int (leftValue + rightValue))
  | ifTrue : Evaluates condition (.bool true) → Evaluates yes result →
      Evaluates (.ite condition yes no) result
  | ifFalse : Evaluates condition (.bool false) → Evaluates no result →
      Evaluates (.ite condition yes no) result
  | app : Evaluates function (.lam parameter type body) →
      Evaluates argument argumentValue →
      Evaluates (substitute parameter argumentValue body) result →
      Evaluates (.app function argument) result
  | letE : Evaluates value valueResult →
      Evaluates (substitute name valueResult body) result →
      Evaluates (.letE name value body) result

private theorem evaluatesValue (evaluation : Evaluates expression result) :
    IsValue result := by
  induction evaluation with
  | int => exact .int
  | bool => exact .bool
  | lam => exact .lam
  | add => exact .int
  | ifTrue _ _ _ branchIH | ifFalse _ _ _ branchIH => exact branchIH
  | app _ _ _ _ _ bodyIH | letE _ _ _ bodyIH => exact bodyIH

private abbrev Steps := SemanticsTemplate.ReflTransGen Step

private theorem stepsAddLeft (steps : Steps left left') :
    Steps (.add left right) (.add left' right) := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.addLeft step) restIH

private theorem stepsAddRight (leftValue : IsValue left)
    (steps : Steps right right') :
    Steps (.add left right) (.add left right') := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.addRight leftValue step) restIH

private theorem stepsIfCondition (steps : Steps condition condition') :
    Steps (.ite condition yes no) (.ite condition' yes no) := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.ifCondition step) restIH

private theorem stepsAppFunction (steps : Steps function function') :
    Steps (.app function argument) (.app function' argument) := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.appFunction step) restIH

private theorem stepsAppArgument (functionValue : IsValue function)
    (steps : Steps argument argument') :
    Steps (.app function argument) (.app function argument') := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.appArgument functionValue step) restIH

private theorem stepsLetValue (steps : Steps value value') :
    Steps (.letE name value body) (.letE name value' body) := by
  induction steps with
  | refl => exact .refl _
  | tail step _ restIH => exact .tail (.letValue step) restIH

private theorem evaluatesSteps (evaluation : Evaluates expression result) :
    Steps expression result := by
  induction evaluation with
  | int | bool | lam => exact .refl _
  | add leftEvaluation rightEvaluation leftIH rightIH =>
      exact (stepsAddLeft leftIH).trans <|
        (stepsAddRight .int rightIH).trans <|
          SemanticsTemplate.ReflTransGen.single .addValues
  | ifTrue conditionEvaluation yesEvaluation conditionIH yesIH =>
      exact (stepsIfCondition conditionIH).trans <|
        (SemanticsTemplate.ReflTransGen.single Step.ifTrue).trans yesIH
  | ifFalse conditionEvaluation noEvaluation conditionIH noIH =>
      exact (stepsIfCondition conditionIH).trans <|
        (SemanticsTemplate.ReflTransGen.single Step.ifFalse).trans noIH
  | app functionEvaluation argumentEvaluation bodyEvaluation
      functionIH argumentIH bodyIH =>
      exact (stepsAppFunction functionIH).trans <|
        (stepsAppArgument .lam argumentIH).trans <|
        (SemanticsTemplate.ReflTransGen.single
          (.beta (evaluatesValue argumentEvaluation))).trans bodyIH
  | letE valueEvaluation bodyEvaluation valueIH bodyIH =>
      exact (stepsLetValue valueIH).trans <|
        (SemanticsTemplate.ReflTransGen.single
          (.letSubstitute (evaluatesValue valueEvaluation))).trans bodyIH

private theorem evaluateSound
    (success : evaluate fuel expression = some result) :
    Evaluates expression result := by
  induction fuel generalizing expression result with
  | zero => simp [evaluate] at success
  | succ fuel fuelIH =>
      cases expression with
      | int value =>
          simp [evaluate] at success
          subst result
          exact .int
      | bool value =>
          simp [evaluate] at success
          subst result
          exact .bool
      | var name => simp [evaluate] at success
      | lam parameter type body =>
          simp [evaluate] at success
          subst result
          exact .lam
      | add left right =>
          cases leftResult : evaluate fuel left with
          | none => simp [evaluate, leftResult] at success
          | some leftValue =>
              cases leftValue with
              | int leftNumber =>
                  cases rightResult : evaluate fuel right with
                  | none => simp [evaluate, leftResult, rightResult] at success
                  | some rightValue =>
                      cases rightValue with
                      | int rightNumber =>
                          simp [evaluate, leftResult, rightResult] at success
                          subst result
                          exact .add (fuelIH leftResult) (fuelIH rightResult)
                      | bool | var | add | ite | lam | app | letE =>
                          simp [evaluate, leftResult, rightResult] at success
              | bool | var | add | ite | lam | app | letE =>
                  simp [evaluate, leftResult] at success
      | ite condition yes no =>
          cases conditionResult : evaluate fuel condition with
          | none => simp [evaluate, conditionResult] at success
          | some conditionValue =>
              cases conditionValue with
              | bool boolean =>
                  cases boolean
                  · exact .ifFalse (fuelIH conditionResult)
                      (fuelIH (by simpa [evaluate, conditionResult] using success))
                  · exact .ifTrue (fuelIH conditionResult)
                      (fuelIH (by simpa [evaluate, conditionResult] using success))
              | int | var | add | ite | lam | app | letE =>
                  simp [evaluate, conditionResult] at success
      | app function argument =>
          cases functionResult : evaluate fuel function with
          | none => simp [evaluate, functionResult] at success
          | some functionValue =>
              cases functionValue with
              | lam parameter type body =>
                  cases argumentResult : evaluate fuel argument with
                  | none =>
                      simp [evaluate, functionResult, argumentResult] at success
                  | some argumentValue =>
                      have bodyResult :
                          evaluate fuel (substitute parameter argumentValue body) =
                            some result := by
                        simpa [evaluate, functionResult, argumentResult] using success
                      exact .app (fuelIH functionResult) (fuelIH argumentResult)
                        (fuelIH bodyResult)
              | int | bool | var | add | ite | app | letE =>
                  simp [evaluate, functionResult] at success
      | letE name value body =>
          cases valueResult : evaluate fuel value with
          | none => simp [evaluate, valueResult] at success
          | some valueResultExpression =>
              have bodyResult :
                  evaluate fuel (substitute name valueResultExpression body) =
                    some result := by
                simpa [evaluate, valueResult] using success
              exact .letE (fuelIH valueResult) (fuelIH bodyResult)

private theorem valueEvaluates (valueForm : IsValue value) :
    Evaluates value value := by
  cases valueForm with
  | int => exact .int
  | bool => exact .bool
  | lam => exact .lam

private theorem stepEvaluates
    (step : Step expression next)
    (evaluation : Evaluates next result) :
    Evaluates expression result := by
  induction step generalizing result with
  | addLeft step stepIH =>
      cases evaluation with
      | add leftEvaluation rightEvaluation =>
          exact .add (stepIH leftEvaluation) rightEvaluation
  | addRight leftValue step stepIH =>
      cases evaluation with
      | add leftEvaluation rightEvaluation =>
          exact .add leftEvaluation (stepIH rightEvaluation)
  | addValues =>
      cases evaluation
      exact .add .int .int
  | ifCondition step stepIH =>
      cases evaluation with
      | ifTrue conditionEvaluation branchEvaluation =>
          exact .ifTrue (stepIH conditionEvaluation) branchEvaluation
      | ifFalse conditionEvaluation branchEvaluation =>
          exact .ifFalse (stepIH conditionEvaluation) branchEvaluation
  | ifTrue => exact .ifTrue .bool evaluation
  | ifFalse => exact .ifFalse .bool evaluation
  | appFunction step stepIH =>
      cases evaluation with
      | app functionEvaluation argumentEvaluation bodyEvaluation =>
          exact .app (stepIH functionEvaluation) argumentEvaluation bodyEvaluation
  | appArgument functionValue step stepIH =>
      cases evaluation with
      | app functionEvaluation argumentEvaluation bodyEvaluation =>
          exact .app functionEvaluation (stepIH argumentEvaluation) bodyEvaluation
  | beta argumentValue =>
      exact .app .lam (valueEvaluates argumentValue) evaluation
  | letValue step stepIH =>
      cases evaluation with
      | letE valueEvaluation bodyEvaluation =>
          exact .letE (stepIH valueEvaluation) bodyEvaluation
  | letSubstitute valueForm =>
      exact .letE (valueEvaluates valueForm) evaluation

private theorem stepsEvaluate
    (steps : Steps expression final)
    (finalValue : IsValue final) :
    Evaluates expression final := by
  induction steps with
  | refl => exact valueEvaluates finalValue
  | tail step rest restIH => exact stepEvaluates step (restIH finalValue)

private theorem evaluatesExecutable (evaluation : Evaluates expression result) :
    ∃ threshold, ∀ fuel, threshold ≤ fuel →
      evaluate fuel expression = some result := by
  induction evaluation with
  | int =>
      exact ⟨1, by
        intro fuel enough
        cases fuel <;> simp_all [evaluate]⟩
  | bool =>
      exact ⟨1, by
        intro fuel enough
        cases fuel <;> simp_all [evaluate]⟩
  | lam =>
      exact ⟨1, by
        intro fuel enough
        cases fuel <;> simp_all [evaluate]⟩
  | add leftEvaluation rightEvaluation leftIH rightIH =>
      rcases leftIH with ⟨leftFuel, leftRuns⟩
      rcases rightIH with ⟨rightFuel, rightRuns⟩
      refine ⟨max leftFuel rightFuel + 1, ?_⟩
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ remaining =>
          have leftEnough : leftFuel ≤ remaining := by omega
          have rightEnough : rightFuel ≤ remaining := by omega
          simp [evaluate, leftRuns remaining leftEnough,
            rightRuns remaining rightEnough]
  | ifTrue conditionEvaluation yesEvaluation conditionIH yesIH =>
      rcases conditionIH with ⟨conditionFuel, conditionRuns⟩
      rcases yesIH with ⟨yesFuel, yesRuns⟩
      refine ⟨max conditionFuel yesFuel + 1, ?_⟩
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ remaining =>
          have conditionEnough : conditionFuel ≤ remaining := by omega
          have yesEnough : yesFuel ≤ remaining := by omega
          simp [evaluate, conditionRuns remaining conditionEnough,
            yesRuns remaining yesEnough]
  | ifFalse conditionEvaluation noEvaluation conditionIH noIH =>
      rcases conditionIH with ⟨conditionFuel, conditionRuns⟩
      rcases noIH with ⟨noFuel, noRuns⟩
      refine ⟨max conditionFuel noFuel + 1, ?_⟩
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ remaining =>
          have conditionEnough : conditionFuel ≤ remaining := by omega
          have noEnough : noFuel ≤ remaining := by omega
          simp [evaluate, conditionRuns remaining conditionEnough,
            noRuns remaining noEnough]
  | app functionEvaluation argumentEvaluation bodyEvaluation
      functionIH argumentIH bodyIH =>
      rcases functionIH with ⟨functionFuel, functionRuns⟩
      rcases argumentIH with ⟨argumentFuel, argumentRuns⟩
      rcases bodyIH with ⟨bodyFuel, bodyRuns⟩
      refine ⟨max functionFuel (max argumentFuel bodyFuel) + 1, ?_⟩
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ remaining =>
          have functionEnough : functionFuel ≤ remaining := by omega
          have argumentEnough : argumentFuel ≤ remaining := by omega
          have bodyEnough : bodyFuel ≤ remaining := by omega
          simp [evaluate, functionRuns remaining functionEnough,
            argumentRuns remaining argumentEnough,
            bodyRuns remaining bodyEnough]
  | letE valueEvaluation bodyEvaluation valueIH bodyIH =>
      rcases valueIH with ⟨valueFuel, valueRuns⟩
      rcases bodyIH with ⟨bodyFuel, bodyRuns⟩
      refine ⟨max valueFuel bodyFuel + 1, ?_⟩
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ remaining =>
          have valueEnough : valueFuel ≤ remaining := by omega
          have bodyEnough : bodyFuel ≤ remaining := by omega
          simp [evaluate, valueRuns remaining valueEnough,
            bodyRuns remaining bodyEnough]

private theorem sourceResultValue
    (observation : sourceResult expression = some result) :
    IsValue expression := by
  cases expression <;> simp [sourceResult] at observation
  · exact .int
  · exact .bool
  · exact .lam

theorem interpretSound
    (_wellFormed : relationalWellFormed expression)
    (success : interpret fuel expression = some result) :
    ∃ final,
      SemanticsTemplate.ReflTransGen Step expression final ∧
      sourceResult final = some result := by
  cases evaluated : evaluate fuel expression with
  | none => simp [interpret, evaluated] at success
  | some final =>
      have evaluation : Evaluates expression final := evaluateSound evaluated
      have observation : sourceResult final = some result := by
        simpa [interpret, evaluated] using success
      exact ⟨final, evaluatesSteps evaluation, observation⟩

theorem interpretComplete
    (_wellFormed : relationalWellFormed expression)
    (steps : SemanticsTemplate.ReflTransGen Step expression final)
    (finalResult : sourceResult final = some result) :
    ∃ fuel, interpret fuel expression = some result := by
  have evaluation : Evaluates expression final :=
    stepsEvaluate steps (sourceResultValue finalResult)
  rcases evaluatesExecutable evaluation with ⟨fuel, runs⟩
  exact ⟨fuel, by simp [interpret, runs fuel (Nat.le_refl fuel), finalResult]⟩

/-! ## Parser and runnable frontend -/

inductive Token where
  | left
  | right
  | colon
  | atom (text : String)
deriving Repr

private def isDelimiter : Char → Bool
  | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ':' => true
  | _ => false

private partial def lexTokens : List Char → List Token → Except String (List Token)
  | [], output => .ok output.reverse
  | ' ' :: rest, output => lexTokens rest output
  | '\t' :: rest, output => lexTokens rest output
  | '\r' :: rest, output => lexTokens rest output
  | '\n' :: rest, output => lexTokens rest output
  | '(' :: rest, output => lexTokens rest (.left :: output)
  | ')' :: rest, output => lexTokens rest (.right :: output)
  | ':' :: rest, output => lexTokens rest (.colon :: output)
  | first :: rest, output =>
      let tail := rest.takeWhile (fun character => !isDelimiter character)
      let remaining := rest.dropWhile (fun character => !isDelimiter character)
      lexTokens remaining (.atom (String.ofList (first :: tail)) :: output)

private def lex (source : String) : Except String (List Token) :=
  lexTokens source.toList []

private partial def parseType : List Token → Except String (Ty × List Token)
  | .atom "Int" :: rest => .ok (.int, rest)
  | .atom "Bool" :: rest => .ok (.bool, rest)
  | .left :: .atom "->" :: rest => do
      let (argument, afterArgument) ← parseType rest
      let (result, afterResult) ← parseType afterArgument
      match afterResult with
      | .right :: remaining => .ok (.fn argument result, remaining)
      | _ => .error "function type is missing ')'"
  | _ => .error "expected a type"

private partial def parseExpression :
    List Token → Except String (Expr × List Token)
  | [] => .error "unexpected end of input"
  | .atom "true" :: rest => .ok (.bool true, rest)
  | .atom "false" :: rest => .ok (.bool false, rest)
  | .atom atom :: rest =>
      match atom.toInt? with
      | some number => .ok (.int number, rest)
      | none => .ok (.var atom, rest)
  | .left :: .atom "+" :: rest => do
      let (left, afterLeft) ← parseExpression rest
      let (right, afterRight) ← parseExpression afterLeft
      match afterRight with
      | .right :: remaining => .ok (.add left right, remaining)
      | _ => .error "+ expression is missing ')'"
  | .left :: .atom "if" :: rest => do
      let (condition, afterCondition) ← parseExpression rest
      let (yes, afterYes) ← parseExpression afterCondition
      let (no, afterNo) ← parseExpression afterYes
      match afterNo with
      | .right :: remaining => .ok (.ite condition yes no, remaining)
      | _ => .error "if expression is missing ')'"
  | .left :: .atom "fun" :: .atom parameter :: .colon :: rest => do
      let (parameterType, afterType) ← parseType rest
      let (body, afterBody) ← parseExpression afterType
      match afterBody with
      | .right :: remaining =>
          .ok (.lam parameter parameterType body, remaining)
      | _ => .error "fun expression is missing ')'"
  | .left :: .atom "let" :: .atom name :: rest => do
      let (value, afterValue) ← parseExpression rest
      let (body, afterBody) ← parseExpression afterValue
      match afterBody with
      | .right :: remaining => .ok (.letE name value body, remaining)
      | _ => .error "let expression is missing ')'"
  | .left :: rest => do
      let (function, afterFunction) ← parseExpression rest
      let (argument, afterArgument) ← parseExpression afterFunction
      match afterArgument with
      | .right :: remaining => .ok (.app function argument, remaining)
      | _ => .error "application is missing ')'"
  | .right :: _ => .error "unexpected ')'"
  | .colon :: _ => .error "unexpected ':'"

def parseSyntax (source : String) : Except String Expr := do
  let tokens ← lex source
  let (expression, remaining) ← parseExpression tokens
  if remaining.isEmpty then pure expression
  else throw "extra input after expression"

/-- Parse and statically validate a source program. --/
def parse (source : String) : Except String Expr :=
  match parseSyntax source with
  | .error message => .error message
  | .ok expression =>
      match infer Context.empty expression with
      | .error message => .error message
      | .ok _ => .ok expression

theorem parseWellFormed (success : parse source = .ok expression) :
    relationalWellFormed expression := by
  unfold parse at success
  cases parsed : parseSyntax source with
  | error message => simp [parsed] at success
  | ok parsedExpression =>
      cases checked : infer Context.empty parsedExpression with
      | error message => simp [parsed, checked] at success
      | ok type =>
          simp [parsed, checked] at success
          subst expression
          exact ⟨type, inferSound checked⟩

/-- The complete worked instance of the shared semantics template. --/
def development : SemanticsTemplate.Development where
  Program := Expr
  State := Expr
  parse := parse
  initial := id
  WellFormed := relationalWellFormed
  Step := Step
  observe := sourceResult
  interpret := interpret
  initialWellFormed := by
    intro source program parsed
    exact parseWellFormed parsed
  progress := relationalProgress
  preservation := relationalPreservation
  interpreterSoundness := by
    intro fuel state result wellFormed success
    exact interpretSound wellFormed success
  interpreterCompleteness := by
    intro state finalState result wellFormed steps observation
    exact interpretComplete wellFormed steps observation

def renderType : Ty → String
  | .int => "Int"
  | .bool => "Bool"
  | .fn argument result => s!"(-> {renderType argument} {renderType result})"


def checkSource (source : String) : Except String Ty := do
  infer Context.empty (← parse source)

def evaluateSource (fuel : Nat) (source : String) : Except String String := do
  let expression ← parse source
  let _ ← infer Context.empty expression
  match interpret fuel expression with
  | some result => pure result
  | none => throw "fuel exhausted"

def cliMain (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["--check", path] =>
      let source ← IO.FS.readFile path
      match checkSource source with
      | .ok type => IO.println (renderType type); pure 0
      | .error message => IO.eprintln message; pure 1
  | [path] | [path, ""] =>
      let source ← IO.FS.readFile path
      match evaluateSource 1000 source with
      | .ok result => IO.println result; pure 0
      | .error message => IO.eprintln message; pure 1
  | [path, fuelText] =>
      match fuelText.toNat? with
      | none => IO.eprintln "fuel must be a natural number"; pure 2
      | some fuel =>
          let source ← IO.FS.readFile path
          match evaluateSource fuel source with
          | .ok result => IO.println result; pure 0
          | .error message => IO.eprintln message; pure 1
  | _ =>
      IO.eprintln "usage: MiniML [--check] PROGRAM [FUEL]"
      pure 2

end MiniML

def main (arguments : List String) : IO UInt32 := MiniML.cliMain arguments
