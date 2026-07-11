(** Typed loading of the verifier's YAML benchmark document. *)

type case = {
  name : string;
  program : string;
  oracle_migration : string;
  contexts : string list;
}
(** A challenge program, default TypeWhich migration, and closing contexts that
    contain the token [HOLE]. *)

val load : string -> case list
(** Decode the YAML case array. *)
