(** MiniScheme source reader.

    The reader accepts one or more MiniScheme datum forms from a string. It
    supports semicolon line comments, string escapes, quote shorthand, lists,
    and vector literals. *)

(** [read_all src] parses every datum in [src], in source order, then checks
    the well-formedness of special-form expressions.

    Raises {!Value.Parse_error} when [src] is not valid MiniScheme syntax or
    contains a malformed special form. *)
val read_all : string -> Value.t list

(** [validate_closed ~initial forms] checks that every unquoted symbol
    expression in [forms] is bound by [initial], a top-level definition, or a
    lexical binder.

    Raises {!Value.Parse_error} on unbound variables. *)
val validate_closed : initial:string list -> Value.t list -> unit
