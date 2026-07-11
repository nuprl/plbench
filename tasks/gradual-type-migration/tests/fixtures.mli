(** Typed loading of the verifier's YAML benchmark document. *)

type context = { source : string; expected : string }
(** A closing program context and its recorded observable outcome. *)

type case = {
  name : string;
  program : string;
  oracle_migration : string;
  contexts : context list;
}
(** A challenge program, vetted best migration, and closing contexts whose
    [source] contains [HOLE]. *)

val load : string -> case list
(** Decode the YAML case array. *)
