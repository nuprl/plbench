(** Invocation of migration executables with bounded resources. *)

val run :
  timeout_seconds:int ->
  executable:string ->
  input:string ->
  (string, string) result
(** [run ~timeout_seconds ~executable ~input] invokes [executable input] and
    returns its standard output. Nonzero exits, oversized output, and timeout
    failures are returned as concise diagnostics. *)
