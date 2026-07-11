(** Recognition of the task's syntactic migration relation. *)

val check : original:Syntax.expr -> migrated:Syntax.expr -> bool
(** [check ~original ~migrated] first type-checks both programs, then recognizes
    pointwise syntactic precision. Corresponding non-type syntax, including all variable
    and binder names, must be identical; each type decoration in [original] must be no
    more precise than its counterpart in [migrated]. A missing decoration denotes [any].
    A static error is raised if either program does not type-check. *)
