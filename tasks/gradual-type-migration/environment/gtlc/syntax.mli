(** Abstract syntax and pretty-printing for the task's gradual lambda calculus. *)

(** Gradual types. [Any] is the unknown type. *)
type typ = Int | Bool | Any | Arr of typ * typ

(** Primitive integer operations. *)
type binary_operator = Add | Multiply

(** Surface expressions. A missing lambda annotation denotes [Any]. *)
type expr =
  | Lit_int of int
  | Lit_bool of bool
  | Var of string
  | Fun of string * typ option * expr
  | App of expr * expr
  | Bin of binary_operator * expr * expr
  | If of expr * expr * expr
  | Let of string * expr * expr
  | Ann of expr * typ

val show_typ : typ -> string
(** Render a type in GTLC surface syntax. *)

val show_expr : expr -> string
(** Render an expression in an unambiguous canonical form. *)

val count_anys : expr -> int
(** Count lambda annotations and expression ascriptions whose complete type is
    [any]. A missing lambda annotation counts as an implicit [any]. *)
