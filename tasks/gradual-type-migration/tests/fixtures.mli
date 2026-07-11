(** Typed loading of the verifier's YAML benchmark document. *)

type case = {
  name : string;
  program : string;
  oracle_migration : string;
  context : string option;
  maximal_migrations : string list;
}
(** A challenge program, default TypeWhich's migration, an optional witness
    context containing [HOLE], and its curated maximal compatible migrations. *)

val load : string -> case list
(** Decode the YAML case array. *)
