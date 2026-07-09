(** MiniScheme evaluator and builtins. *)

open Value

let special = function
  | "quote" | "lambda" | "if" | "let" | "letrec" | "begin" | "and" | "or"
  | "cond" | "define" ->
      true
  | _ -> false

let rec apply_proc (proc : t) (args : t list) : t =
  match proc with
  | Builtin (_, fn) -> fn args
  | Closure { params; body; env } ->
      eval_expr body (extend env params args)
  | v -> raise (Type_error ("apply: not a procedure: " ^ to_string v))

and eval_expr (expr : t) (env : env) : t =
  match expr with
  | Bool _ | Int _ | Float _ | String _ -> expr
  | Symbol name -> lookup env name
  | Vector _ | Closure _ | Builtin _ ->
      raise (Type_error ("cannot evaluate: " ^ to_string expr))
  | List [] -> raise (Type_error "cannot evaluate empty list as expression")
  | List (head :: rest) -> (
      match head with
      | Symbol name when special name -> eval_special name (head :: rest) env
      | _ ->
          let vals = List.map (fun e -> eval_expr e env) (head :: rest) in
          apply_proc (List.hd vals) (List.tl vals))

and eval_special name expr env =
  match name with
  | "quote" -> (
      match expr with
      | [ _; datum ] -> datum
      | _ -> raise (Type_error "quote: expected 1 argument"))
  | "lambda" -> (
      match expr with
      | [ _; List params; body ] ->
          let ps =
            List.map
              (function
                | Symbol s -> s
                | _ -> raise (Type_error "lambda: params must be symbols"))
              params
          in
          Closure { params = ps; body; env }
      | _ -> raise (Type_error "lambda: expected (lambda (params) body)"))
  | "if" -> (
      match expr with
      | [ _; test; thn; els ] ->
          if is_truthy (eval_expr test env) then eval_expr thn env
          else eval_expr els env
      | _ -> raise (Type_error "if: expected (if test then else)"))
  | "let" -> (
      match expr with
      | [ _; List bindings; body ] ->
          let names, vals =
            List.split
              (List.map
                 (function
                   | List [ Symbol n; e ] -> (n, eval_expr e env)
                   | _ -> raise (Type_error "let: bad binding"))
                 bindings)
          in
          eval_expr body (extend env names vals)
      | _ -> raise (Type_error "let: expected (let ((x e) ...) body)"))
  | "letrec" -> (
      match expr with
      | [ _; List bindings; body ] ->
          let child = make_env ~parent:env () in
          let specs =
            List.map
              (function
                | List [ Symbol n; e ] ->
                    define child n (Bool false);
                    (n, e)
                | _ -> raise (Type_error "letrec: bad binding"))
              bindings
          in
          List.iter
            (fun (n, e) -> define child n (eval_expr e child))
            specs;
          eval_expr body child
      | _ -> raise (Type_error "letrec: expected (letrec ((x e) ...) body)"))
  | "begin" -> (
      match expr with
      | _ :: es when es <> [] ->
          List.fold_left (fun _ e -> eval_expr e env) (Bool false) es
      | _ -> raise (Type_error "begin: expected at least one expression"))
  | "and" -> (
      let rec loop = function
        | [] -> Bool true
        | [ e ] -> eval_expr e env
        | e :: es ->
            let v = eval_expr e env in
            if is_truthy v then loop es else v
      in
      loop (List.tl expr))
  | "or" -> (
      let rec loop = function
        | [] -> Bool false
        | [ e ] -> eval_expr e env
        | e :: es ->
            let v = eval_expr e env in
            if is_truthy v then v else loop es
      in
      loop (List.tl expr))
  | "cond" -> (
      let rec loop = function
        | [] -> raise (Type_error "cond: no clause matched")
        | List [ Symbol "else"; body ] :: _ -> eval_expr body env
        | List [ test; body ] :: rest ->
            if is_truthy (eval_expr test env) then eval_expr body env
            else loop rest
        | _ -> raise (Type_error "cond: bad clause")
      in
      loop (List.tl expr))
  | "define" -> raise (Type_error "define: only valid at top level")
  | _ -> raise (Runtime_error ("unknown special form: " ^ name))

let eval_define parts env =
  match parts with
  | [ Symbol name; e ] ->
      let v = eval_expr e env in
      define env name v;
      Symbol name
  | List (Symbol fname :: params) :: [ body ] ->
      let ps =
        List.map
          (function
            | Symbol s -> s
            | _ -> raise (Type_error "define: params must be symbols"))
          params
      in
      let clo = Closure { params = ps; body; env } in
      define env fname clo;
      Symbol fname
  | _ -> raise (Type_error "define: bad syntax")

