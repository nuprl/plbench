(** Static validation of a proposed gradual-type migration. *)

val parse : description:string -> string -> (Syntax.expr, string) result
(** Parse verifier or contestant output, prefixing parse errors with
    [description]. *)

val validate :
  original:Syntax.expr -> migrated:Syntax.expr -> (Syntax.typ, string) result
(** Type-check both programs, then check that their non-type syntax (including
    names) is identical, their annotations are pointwise ordered, and every
    lambda in [migrated] is explicitly annotated. *)

val precision_below :
  candidate:Syntax.expr -> maximum:Syntax.expr -> (int * int) option
(** Return the candidate's earned and possible decoration information when it is
    no more precise than [maximum]. Lambda annotations are compared pointwise.
    At each position in the undecorated expression, a candidate may omit an
    ascription present in [maximum]; a candidate ascription must have a
    corresponding ascription in [maximum] and be no more precise. Return [None]
    for incomparable migrations. *)
