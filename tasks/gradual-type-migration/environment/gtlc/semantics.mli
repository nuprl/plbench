(** Static and dynamic semantics for GTLC. *)

(** Observable results of evaluating a closed expression. *)
type outcome = Function | Integer of int | Boolean of bool

exception Static_error of string
(** Elaboration encountered an unbound identifier. *)

exception Runtime_error of string
(** Evaluation encountered a failing guarded cast or invalid operation. *)

val infer : Syntax.expr -> Syntax.typ
(** Infer the gradual type of an expression, inserting the casts prescribed by the
    language semantics internally. *)

val run : Syntax.expr -> outcome
(** Evaluate a closed expression to an observable result. There is deliberately no fuel
    or timeout: a diverging source expression makes this function diverge. *)

val type_leq : Syntax.typ -> Syntax.typ -> bool
(** [type_leq a b] is true exactly when [b] is at least as precise as [a]. *)

val structurally_equal : Syntax.expr -> Syntax.expr -> bool
(** Compare expressions modulo binder renaming after erasing annotations and expression
    ascriptions. *)

val all_lambdas_annotated : Syntax.expr -> bool
(** Whether every lambda parameter has an explicit annotation. *)
