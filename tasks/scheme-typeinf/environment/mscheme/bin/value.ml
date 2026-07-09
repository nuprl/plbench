(** MiniScheme runtime values. *)

type t =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Symbol of string
  | List of t list
  | Vector of t array
  | Closure of {
      params : string list;
      body : t;
      env : env;
    }
  | Builtin of string * (t list -> t)

and env = {
  parent : env option;
  bindings : (string, t) Hashtbl.t;
}

exception Type_error of string
exception Runtime_error of string
exception Parse_error of string

let rec to_string = function
  | Int i -> string_of_int i
  | Float f ->
      let s = string_of_float f in
      if String.length s > 0 && s.[String.length s - 1] = '.' then s ^ "0" else s
  | Bool true -> "#t"
  | Bool false -> "#f"
  | String s ->
      let buf = Buffer.create (String.length s + 2) in
      Buffer.add_char buf '"';
      String.iter
        (function
          | '\\' -> Buffer.add_string buf "\\\\"
          | '"' -> Buffer.add_string buf "\\\""
          | '\n' -> Buffer.add_string buf "\\n"
          | '\t' -> Buffer.add_string buf "\\t"
          | c -> Buffer.add_char buf c)
        s;
      Buffer.add_char buf '"';
      Buffer.contents buf
  | Symbol name -> name
  | List xs -> "(" ^ String.concat " " (List.map to_string xs) ^ ")"
  | Vector arr ->
      "#("
      ^ String.concat " " (Array.to_list (Array.map to_string arr))
      ^ ")"
  | Closure _ -> "#<closure>"
  | Builtin (name, _) -> "#<builtin " ^ name ^ ">"

let make_env ?parent () : env =
  { parent; bindings = Hashtbl.create 16 }

let rec lookup (e : env) (name : string) : t =
  match Hashtbl.find_opt e.bindings name with
  | Some v -> v
  | None -> (
      match e.parent with
      | Some p -> lookup p name
      | None -> raise (Type_error ("unbound variable: " ^ name)))

let define (e : env) (name : string) (v : t) : unit =
  Hashtbl.replace e.bindings name v

let extend (e : env) (params : string list) (args : t list) : env =
  let child = make_env ~parent:e () in
  let rec loop ps as_ =
    match (ps, as_) with
    | [], [] -> ()
    | p :: ps', a :: as' ->
        define child p a;
        loop ps' as'
    | _, _ ->
        raise
          (Type_error
             (Printf.sprintf "arity mismatch: expected %d args, got %d"
                (List.length params) (List.length args)))
  in
  loop params args;
  child

let as_number ~who = function
  | Int i -> `Int i
  | Float f -> `Float f
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected number, got %s" who (to_string v)))

let as_int ~who = function
  | Int i -> i
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected integer, got %s" who (to_string v)))

let as_list ~who = function
  | List xs -> xs
  | v ->
      raise (Type_error (Printf.sprintf "%s: expected list, got %s" who (to_string v)))

let as_string ~who = function
  | String s -> s
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected string, got %s" who (to_string v)))

let as_symbol ~who = function
  | Symbol s -> s
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected symbol, got %s" who (to_string v)))

let as_vector ~who = function
  | Vector a -> a
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected vector, got %s" who (to_string v)))

let as_bool ~who = function
  | Bool b -> b
  | v ->
      raise
        (Type_error (Printf.sprintf "%s: expected boolean, got %s" who (to_string v)))

let is_truthy = function
  | Bool false -> false
  | _ -> true

let rec equal a b =
  match (a, b) with
  | Int x, Int y -> x = y
  | Float x, Float y -> x = y
  | Int x, Float y -> float_of_int x = y
  | Float x, Int y -> x = float_of_int y
  | Bool x, Bool y -> x = y
  | String x, String y -> x = y
  | Symbol x, Symbol y -> x = y
  | List xs, List ys ->
      List.length xs = List.length ys && List.for_all2 equal xs ys
  | Vector xs, Vector ys ->
      Array.length xs = Array.length ys
      &&
      let ok = ref true in
      for i = 0 to Array.length xs - 1 do
        if not (equal xs.(i) ys.(i)) then ok := false
      done;
      !ok
  | _ -> false
