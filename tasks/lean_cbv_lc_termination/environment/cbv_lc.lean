/-!
Trusted nominal syntax and call-by-value semantics.
-/

abbrev Name := String

inductive Typ where
  | base : Typ
  | arr : Typ → Typ → Typ

infixr:60 " ⇒ " => Typ.arr

inductive Trm where
  | var : Name → Trm
  | unit : Trm
  | lam : Name → Typ → Trm → Trm
  | app : Trm → Trm → Trm

namespace Trm

/-- An upper bound on the length of every name appearing in a term. -/
def maxNameLength : Trm → Nat
  | .var name => name.length
  | .unit => 0
  | .lam parameter _ body => max parameter.length body.maxNameLength
  | .app fn arg => max fn.maxNameLength arg.maxNameLength

abbrev Substitution := List (Name × Trm)

/-- An upper bound on the length of names in all replacement terms. -/
def substitutionMaxNameLength (substitution : Substitution) : Nat :=
  (substitution.map (fun (_, replacement) => replacement.maxNameLength)).max?.getD 0

/-- A name absent from a body and every replacement in a substitution. -/
def freshFor (body : Trm) (substitution : Substitution) : Name :=
  String.ofList
    (List.replicate
      (max body.maxNameLength (substitutionMaxNameLength substitution) + 1) '_')

/-- Simultaneous capture-avoiding substitution on nominal terms. -/
def substAll (substitution : Substitution) : Trm → Trm
  | .var name =>
      (substitution.lookup name).getD (.var name)
  | .unit => .unit
  | .lam parameter type body =>
      let freshName := freshFor body substitution
      .lam freshName type
        (substAll ((parameter, .var freshName) :: substitution) body)
  | .app fn arg =>
      .app (substAll substitution fn) (substAll substitution arg)

/-- Capture-avoiding substitution of a term for a named variable. -/
def subst (term : Trm) (name : Name) (replacement : Trm) : Trm :=
  substAll [(name, replacement)] term

end Trm

abbrev Ctx := List (Name × Typ)

inductive typing : Ctx → Trm → Typ → Prop where
  | var : Γ.lookup name = some type → typing Γ (.var name) type
  | unit : typing Γ .unit .base
  | lam : typing ((parameter, argumentType) :: Γ) body resultType →
      typing Γ (.lam parameter argumentType body) (argumentType ⇒ resultType)
  | app : typing Γ fn (argumentType ⇒ resultType) →
      typing Γ argument argumentType →
      typing Γ (.app fn argument) resultType

inductive Value : Trm → Prop where
  | unit : Value .unit
  | lam : Value (.lam parameter type body)

inductive Step : Trm → Trm → Prop where
  | beta : Value argument →
      Step (.app (.lam parameter type body) argument)
        (body.subst parameter argument)
  | appLeft : Step fn fn' → Step (.app fn argument) (.app fn' argument)
  | appRight : Value fn → Step argument argument' →
      Step (.app fn argument) (.app fn argument')

inductive Steps : Trm → Trm → Prop where
  | refl : Steps term term
  | tail : Steps first middle → Step middle last → Steps first last

def Terminates (term : Trm) : Prop :=
  ∃ value, Steps term value ∧ Value value

def Termination : Prop :=
  ∀ {term type}, typing [] term type → Terminates term
