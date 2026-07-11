(** Parser for the GTLC surface language. *)

exception Error of string
(** A malformed source program, with a byte-oriented diagnostic. *)

val parse : string -> Syntax.expr
(** Parse exactly one expression. *)

val parse_file : string -> Syntax.expr
(** Read and parse exactly one expression from a file. *)
