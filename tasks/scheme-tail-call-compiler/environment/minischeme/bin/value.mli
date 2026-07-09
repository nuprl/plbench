(** Runtime values and environments for MiniScheme. *)

(** A MiniScheme runtime value.

    Source datums and evaluated values share the same representation: quoted
    programs are ordinary lists, symbols, strings, numbers, booleans, and
    vectors. Procedures are represented by closures or builtins. *)
type t =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Symbol of string
  | List of t list
  | Vector of t array
  | Closure of {
      params : string list;
      body : t;
      env : env;
    }
  | Builtin of string * (t list -> t)

(** Lexically scoped environment. *)
and env

(** Raised for dynamic type failures, such as applying a non-procedure or
    calling a builtin with an argument of the wrong kind. *)
exception Type_error of string

(** Raised by MiniScheme's [error] builtin. *)
exception Runtime_error of string

(** Raised when source text cannot be parsed as MiniScheme. *)
exception Parse_error of string

(** [to_string value] renders [value] in MiniScheme syntax when possible. *)
val to_string : t -> string

(** [make_env ?parent ()] creates an empty environment, optionally chained to
    [parent] for lexical lookup. *)
val make_env : ?parent:env -> unit -> env

(** [lookup env name] returns the current binding for [name].

    Raises {!Type_error} if [name] is unbound. *)
val lookup : env -> string -> t

(** [define env name value] installs or replaces a binding in [env]. *)
val define : env -> string -> t -> unit

(** [set_existing env name value] updates the nearest lexical binding named
    [name]. Raises {!Type_error} when no such binding exists. *)
val set_existing : env -> string -> t -> unit

(** [extend env params args] creates a child environment binding [params] to
    [args].

    Raises {!Type_error} when the lists have different lengths. *)
val extend : env -> string list -> t list -> env

(** Coerce a value to a numeric value accepted by arithmetic builtins. *)
val as_number : who:string -> t -> [ `Int of int | `Float of float ]

(** Coerce a value to an integer. *)
val as_int : who:string -> t -> int

(** Coerce a value to a list. *)
val as_list : who:string -> t -> t list

(** Coerce a value to a string. *)
val as_string : who:string -> t -> string

(** Coerce a value to a symbol name. *)
val as_symbol : who:string -> t -> string

(** Coerce a value to a vector. *)
val as_vector : who:string -> t -> t array

(** Coerce a value to a boolean. *)
val as_bool : who:string -> t -> bool

(** MiniScheme truthiness: only [#f] is false. *)
val is_truthy : t -> bool

(** Structural equality used by the [equal?] builtin. *)
val equal : t -> t -> bool
