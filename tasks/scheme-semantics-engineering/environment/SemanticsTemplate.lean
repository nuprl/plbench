import Std

/-!
# A template for semantics engineering

This module is the complete interface for a semantics development that will be
compiled and exercised on held-out source programs. A development supplies:

* a parser from source text to abstract syntax;
* independent declarative well-formedness and small-step semantics;
* a pure fuel-bounded interpreter; and
* proofs connecting the executable definitions to the declarative relations.

Source text, parse errors, and observable execution results are strings so that
a verifier can supply programs and compare their behavior directly. The entire
required artifact is represented by one value of `Development`.
-/

namespace SemanticsTemplate

/-- Zero or more uses of a binary relation. -/
inductive ReflTransGen (relation : α → α → Prop) : α → α → Prop where
  | refl (value : α) : ReflTransGen relation value value
  | tail : relation first next → ReflTransGen relation next last →
      ReflTransGen relation first last

namespace ReflTransGen

/-- Embed one relation step into its reflexive-transitive closure. -/
theorem single (step : relation first last) :
    ReflTransGen relation first last :=
  .tail step (.refl last)

/-- Reflexive-transitive closure is transitive. -/
theorem trans :
    ReflTransGen relation first middle →
    ReflTransGen relation middle last →
    ReflTransGen relation first last
  | .refl _, suffix => suffix
  | .tail step rest, suffix => .tail step (trans rest suffix)

end ReflTransGen


/--
A complete semantics development. The verifier imports a submitted value of
this type, parses held-out source strings, and executes `interpret` on them.
-/
structure Development where
  /-- The type for abstract syntax, as returned by the parser. --/
  Program : Type
  /-- Abstract machine state, i.e., the program, environment, store, whatever. --/
  State : Type

  parse : String → Except String Program
  initial : Program → State

  /-- Declarative static semantics, i.e., typing, well-formedness, etc. --/
  WellFormed : State → Prop


  /-- A single step of a small-step operational semantics. --/
  Step : State → State → Prop

  /-- Observe serves as a predicate to determine if the state is final. If
      it is not, it must return None. If it is final, it must return the output
      that the program produces. We only model standard output and ignore
      standard error and other output channels. --/
  observe : State → Option String

  /-- A fuel-bounded interpreter that returns the output (given enough fuel). --/
  interpret : Nat → State → Option String

  -- Several theorems that must be proven.

  /-- Successfully parsed programs have well-formed initial states. --/
  initialWellFormed :
    ∀ {source program}, parse source = .ok program →
      WellFormed (initial program)

  progress :
    ∀ {state}, WellFormed state →
      (∃ result, observe state = some result) ∨
      ∃ next, Step state next

  preservation :
    ∀ {state next}, WellFormed state →
      Step state next →
      WellFormed next

  /-- If the interpreter returns a result, then there is a sequence of steps that
      leads to a final state that produces the result. --/
  interpreterSoundness :
    ∀ {fuel state result},
      WellFormed state →
      interpret fuel state = some result →
      ∃ finalState,
        ReflTransGen Step state finalState ∧
        observe finalState = some result

  /-- If there is a sequence of steps that produces a result, then there is
      some amount of fuel that will drive the interpreter to produce the result.
    -/
  interpreterCompleteness :
    ∀ {state finalState result},
      WellFormed state →
      ReflTransGen Step state finalState →
      observe finalState = some result →
      ∃ fuel, interpret fuel state = some result


end SemanticsTemplate
