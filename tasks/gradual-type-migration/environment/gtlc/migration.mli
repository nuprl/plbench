(** Recognition of the task's syntactic migration relation. *)

val check : original:Syntax.expr -> migrated:Syntax.expr -> bool
(** [check ~original ~migrated] first type-checks both programs, then recognizes
    pointwise syntactic precision. The expression structure, including the
    presence of every ascription and all variable and binder names, must be
    identical. Corresponding lambda annotations and ascription types may differ
    only when the original type is no more precise than the migrated type. A
    missing lambda annotation denotes [any]. A static error is raised if either
    program does not type-check. *)

val distance :
  less_precise:Syntax.expr -> more_precise:Syntax.expr -> int option
(** Count single-edge precision refinements between structurally corresponding
    programs. Returns [None] when the syntax differs or corresponding types are
    incomparable. Both programs are type-checked first. *)