let rec eval_toplevel forms env =
  let result = ref (Bool false) in
  List.iter
    (fun form ->
      match form with
      | List (Symbol "define" :: parts) -> result := eval_define parts env
      | List (Symbol "begin" :: rest) -> result := eval_toplevel rest env
      | _ -> result := eval_expr form env)
    forms;
  !result

(* ---- builtins ---- *)

let require_arity name n args =
  if List.length args <> n then
    raise
      (Type_error
         (Printf.sprintf "%s: expected %d args, got %d" name n (List.length args)))

let num_list ~who args =
  List.map (as_number ~who) args

let add_nums xs =
  let rec loop acc = function
    | [] -> acc
    | `Int i :: rest -> (
        match acc with
        | `Int a -> loop (`Int (a + i)) rest
        | `Float a -> loop (`Float (a +. float_of_int i)) rest)
    | `Float f :: rest -> (
        match acc with
        | `Int a -> loop (`Float (float_of_int a +. f)) rest
        | `Float a -> loop (`Float (a +. f)) rest)
  in
  match loop (`Int 0) xs with
  | `Int i -> Int i
  | `Float f -> Float f

let sub_nums xs =
  match xs with
  | [] -> raise (Type_error "-: expected at least 1 arg")
  | [ `Int i ] -> Int (-i)
  | [ `Float f ] -> Float (-.f)
  | h :: t ->
      let rec loop acc = function
        | [] -> acc
        | `Int i :: rest -> (
            match acc with
            | `Int a -> loop (`Int (a - i)) rest
            | `Float a -> loop (`Float (a -. float_of_int i)) rest)
        | `Float f :: rest -> (
            match acc with
            | `Int a -> loop (`Float (float_of_int a -. f)) rest
            | `Float a -> loop (`Float (a -. f)) rest)
      in
      (match loop h t with `Int i -> Int i | `Float f -> Float f)

let mul_nums xs =
  let rec loop acc = function
    | [] -> acc
    | `Int i :: rest -> (
        match acc with
        | `Int a -> loop (`Int (a * i)) rest
        | `Float a -> loop (`Float (a *. float_of_int i)) rest)
    | `Float f :: rest -> (
        match acc with
        | `Int a -> loop (`Float (float_of_int a *. f)) rest
        | `Float a -> loop (`Float (a *. f)) rest)
  in
  match loop (`Int 1) xs with
  | `Int i -> Int i
  | `Float f -> Float f

let div_nums xs =
  let to_f = function `Int i -> float_of_int i | `Float f -> f in
  match xs with
  | [] -> raise (Type_error "/: expected at least 1 arg")
  | [ x ] -> Float (1.0 /. to_f x)
  | h :: t ->
      Float (List.fold_left (fun acc x -> acc /. to_f x) (to_f h) t)

let cmp_nums op ~who args =
  if List.length args < 2 then
    raise (Type_error (who ^ ": expected at least 2 args"));
  let ns = num_list ~who args in
  let to_f = function `Int i -> float_of_int i | `Float f -> f in
  let rec loop = function
    | _ :: [] | [] -> true
    | a :: b :: rest -> op (to_f a) (to_f b) && loop (b :: rest)
  in
  Bool (loop ns)

let builtin name arity fn =
  let wrapped args =
    (match arity with
    | Some n -> require_arity name n args
    | None -> ());
    fn args
  in
  (name, Builtin (name, wrapped))

let make_global_env () : env =
  let env = make_env () in
  let install (name, v) = define env name v in
  List.iter install
    [
      builtin "+" None (fun args -> add_nums (num_list ~who:"+" args));
      builtin "-" None (fun args -> sub_nums (num_list ~who:"-" args));
      builtin "*" None (fun args -> mul_nums (num_list ~who:"*" args));
      builtin "/" None (fun args -> div_nums (num_list ~who:"/" args));
      builtin "=" None (cmp_nums ( = ) ~who:"=");
      builtin "<" None (cmp_nums ( < ) ~who:"<");
      builtin ">" None (cmp_nums ( > ) ~who:">");
      builtin "<=" None (cmp_nums ( <= ) ~who:"<=");
      builtin ">=" None (cmp_nums ( >= ) ~who:">=");
      builtin "number?" (Some 1) (function
        | [ Int _ ] | [ Float _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "integer?" (Some 1) (function
        | [ Int _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "float?" (Some 1) (function
        | [ Float _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "boolean?" (Some 1) (function
        | [ Bool _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "string?" (Some 1) (function
        | [ String _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "symbol?" (Some 1) (function
        | [ Symbol _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "procedure?" (Some 1) (function
        | [ Closure _ ] | [ Builtin _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "null?" (Some 1) (function
        | [ List [] ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "pair?" (Some 1) (function
        | [ List (_ :: _) ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "list?" (Some 1) (function
        | [ List _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "vector?" (Some 1) (function
        | [ Vector _ ] -> Bool true
        | [ _ ] -> Bool false
        | _ -> assert false);
      builtin "not" (Some 1) (function
        | [ v ] -> Bool (not (as_bool ~who:"not" v))
        | _ -> assert false);
      builtin "eq?" (Some 2) (function
        | [ Symbol a; Symbol b ] -> Bool (a = b)
        | [ Bool a; Bool b ] -> Bool (a = b)
        | [ List []; List [] ] -> Bool true
        | [ a; b ] -> Bool (a == b)
        | _ -> assert false);
      builtin "equal?" (Some 2) (function
        | [ a; b ] -> Bool (equal a b)
        | _ -> assert false);
      builtin "cons" (Some 2) (function
        | [ a; d ] -> List (a :: as_list ~who:"cons" d)
        | _ -> assert false);
      builtin "car" (Some 1) (function
        | [ v ] -> (
            match as_list ~who:"car" v with
            | [] -> raise (Type_error "car: empty list")
            | x :: _ -> x)
        | _ -> assert false);
      builtin "cdr" (Some 1) (function
        | [ v ] -> (
            match as_list ~who:"cdr" v with
            | [] -> raise (Type_error "cdr: empty list")
            | _ :: xs -> List xs)
        | _ -> assert false);
      builtin "list" None (fun args -> List args);
      builtin "length" (Some 1) (function
        | [ v ] -> Int (List.length (as_list ~who:"length" v))
        | _ -> assert false);
      builtin "append" None (fun args ->
          List
            (List.concat
               (List.map (as_list ~who:"append") args)));
      builtin "list-ref" (Some 2) (function
        | [ xs; i ] ->
            let lst = as_list ~who:"list-ref" xs in
            let idx = as_int ~who:"list-ref" i in
            if idx < 0 || idx >= List.length lst then
              raise (Type_error "list-ref: index out of bounds")
            else List.nth lst idx
        | _ -> assert false);
      builtin "vector" None (fun args -> Vector (Array.of_list args));
      builtin "vector-length" (Some 1) (function
        | [ v ] -> Int (Array.length (as_vector ~who:"vector-length" v))
        | _ -> assert false);
      builtin "vector-ref" (Some 2) (function
        | [ v; i ] ->
            let arr = as_vector ~who:"vector-ref" v in
            let idx = as_int ~who:"vector-ref" i in
            if idx < 0 || idx >= Array.length arr then
              raise (Type_error "vector-ref: index out of bounds")
            else arr.(idx)
        | _ -> assert false);
      builtin "string-length" (Some 1) (function
        | [ v ] -> Int (String.length (as_string ~who:"string-length" v))
        | _ -> assert false);
      builtin "string-append" None (fun args ->
          String
            (String.concat ""
               (List.map (as_string ~who:"string-append") args)));
      builtin "string-ref" (Some 2) (function
        | [ s; i ] ->
            let st = as_string ~who:"string-ref" s in
            let idx = as_int ~who:"string-ref" i in
            if idx < 0 || idx >= String.length st then
              raise (Type_error "string-ref: index out of bounds")
            else String (String.make 1 st.[idx])
        | _ -> assert false);
      builtin "string->symbol" (Some 1) (function
        | [ v ] -> Symbol (as_string ~who:"string->symbol" v)
        | _ -> assert false);
      builtin "symbol->string" (Some 1) (function
        | [ v ] -> String (as_symbol ~who:"symbol->string" v)
        | _ -> assert false);
      builtin "error" (Some 1) (function
        | [ v ] -> raise (Runtime_error (as_string ~who:"error" v))
        | _ -> assert false);
      builtin "apply" (Some 2) (function
        | [ f; args ] -> apply_proc f (as_list ~who:"apply" args)
        | _ -> assert false);
    ];
  env

let load_file path env =
  let ic = open_in path in
  let len = in_channel_length ic in
  let src = really_input_string ic len in
  close_in ic;
  eval_toplevel (Reader.read_all src) env
