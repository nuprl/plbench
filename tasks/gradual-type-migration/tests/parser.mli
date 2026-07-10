(** Parser for the task's GTLC surface language. *)

exception Error of string
(** Raised for malformed source, with a byte-oriented diagnostic. *)

val parse : string -> Syntax.expr
(** Parse exactly one expression. Inputs larger than 1 MB are rejected. *)
