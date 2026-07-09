(** MiniScheme source reader.

    The reader accepts one or more MiniScheme datum forms from a string. It
    supports semicolon line comments, string escapes, quote shorthand, lists,
    and vector literals. *)

(** [read_all src] parses every datum in [src], in source order.

    Raises {!Value.Parse_error} when [src] is not valid MiniScheme syntax. *)
val read_all : string -> Value.t list
