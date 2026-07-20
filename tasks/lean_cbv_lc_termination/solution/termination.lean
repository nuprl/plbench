import cbv_lc

namespace DB

inductive Trm where
  | var : Nat → Trm
  | unit : Trm
  | lam : Typ → Trm → Trm
  | app : Trm → Trm → Trm

namespace Trm

def upRen (ρ : Nat → Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => ρ n + 1

def rename (ρ : Nat → Nat) : Trm → Trm
  | .var n => .var (ρ n)
  | .unit => .unit
  | .lam A body => .lam A (body.rename (upRen ρ))
  | .app fn arg => .app (fn.rename ρ) (arg.rename ρ)

def upSub (σ : Nat → Trm) : Nat → Trm
  | 0 => .var 0
  | n + 1 => (σ n).rename Nat.succ

def subst (σ : Nat → Trm) : Trm → Trm
  | .var n => σ n
  | .unit => .unit
  | .lam A body => .lam A (body.subst (upSub σ))
  | .app fn arg => .app (fn.subst σ) (arg.subst σ)

def subst0 (body argument : Trm) : Trm :=
  body.subst fun
    | 0 => argument
    | n + 1 => .var n

theorem rename_id (term : Trm) : term.rename id = term := by
  induction term with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [rename]
      have upId : upRen id = id := by
        funext n
        cases n <;> rfl
      rw [upId, ih]
  | app fn arg fnIH argIH => simp [rename, fnIH, argIH]

theorem rename_comp (term : Trm) (ρ₁ ρ₂ : Nat → Nat) :
    (term.rename ρ₁).rename ρ₂ = term.rename (fun n => ρ₂ (ρ₁ n)) := by
  induction term generalizing ρ₁ ρ₂ with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [rename]
      rw [ih]
      congr 2
      funext n
      cases n <;> rfl
  | app fn arg fnIH argIH => simp [rename, fnIH, argIH]

theorem subst_rename (term : Trm) (ρ : Nat → Nat) (σ : Nat → Trm) :
    (term.rename ρ).subst σ = term.subst (fun n => σ (ρ n)) := by
  induction term generalizing ρ σ with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [rename, subst]
      rw [ih]
      congr 2
      funext n
      cases n <;> rfl
  | app fn arg fnIH argIH => simp [rename, subst, fnIH, argIH]

theorem rename_subst (term : Trm) (σ : Nat → Trm) (ρ : Nat → Nat) :
    (term.subst σ).rename ρ = term.subst (fun n => (σ n).rename ρ) := by
  induction term generalizing σ ρ with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [subst, rename]
      rw [ih]
      congr 2
      funext n
      cases n with
      | zero => rfl
      | succ n =>
          simp only [upSub]
          rw [rename_comp, rename_comp]
          apply congrArg (fun f => (σ n).rename f)
          funext k
          cases k <;> rfl
  | app fn arg fnIH argIH => simp [subst, rename, fnIH, argIH]

theorem subst_comp (term : Trm) (σ τ : Nat → Trm) :
    (term.subst σ).subst τ = term.subst (fun n => (σ n).subst τ) := by
  induction term generalizing σ τ with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [subst]
      rw [ih]
      congr 2
      funext n
      cases n with
      | zero => rfl
      | succ n =>
          simp only [upSub]
          rw [subst_rename, rename_subst]
          congr 1
  | app fn arg fnIH argIH => simp [subst, fnIH, argIH]

theorem subst_vars (term : Trm) : term.subst (fun n => .var n) = term := by
  induction term with
  | var n => rfl
  | unit => rfl
  | lam A body ih =>
      simp only [subst]
      have upVars : upSub (fun n => .var n) = (fun n => .var n) := by
        funext n
        cases n <;> rfl
      rw [upVars, ih]
  | app fn arg fnIH argIH => simp [subst, fnIH, argIH]

theorem rename_succ_subst_drop (term replacement : Trm) :
    (term.rename Nat.succ).subst (fun
      | 0 => replacement
      | n + 1 => .var n) = term := by
  rw [subst_rename]
  have same :
      (fun n : Nat => (fun
        | 0 => replacement
        | k + 1 => Trm.var k) (Nat.succ n)) =
      (fun n => Trm.var n) := by
    funext n
    rfl
  rw [same, subst_vars]

theorem subst_lift_subst0 (body argument : Trm) (σ : Nat → Trm) :
    (body.subst (upSub σ)).subst0 argument =
      body.subst (fun
        | 0 => argument
        | n + 1 => σ n) := by
  simp only [subst0]
  rw [subst_comp]
  congr 1
  funext n
  cases n with
  | zero => rfl
  | succ n =>
      simp only [upSub]
      exact rename_succ_subst_drop (σ n) argument

theorem subst0_then_subst (body argument : Trm) (σ : Nat → Trm) :
    (body.subst0 argument).subst σ =
      body.subst (fun
        | 0 => argument.subst σ
        | n + 1 => σ n) := by
  simp only [subst0]
  rw [subst_comp]
  congr 1
  funext n
  cases n <;> rfl

theorem beta_fusion (body argument : Trm) (σ : Nat → Trm) :
    (body.subst (upSub σ)).subst0 (argument.subst σ) =
      (body.subst0 argument).subst σ := by
  rw [subst_lift_subst0, subst0_then_subst]

end Trm

abbrev Ctx := List Typ

inductive typing : Ctx → Trm → Typ → Prop where
  | var : Γ[n]? = some A → typing Γ (.var n) A
  | unit : typing Γ .unit .base
  | lam : typing (A :: Γ) body B → typing Γ (.lam A body) (A ⇒ B)
  | app : typing Γ fn (A ⇒ B) → typing Γ arg A → typing Γ (.app fn arg) B

inductive Value : Trm → Prop where
  | unit : Value .unit
  | lam : Value (.lam A body)

inductive Step : Trm → Trm → Prop where
  | beta : Value argument →
      Step (.app (.lam A body) argument) (body.subst0 argument)
  | appLeft : Step fn fn' → Step (.app fn arg) (.app fn' arg)
  | appRight : Value fn → Step arg arg' →
      Step (.app fn arg) (.app fn arg')

inductive Steps : Trm → Trm → Prop where
  | refl : Steps term term
  | tail : Steps first middle → Step middle last → Steps first last

def Terminates (term : Trm) : Prop :=
  ∃ value, Steps term value ∧ Value value

theorem value_subst (value : Value term) (σ : Nat → Trm) :
    Value (term.subst σ) := by
  cases value with
  | unit => exact .unit
  | lam => exact .lam

theorem step_subst (reduction : Step term term') (σ : Nat → Trm) :
    Step (term.subst σ) (term'.subst σ) := by
  induction reduction generalizing σ with
  | beta value =>
      simp only [Trm.subst]
      rw [← Trm.beta_fusion]
      exact .beta (value_subst value σ)
  | appLeft step ih => exact .appLeft (ih σ)
  | appRight value step ih =>
      exact .appRight (value_subst value σ) (ih σ)

theorem steps_trans (first : Steps a b) (second : Steps b c) : Steps a c := by
  induction second with
  | refl => exact first
  | tail _ => exact .tail (by assumption) (by assumption)

theorem steps_app_left (reductions : Steps fn fn') :
    Steps (.app fn arg) (.app fn' arg) := by
  induction reductions with
  | refl => exact .refl
  | tail _ => exact .tail (by assumption) (.appLeft (by assumption))

theorem steps_app_right (functionValue : Value fn) (reductions : Steps arg arg') :
    Steps (.app fn arg) (.app fn arg') := by
  induction reductions with
  | refl => exact .refl
  | tail _ =>
      exact .tail (by assumption) (.appRight functionValue (by assumption))

def Red : Typ → Trm → Prop
  | .base, term => Terminates term
  | .arr A B, term =>
      ∃ value, Steps term value ∧ Value value ∧
        ∀ argument, Red A argument → Red B (.app value argument)

theorem red_witness (red : Red A term) :
    ∃ value, Steps term value ∧ Value value ∧ Red A value := by
  cases A with
  | base =>
      rcases red with ⟨value, reductions, isValue⟩
      exact ⟨value, reductions, isValue, value, .refl, isValue⟩
  | arr A B =>
      rcases red with ⟨value, reductions, isValue, maps⟩
      exact ⟨value, reductions, isValue, value, .refl, isValue, maps⟩

theorem red_backward (reductions : Steps term term') (red : Red A term') :
    Red A term := by
  cases A with
  | base =>
      rcases red with ⟨value, suffix, isValue⟩
      exact ⟨value, steps_trans reductions suffix, isValue⟩
  | arr A B =>
      rcases red with ⟨value, suffix, isValue, maps⟩
      exact ⟨value, steps_trans reductions suffix, isValue, maps⟩

def RedSub (Γ : Ctx) (σ : Nat → Trm) : Prop :=
  ∀ {n A}, Γ[n]? = some A → Red A (σ n)

theorem redSub_cons (redArgument : Red A argument) (redσ : RedSub Γ σ) :
    RedSub (A :: Γ) (fun
      | 0 => argument
      | n + 1 => σ n) := by
  intro n T lookup
  cases n with
  | zero =>
      simp only [List.getElem?_cons_zero] at lookup
      cases lookup
      exact redArgument
  | succ n =>
      simp only [List.getElem?_cons_succ] at lookup
      exact redσ lookup

theorem fundamental (derivation : typing Γ term A) (redσ : RedSub Γ σ) :
    Red A (term.subst σ) := by
  induction derivation generalizing σ with
  | var lookup => exact redσ lookup
  | unit => exact ⟨.unit, .refl, .unit⟩
  | app functionTyping argumentTyping functionIH argumentIH =>
      have redFunction := functionIH redσ
      rcases redFunction with ⟨value, reductions, isValue, maps⟩
      apply red_backward (steps_app_left reductions)
      exact maps _ (argumentIH redσ)
  | lam bodyTyping bodyIH =>
      rename_i argumentType context rawBody resultType
      simp only [Trm.subst]
      let substitutedBody := rawBody.subst (Trm.upSub σ)
      refine ⟨.lam argumentType substitutedBody, .refl, .lam, ?_⟩
      intro argument redArgument
      rcases red_witness redArgument with
        ⟨value, argumentSteps, isValue, redValue⟩
      have redExtended : RedSub (argumentType :: context) (fun
          | 0 => value
          | n + 1 => σ n) := redSub_cons redValue redσ
      have redBody := bodyIH redExtended
      have redContractum : Red resultType (substitutedBody.subst0 value) := by
        dsimp [substitutedBody]
        rw [Trm.subst_lift_subst0]
        exact redBody
      have evaluateArgument :
          Steps (.app (.lam argumentType substitutedBody) argument)
            (.app (.lam argumentType substitutedBody) value) :=
        steps_app_right .lam argumentSteps
      have evaluateApplication :
          Steps (.app (.lam argumentType substitutedBody) argument)
            (substitutedBody.subst0 value) :=
        .tail evaluateArgument (.beta isValue)
      exact red_backward evaluateApplication redContractum

theorem empty_redSub (σ : Nat → Trm) : RedSub [] σ := by
  intro n A lookup
  cases n <;> simp at lookup

theorem termination (derivation : typing [] term type) : Terminates term := by
  have red : Red type (term.subst (fun n => .var n)) :=
    fundamental derivation (empty_redSub _)
  rw [Trm.subst_vars] at red
  rcases red_witness red with ⟨value, reductions, isValue, _⟩
  exact ⟨value, reductions, isValue⟩

end DB

namespace Nominal

def contextNames : Ctx → List Name
  | [] => []
  | (name, _) :: rest => name :: contextNames rest

def contextTypes : Ctx → List Typ
  | [] => []
  | (_, type) :: rest => type :: contextTypes rest

def indexOf (name : Name) : List Name → Option Nat
  | [] => none
  | candidate :: rest =>
      if name = candidate then some 0 else (indexOf name rest).map (· + 1)

def erase (names : List Name) : Trm → Option DB.Trm
  | .var name => (indexOf name names).map DB.Trm.var
  | .unit => some .unit
  | .lam parameter type body =>
      (erase (parameter :: names) body).map (DB.Trm.lam type)
  | .app fn arg =>
      match erase names fn, erase names arg with
      | some erasedFn, some erasedArg => some (.app erasedFn erasedArg)
      | _, _ => none

theorem lookup_position (lookup : Γ.lookup name = some type) :
    ∃ index,
      indexOf name (contextNames Γ) = some index ∧
      (contextTypes Γ)[index]? = some type := by
  induction Γ with
  | nil => simp at lookup
  | cons entry rest ih =>
      rcases entry with ⟨boundName, boundType⟩
      by_cases same : boundName = name
      · subst boundName
        have typeSame : boundType = type := by
          simpa only [List.lookup_cons_self, Option.some.injEq] using lookup
        subst boundType
        exact ⟨0, by simp [contextNames, indexOf], by simp [contextTypes]⟩
      · have reverse : name ≠ boundName := Ne.symm same
        have beqFalse : (name == boundName) = false :=
          beq_eq_false_iff_ne.mpr reverse
        simp only [List.lookup_cons, beqFalse] at lookup
        rcases ih lookup with ⟨index, nameAt, typeAt⟩
        refine ⟨index + 1, ?_, ?_⟩
        · simp [contextNames, indexOf, reverse, nameAt]
        · simpa [contextTypes] using typeAt

theorem erase_typing (derivation : typing Γ term type) :
    ∃ erased,
      erase (contextNames Γ) term = some erased ∧
      DB.typing (contextTypes Γ) erased type := by
  induction derivation with
  | var lookup =>
      rcases lookup_position lookup with ⟨index, nameAt, typeAt⟩
      exact ⟨.var index, by simp [erase, nameAt], .var typeAt⟩
  | unit => exact ⟨.unit, rfl, .unit⟩
  | lam bodyTyping ih =>
      rcases ih with ⟨body, erasedBody, typedBody⟩
      exact ⟨.lam _ body, by simpa [erase, contextNames] using erasedBody,
        .lam (by simpa [contextTypes] using typedBody)⟩
  | app functionTyping argumentTyping functionIH argumentIH =>
      rcases functionIH with ⟨fn, erasedFn, typedFn⟩
      rcases argumentIH with ⟨arg, erasedArg, typedArg⟩
      exact ⟨.app fn arg, by simp [erase, erasedFn, erasedArg],
        .app typedFn typedArg⟩

def liftRen : Nat → (Nat → Nat) → Nat → Nat
  | 0, rho => rho
  | depth + 1, rho => DB.Trm.upRen (liftRen depth rho)

theorem liftRen_zero (rho : Nat → Nat) : liftRen 0 rho = rho := rfl

theorem liftRen_succ (depth : Nat) (rho : Nat → Nat) :
    liftRen (depth + 1) rho = DB.Trm.upRen (liftRen depth rho) := rfl

theorem indexOf_insert (different : name ≠ fresh)
    (found : indexOf name (pre ++ names) = some index) :
    indexOf name (pre ++ fresh :: names) =
      some (liftRen pre.length Nat.succ index) := by
  induction pre generalizing index with
  | nil =>
      simp only [List.nil_append, indexOf, different, ↓reduceIte] at found ⊢
      simpa using congrArg (Option.map (· + 1)) found
  | cons head pre ih =>
      by_cases same : name = head
      · subst head
        have zeroIndex : 0 = index := by simpa [indexOf] using found
        have indexZero : index = 0 := zeroIndex.symm
        subst index
        simp [indexOf, liftRen, DB.Trm.upRen]
      · simp only [List.cons_append, indexOf, same, ↓reduceIte] at found ⊢
        cases inner : indexOf name (pre ++ names) with
        | none => simp [inner] at found
        | some innerIndex =>
            have indexEq : innerIndex + 1 = index := by simpa [inner] using found
            subst index
            rw [ih inner]
            rfl

theorem erase_weaken (bound : term.maxNameLength < fresh.length)
    (encoded : erase (pre ++ names) term = some erased) :
    erase (pre ++ fresh :: names) term =
      some (erased.rename (liftRen pre.length Nat.succ)) := by
  induction term generalizing pre erased with
  | var name =>
      simp only [Trm.maxNameLength] at bound
      simp only [erase, Option.map_eq_some_iff] at encoded ⊢
      rcases encoded with ⟨index, found, rfl⟩
      refine ⟨liftRen pre.length Nat.succ index,
        indexOf_insert ?_ found, rfl⟩
      intro same
      subst name
      omega
  | unit =>
      simp only [erase, Option.some.injEq] at encoded ⊢
      cases encoded
      rfl
  | lam parameter type body ih =>
      simp only [Trm.maxNameLength, Nat.max_lt] at bound
      simp only [erase, Option.map_eq_some_iff] at encoded ⊢
      rcases encoded with ⟨erasedBody, bodyEncoded, rfl⟩
      refine ⟨erasedBody.rename
        (liftRen (parameter :: pre).length Nat.succ), ?_, ?_⟩
      · simpa only [List.cons_append] using
          ih bound.2 (pre := parameter :: pre) bodyEncoded
      · simp only [DB.Trm.rename, List.length_cons, liftRen_succ]
  | app fn arg fnIH argIH =>
      simp only [Trm.maxNameLength, Nat.max_lt] at bound
      simp only [erase] at encoded ⊢
      split at encoded <;> try contradiction
      next erasedFn erasedArg fnEq argEq =>
        cases encoded
        rw [fnIH bound.1 fnEq, argIH bound.2 argEq]
        rfl

theorem substitutionMaxNameLength_cons :
    Trm.substitutionMaxNameLength ((name, replacement) :: substitution) =
      max replacement.maxNameLength
        (Trm.substitutionMaxNameLength substitution) := by
  unfold Trm.substitutionMaxNameLength
  simp only [List.map_cons, List.max?_cons, Option.getD_some]
  cases (substitution.map
      (fun (_, term) => term.maxNameLength)).max? <;> simp

theorem freshFor_length :
    (Trm.freshFor body substitution).length =
      max body.maxNameLength (Trm.substitutionMaxNameLength substitution) + 1 := by
  simp [Trm.freshFor]

def replacementFor (substitution : Trm.Substitution) (name : Name) : Trm :=
  (substitution.lookup name).getD (.var name)

def SubRel (sourceNames targetNames : List Name)
    (substitution : Trm.Substitution) (dbSubstitution : Nat → DB.Trm) : Prop :=
  ∀ {name index}, indexOf name sourceNames = some index →
    erase targetNames (replacementFor substitution name) =
      some (dbSubstitution index) ∧
    (replacementFor substitution name).maxNameLength ≤
      Trm.substitutionMaxNameLength substitution

theorem subRel_extend (relation : SubRel sourceNames targetNames substitution σ) :
    let fresh := Trm.freshFor body substitution
    SubRel (parameter :: sourceNames) (fresh :: targetNames)
      ((parameter, .var fresh) :: substitution) (DB.Trm.upSub σ) := by
  dsimp
  intro name index found
  let fresh := Trm.freshFor body substitution
  by_cases same : name = parameter
  · subst name
    have zeroIndex : 0 = index := by simpa [indexOf] using found
    subst index
    constructor
    · simp [replacementFor, erase, indexOf, DB.Trm.upSub]
    · rw [substitutionMaxNameLength_cons]
      simpa [replacementFor, fresh, Trm.maxNameLength] using
        Nat.le_max_left fresh.length
          (Trm.substitutionMaxNameLength substitution)
  · simp only [indexOf, same, ↓reduceIte] at found
    cases tailFound : indexOf name sourceNames with
    | none => simp [tailFound] at found
    | some tailIndex =>
        have indexEq : tailIndex + 1 = index := by
          simpa [tailFound] using found
        subst index
        have reverse : name ≠ parameter := same
        have beqFalse : (name == parameter) = false :=
          beq_eq_false_iff_ne.mpr reverse
        have replacementEq :
            replacementFor ((parameter, .var fresh) :: substitution) name =
              replacementFor substitution name := by
          simp [replacementFor, List.lookup_cons, beqFalse]
        rcases relation tailFound with ⟨encoded, bounded⟩
        constructor
        · rw [replacementEq]
          have strict :
              (replacementFor substitution name).maxNameLength < fresh.length := by
            rw [freshFor_length]
            omega
          simpa [DB.Trm.upSub] using
            erase_weaken (pre := []) strict encoded
        · rw [replacementEq, substitutionMaxNameLength_cons]
          exact Nat.le_trans bounded (Nat.le_max_right _ _)

theorem erase_substAll (relation : SubRel sourceNames targetNames substitution σ)
    (encoded : erase sourceNames term = some erased) :
    erase targetNames (term.substAll substitution) =
      some (erased.subst σ) := by
  induction term generalizing sourceNames targetNames substitution σ erased with
  | var name =>
      simp only [erase, Option.map_eq_some_iff] at encoded
      rcases encoded with ⟨index, found, rfl⟩
      simpa [Trm.substAll, replacementFor] using (relation found).1
  | unit =>
      simp only [erase, Option.some.injEq] at encoded
      cases encoded
      rfl
  | lam parameter type body ih =>
      simp only [erase, Option.map_eq_some_iff] at encoded
      rcases encoded with ⟨erasedBody, bodyEncoded, rfl⟩
      simp only [Trm.substAll, DB.Trm.subst, erase]
      rw [ih (subRel_extend (body := body) (parameter := parameter) relation)
        bodyEncoded]
      rfl
  | app fn arg fnIH argIH =>
      simp only [erase] at encoded
      split at encoded <;> try contradiction
      next erasedFn erasedArg fnEncoded argEncoded =>
        cases encoded
        simp only [Trm.substAll, DB.Trm.subst, erase]
        rw [fnIH relation fnEncoded, argIH relation argEncoded]

theorem beta_substitution (bodyEncoded : erase [parameter] body = some erasedBody)
    (argumentEncoded : erase [] argument = some erasedArgument) :
    erase [] (body.subst parameter argument) =
      some (erasedBody.subst0 erasedArgument) := by
  let σ : Nat → DB.Trm := fun
    | 0 => erasedArgument
    | index + 1 => .var index
  have relation : SubRel [parameter] [] [(parameter, argument)] σ := by
    intro name index found
    have nameEq : name = parameter := by
      by_cases same : name = parameter
      · exact same
      · have impossible : indexOf name [parameter] = none := by
          simp [indexOf, same]
        rw [impossible] at found
        contradiction
    subst name
    have indexEq : index = 0 := by
      have : 0 = index := by simpa [indexOf] using found
      exact this.symm
    subst index
    constructor
    · simpa [replacementFor, σ] using argumentEncoded
    · rw [substitutionMaxNameLength_cons]
      simp [replacementFor, Trm.substitutionMaxNameLength]
  simpa [Trm.subst, DB.Trm.subst0, σ] using
    erase_substAll relation bodyEncoded

theorem erase_unit_inv (encoded : erase names term = some .unit) :
    term = .unit := by
  cases term with
  | var name => simp [erase] at encoded
  | unit => rfl
  | lam parameter type body => simp [erase] at encoded
  | app fn arg =>
      simp only [erase] at encoded
      split at encoded <;> try contradiction
      next => cases encoded

theorem erase_lam_inv (encoded : erase names term = some (.lam type erasedBody)) :
    ∃ parameter body,
      term = .lam parameter type body ∧
      erase (parameter :: names) body = some erasedBody := by
  cases term with
  | var name => simp [erase] at encoded
  | unit => simp [erase] at encoded
  | lam parameter nominalType body =>
      simp only [erase, Option.map_eq_some_iff] at encoded
      rcases encoded with ⟨bodyResult, bodyEncoded, equality⟩
      cases equality
      exact ⟨parameter, body, rfl, bodyEncoded⟩
  | app fn arg =>
      simp only [erase] at encoded
      split at encoded <;> try contradiction
      next => cases encoded

theorem erase_app_inv (encoded : erase names term = some (.app erasedFn erasedArg)) :
    ∃ fn arg,
      term = .app fn arg ∧
      erase names fn = some erasedFn ∧
      erase names arg = some erasedArg := by
  cases term with
  | var name => simp [erase] at encoded
  | unit => simp [erase] at encoded
  | lam parameter type body => simp [erase] at encoded
  | app fn arg =>
      simp only [erase] at encoded
      split at encoded <;> try contradiction
      next fnResult argResult fnEncoded argEncoded =>
        cases encoded
        exact ⟨fn, arg, rfl, fnEncoded, argEncoded⟩

theorem value_of_erase (encoded : erase [] term = some erased)
    (value : DB.Value erased) : Value term := by
  cases value with
  | unit =>
      rw [erase_unit_inv encoded]
      exact .unit
  | lam =>
      rcases erase_lam_inv encoded with ⟨parameter, body, rfl, _⟩
      exact .lam

theorem lift_step (encoded : erase [] term = some erased)
    (reduction : DB.Step erased erased') :
    ∃ term', Step term term' ∧ erase [] term' = some erased' := by
  induction reduction generalizing term with
  | beta argumentValue =>
      rcases erase_app_inv encoded with
        ⟨fn, argument, rfl, fnEncoded, argumentEncoded⟩
      rcases erase_lam_inv fnEncoded with
        ⟨parameter, body, rfl, bodyEncoded⟩
      have nominalValue := value_of_erase argumentEncoded argumentValue
      exact ⟨body.subst parameter argument, .beta nominalValue,
        beta_substitution bodyEncoded argumentEncoded⟩
  | appLeft functionStep ih =>
      rcases erase_app_inv encoded with
        ⟨fn, argument, rfl, fnEncoded, argumentEncoded⟩
      rcases ih fnEncoded with ⟨fn', nominalStep, fn'Encoded⟩
      exact ⟨.app fn' argument, .appLeft nominalStep,
        by simp [erase, fn'Encoded, argumentEncoded]⟩
  | appRight functionValue argumentStep ih =>
      rcases erase_app_inv encoded with
        ⟨fn, argument, rfl, fnEncoded, argumentEncoded⟩
      have nominalValue := value_of_erase fnEncoded functionValue
      rcases ih argumentEncoded with ⟨argument', nominalStep, argument'Encoded⟩
      exact ⟨.app fn argument', .appRight nominalValue nominalStep,
        by simp [erase, fnEncoded, argument'Encoded]⟩

theorem lift_steps (encoded : erase [] term = some erased)
    (reductions : DB.Steps erased erased') :
    ∃ term', Steps term term' ∧ erase [] term' = some erased' := by
  induction reductions generalizing term with
  | refl => exact ⟨term, .refl, encoded⟩
  | tail earlier last ih =>
      rcases ih encoded with ⟨middle, nominalEarlier, middleEncoded⟩
      rcases lift_step middleEncoded last with
        ⟨lastTerm, nominalLast, lastEncoded⟩
      exact ⟨lastTerm, .tail nominalEarlier nominalLast, lastEncoded⟩

end Nominal

theorem termination : Termination := by
  intro term type derivation
  rcases Nominal.erase_typing derivation with
    ⟨erased, encoded, erasedTyping⟩
  rcases DB.termination erasedTyping with
    ⟨erasedValue, reductions, isErasedValue⟩
  rcases Nominal.lift_steps encoded reductions with
    ⟨value, nominalReductions, valueEncoded⟩
  exact ⟨value, nominalReductions,
    Nominal.value_of_erase valueEncoded isErasedValue⟩
