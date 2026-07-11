(** Bounded subprocess invocation for the verifier. *)

type output = { status : int; stdout : string; stderr : string }
(** Captured process output and its numeric exit status. Status [124] denotes
    expiration of the external timeout. *)

val run :
  timeout_seconds:int ->
  executable:string ->
  arguments:string list ->
  (output, string) result
(** Invoke [executable] with [arguments]. Oversized output or an invocation
    failure is returned as an infrastructure diagnostic. *)

val diagnostic : output -> string
(** A concise diagnostic chosen from standard error and standard output. *)
