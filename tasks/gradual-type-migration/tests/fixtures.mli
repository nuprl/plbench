(** Typed loading of the verifier's YAML benchmark document. *)

type case = {
  name : string;
  program : string;
  context : string option;
  maximal_migrations : string list;
}
(** A challenge program, an optional TypeWhich witness context containing
    [HOLE], and its curated maximal compatible migrations. *)

val load : string -> case list
(** Decode the YAML case array. *)
