(** Evaluator and builtin environment for MiniScheme. *)

(** [eval_expr expr env] evaluates one expression in [env].

    Raises {!Value.Type_error} for dynamic type errors and unbound variables,
    and {!Value.Runtime_error} for explicit MiniScheme runtime errors. *)
val eval_expr : Value.t -> Value.env -> Value.t

(** [eval_toplevel forms env] evaluates a sequence of top-level forms.

    Top-level [define] forms extend [env]. A top-level [begin] is flattened so
    its definitions behave like ordinary top-level definitions. The result is
    the value of the last form, or [#f] for an empty sequence. *)
val eval_toplevel : Value.t list -> Value.env -> Value.t

(** [make_global_env ()] creates an environment populated with MiniScheme's
    standard builtins. *)
val make_global_env : unit -> Value.env

(** [load_file path env] parses and evaluates every form in [path] using
    [env], returning the final value. *)
val load_file : string -> Value.env -> Value.t
