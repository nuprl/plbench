(** Trusted static and dynamic semantics used by the verifier. *)

(** Observable outcomes of a closed program. *)
type outcome =
  | Function
  | Integer of int
  | Boolean of bool
  | Runtime_error
  | Diverge

exception Static_error of string
(** Raised when elaboration encounters an unbound identifier. *)

val infer : Syntax.expr -> Syntax.typ
(** Elaborate an expression and return its gradual type. *)

val structurally_equal : Syntax.expr -> Syntax.expr -> bool
(** Test structural equality after erasing annotations, modulo binder renaming.
*)

val all_lambdas_annotated : Syntax.expr -> bool
(** Whether every lambda parameter carries an annotation. *)

val type_leq : Syntax.typ -> Syntax.typ -> bool
(** Whether the second type is at least as precise as the first. *)

val run : Syntax.expr -> outcome
(** Evaluate a closed expression with guarded, deterministic fuel. *)

val apply_args : Syntax.expr -> Syntax.expr list -> Syntax.expr
(** Apply a program through an [any] boundary to closing-context arguments. *)
