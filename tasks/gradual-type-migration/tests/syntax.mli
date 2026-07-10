(** Abstract syntax for the gradual lambda calculus used by the task. *)

(** Gradual types. [Any] is the unknown type. *)
type typ = Int | Bool | Any | Arr of typ * typ

(** The two primitive integer operations. *)
type binary_operator = Add | Multiply

(** Source expressions. A [Fun] annotation is absent only in challenge input. *)
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
(** Render a type in the surface syntax. *)

val show_expr : expr -> string
(** Render an expression canonically, for diagnostics and probe identity. *)

val has_annotation : expr -> bool
(** Whether an expression contains a lambda annotation or an ascription. *)
