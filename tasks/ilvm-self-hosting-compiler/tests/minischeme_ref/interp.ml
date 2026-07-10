open Ast

type value =
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VSymbol of string
  | VList of value list
  | VVector of value array
  | VClosure of string list * Ast.t * env
  | VBuiltin of string * (value list -> value)
  | VUninitialized

and env = (string, value ref) Hashtbl.t list

let fail message = raise (Ast.Error message)

let rec string_of_value = function
  | VInt n -> string_of_int n
  | VFloat n ->
      let text = string_of_float n in
      if text.[String.length text - 1] = '.' then text ^ "0" else text
  | VBool true -> "#t"
  | VBool false -> "#f"
  | VString text ->
      let out = Buffer.create (String.length text + 2) in
      Buffer.add_char out '"';
      String.iter
        (function
          | '\\' -> Buffer.add_string out "\\\\"
          | '"' -> Buffer.add_string out "\\\""
          | '\n' -> Buffer.add_string out "\\n"
          | '\t' -> Buffer.add_string out "\\t"
          | ch -> Buffer.add_char out ch)
        text;
      Buffer.add_char out '"';
      Buffer.contents out
  | VSymbol name -> name
  | VList values ->
      "(" ^ String.concat " " (List.map string_of_value values) ^ ")"
  | VVector values ->
      "#(" ^ String.concat " "
        (Array.to_list (Array.map string_of_value values)) ^ ")"
  | VClosure _ -> "#<procedure>"
  | VBuiltin _ -> "#<procedure>"
  | VUninitialized -> fail "read of uninitialized letrec binding"

let make_frame () = Hashtbl.create 32

let define frame name value = Hashtbl.replace frame name (ref value)

let rec lookup frames name =
  match frames with
  | [] -> fail ("unbound variable: " ^ name)
  | frame :: rest ->
      (match Hashtbl.find_opt frame name with
       | Some cell ->
           (match !cell with
            | VUninitialized -> fail ("uninitialized variable: " ^ name)
            | value -> value)
       | None -> lookup rest name)

let child_env parent names values =
  if List.length names <> List.length values then
    fail (Printf.sprintf "arity mismatch: expected %d arguments, got %d"
      (List.length names) (List.length values));
  let frame = make_frame () in
  List.iter2 (define frame) names values;
  frame :: parent

let truthy = function VBool false -> false | _ -> true

let as_int who = function
  | VInt n -> n
  | value -> fail (who ^ ": expected integer, got " ^ string_of_value value)

let as_number who = function
  | VInt n -> `Int n
  | VFloat n -> `Float n
  | value -> fail (who ^ ": expected number, got " ^ string_of_value value)

let as_bool who = function
  | VBool value -> value
  | value -> fail (who ^ ": expected boolean, got " ^ string_of_value value)

let as_string who = function
  | VString value -> value
  | value -> fail (who ^ ": expected string, got " ^ string_of_value value)

let as_symbol who = function
  | VSymbol value -> value
  | value -> fail (who ^ ": expected symbol, got " ^ string_of_value value)

let as_list who = function
  | VList value -> value
  | value -> fail (who ^ ": expected list, got " ^ string_of_value value)

let as_vector who = function
  | VVector value -> value
  | value -> fail (who ^ ": expected vector, got " ^ string_of_value value)

let require_arity name expected args =
  let actual = List.length args in
  if actual <> expected then
    fail (Printf.sprintf "%s: expected %d arguments, got %d" name expected actual)

let require_min_arity name expected args =
  let actual = List.length args in
  if actual < expected then
    fail (Printf.sprintf "%s: expected at least %d arguments, got %d"
      name expected actual)

let rec quoted = function
  | Int n -> VInt n
  | Float n -> VFloat n
  | Bool value -> VBool value
  | String value -> VString value
  | Symbol value -> VSymbol value
  | List values -> VList (List.map quoted values)
  | Vector values -> VVector (Array.map quoted values)

let rec equal left right =
  match left, right with
  | VInt a, VInt b -> a = b
  | VFloat a, VFloat b -> a = b
  | VInt a, VFloat b -> float_of_int a = b
  | VFloat a, VInt b -> a = float_of_int b
  | VBool a, VBool b -> a = b
  | VString a, VString b -> a = b
  | VSymbol a, VSymbol b -> a = b
  | VList a, VList b ->
      List.length a = List.length b && List.for_all2 equal a b
  | VVector a, VVector b ->
      Array.length a = Array.length b &&
      let same = ref true in
      for i = 0 to Array.length a - 1 do
        if not (equal a.(i) b.(i)) then same := false
      done;
      !same
  | _ -> false

let number_list who args = List.map (as_number who) args

let add args =
  let step total number =
    match total, number with
    | `Int a, `Int b -> `Int (a + b)
    | `Int a, `Float b -> `Float (float_of_int a +. b)
    | `Float a, `Int b -> `Float (a +. float_of_int b)
    | `Float a, `Float b -> `Float (a +. b)
  in
  match List.fold_left step (`Int 0) (number_list "+" args) with
  | `Int n -> VInt n | `Float n -> VFloat n

let multiply args =
  let step total number =
    match total, number with
    | `Int a, `Int b -> `Int (a * b)
    | `Int a, `Float b -> `Float (float_of_int a *. b)
    | `Float a, `Int b -> `Float (a *. float_of_int b)
    | `Float a, `Float b -> `Float (a *. b)
  in
  match List.fold_left step (`Int 1) (number_list "*" args) with
  | `Int n -> VInt n | `Float n -> VFloat n

let subtract args =
  require_min_arity "-" 1 args;
  let numbers = number_list "-" args in
  let subtract_one left right =
    match left, right with
    | `Int a, `Int b -> `Int (a - b)
    | `Int a, `Float b -> `Float (float_of_int a -. b)
    | `Float a, `Int b -> `Float (a -. float_of_int b)
    | `Float a, `Float b -> `Float (a -. b)
  in
  let result =
    match numbers with
    | [`Int n] -> `Int (-n)
    | [`Float n] -> `Float (-.n)
    | first :: rest -> List.fold_left subtract_one first rest
    | [] -> assert false
  in
  match result with `Int n -> VInt n | `Float n -> VFloat n

let divide args =
  require_min_arity "/" 1 args;
  let as_float = function `Int n -> float_of_int n | `Float n -> n in
  let numbers = number_list "/" args in
  let result =
    match numbers with
    | [number] -> 1.0 /. as_float number
    | first :: rest ->
        List.fold_left (fun total n -> total /. as_float n)
          (as_float first) rest
    | [] -> assert false
  in
  VFloat result

let compare_numbers name compare args =
  require_min_arity name 2 args;
  let as_float = function `Int n -> float_of_int n | `Float n -> n in
  let rec adjacent = function
    | left :: (right :: _ as rest) ->
        compare (as_float left) (as_float right) && adjacent rest
    | _ -> true
  in
  VBool (adjacent (number_list name args))

let fixed name arity fn =
  name, VBuiltin (name, fun args -> require_arity name arity args; fn args)

let variadic name fn = name, VBuiltin (name, fn)

let rec apply procedure args =
  match procedure with
  | VClosure (params, body, closure_env) ->
      eval body (child_env closure_env params args)
  | VBuiltin (_, fn) -> fn args
  | value -> fail ("application: expected procedure, got " ^ string_of_value value)

and eval expression env =
  match expression with
  | Int n -> VInt n
  | Float n -> VFloat n
  | Bool value -> VBool value
  | String value -> VString value
  | Symbol name -> lookup env name
  | Vector _ -> fail "vector literals are not self-evaluating"
  | List [] -> fail "the empty list is not self-evaluating"
  | List (Symbol "quote" :: args) ->
      (match args with [datum] -> quoted datum | _ -> fail "quote: expected 1 argument")
  | List (Symbol "lambda" :: args) -> eval_lambda args env
  | List (Symbol "if" :: args) -> eval_if args env
  | List (Symbol "let" :: args) -> eval_let false args env
  | List (Symbol "letrec" :: args) -> eval_let true args env
  | List (Symbol "begin" :: args) -> eval_sequence args env
  | List (Symbol "and" :: args) -> eval_and args env
  | List (Symbol "or" :: args) -> eval_or args env
  | List (Symbol "cond" :: args) -> eval_cond args env
  | List (Symbol "define" :: _) -> fail "define: only valid at top level"
  | List (operator :: operands) ->
      let procedure = eval operator env in
      apply procedure (eval_list operands env)

and eval_list expressions env =
  match expressions with
  | [] -> []
  | expression :: rest -> eval expression env :: eval_list rest env

and eval_lambda args env =
  match args with
  | [List params; body] ->
      let names = List.map
        (function Symbol name -> name | _ -> fail "lambda: parameter is not a name")
        params
      in
      VClosure (names, body, env)
  | _ -> fail "lambda: expected (lambda (name ...) body)"

and eval_if args env =
  match args with
  | [test; yes; no] -> if truthy (eval test env) then eval yes env else eval no env
  | _ -> fail "if: expected (if test then else)"

and binding = function
  | List [Symbol name; expression] -> name, expression
  | _ -> fail "binding must have the form (name expression)"

and eval_let recursive args env =
  match args with
  | [List bindings; body] ->
      let specs = List.map binding bindings in
      if recursive then
        let frame = make_frame () in
        List.iter (fun (name, _) -> define frame name VUninitialized) specs;
        let extended = frame :: env in
        List.iter (fun (name, expression) ->
          let cell = Hashtbl.find frame name in
          cell := eval expression extended) specs;
        eval body extended
      else
        let names, expressions = List.split specs in
        let values = eval_list expressions env in
        eval body (child_env env names values)
  | _ -> fail "let: expected bindings and one body expression"

and eval_sequence expressions env =
  match expressions with
  | [] -> VBool false
  | [expression] -> eval expression env
  | expression :: rest -> ignore (eval expression env); eval_sequence rest env

and eval_and expressions env =
  match expressions with
  | [] -> VBool true
  | [expression] -> eval expression env
  | expression :: rest ->
      let value = eval expression env in
      if truthy value then eval_and rest env else value

and eval_or expressions env =
  match expressions with
  | [] -> VBool false
  | expression :: rest ->
      let value = eval expression env in
      if truthy value then value else eval_or rest env

and eval_cond clauses env =
  match clauses with
  | [] -> fail "cond: no clause matched"
  | List [Symbol "else"; body] :: _ -> eval body env
  | List [test; body] :: rest ->
      if truthy (eval test env) then eval body env else eval_cond rest env
  | _ -> fail "cond: malformed clause"

let builtin_bindings () =
  let predicate name test = fixed name 1 (function
    | [value] -> VBool (test value) | _ -> assert false)
  in
  [
    variadic "+" add;
    variadic "-" subtract;
    variadic "*" multiply;
    variadic "/" divide;
    variadic "=" (compare_numbers "=" ( = ));
    variadic "<" (compare_numbers "<" ( < ));
    variadic ">" (compare_numbers ">" ( > ));
    variadic "<=" (compare_numbers "<=" ( <= ));
    variadic ">=" (compare_numbers ">=" ( >= ));
    predicate "number?" (function VInt _ | VFloat _ -> true | _ -> false);
    predicate "integer?" (function VInt _ -> true | _ -> false);
    predicate "float?" (function VFloat _ -> true | _ -> false);
    predicate "boolean?" (function VBool _ -> true | _ -> false);
    predicate "string?" (function VString _ -> true | _ -> false);
    predicate "symbol?" (function VSymbol _ -> true | _ -> false);
    predicate "procedure?" (function VClosure _ | VBuiltin _ -> true | _ -> false);
    predicate "null?" (function VList [] -> true | _ -> false);
    predicate "pair?" (function VList (_ :: _) -> true | _ -> false);
    predicate "list?" (function VList _ -> true | _ -> false);
    predicate "vector?" (function VVector _ -> true | _ -> false);
    fixed "not" 1 (function [value] -> VBool (not (as_bool "not" value)) | _ -> assert false);
    fixed "eq?" 2 (function
      | [VSymbol a; VSymbol b] -> VBool (a = b)
      | [VBool a; VBool b] -> VBool (a = b)
      | [VList []; VList []] -> VBool true
      | [a; b] -> VBool (a == b)
      | _ -> assert false);
    fixed "equal?" 2 (function [a; b] -> VBool (equal a b) | _ -> assert false);
    fixed "cons" 2 (function
      | [head; tail] -> VList (head :: as_list "cons" tail) | _ -> assert false);
    fixed "car" 1 (function
      | [value] -> (match as_list "car" value with
          | head :: _ -> head | [] -> fail "car: empty list")
      | _ -> assert false);
    fixed "cdr" 1 (function
      | [value] -> (match as_list "cdr" value with
          | _ :: tail -> VList tail | [] -> fail "cdr: empty list")
      | _ -> assert false);
    variadic "list" (fun values -> VList values);
    fixed "length" 1 (function
      | [value] -> VInt (List.length (as_list "length" value)) | _ -> assert false);
    variadic "append" (fun values ->
      VList (List.concat (List.map (as_list "append") values)));
    fixed "list-ref" 2 (function
      | [values; index] ->
          let values = as_list "list-ref" values in
          let index = as_int "list-ref" index in
          if index < 0 || index >= List.length values then fail "list-ref: index out of bounds";
          List.nth values index
      | _ -> assert false);
    variadic "vector" (fun values -> VVector (Array.of_list values));
    fixed "vector-length" 1 (function
      | [value] -> VInt (Array.length (as_vector "vector-length" value)) | _ -> assert false);
    fixed "vector-ref" 2 (function
      | [values; index] ->
          let values = as_vector "vector-ref" values in
          let index = as_int "vector-ref" index in
          if index < 0 || index >= Array.length values then fail "vector-ref: index out of bounds";
          values.(index)
      | _ -> assert false);
    fixed "string-length" 1 (function
      | [value] -> VInt (String.length (as_string "string-length" value)) | _ -> assert false);
    variadic "string-append" (fun values ->
      VString (String.concat "" (List.map (as_string "string-append") values)));
    fixed "string-ref" 2 (function
      | [value; index] ->
          let value = as_string "string-ref" value in
          let index = as_int "string-ref" index in
          if index < 0 || index >= String.length value then fail "string-ref: index out of bounds";
          VString (String.make 1 value.[index])
      | _ -> assert false);
    fixed "string->symbol" 1 (function
      | [value] -> VSymbol (as_string "string->symbol" value) | _ -> assert false);
    fixed "symbol->string" 1 (function
      | [value] -> VString (as_symbol "symbol->string" value) | _ -> assert false);
    fixed "char-code" 1 (function
      | [value] ->
          let value = as_string "char-code" value in
          if String.length value <> 1 then fail "char-code: expected one-character string";
          VInt (Char.code value.[0])
      | _ -> assert false);
    fixed "code-char" 1 (function
      | [value] ->
          let value = as_int "code-char" value in
          if value < 0 || value > 127 then fail "code-char: expected integer in 0..127";
          VString (String.make 1 (Char.chr value))
      | _ -> assert false);
    fixed "apply" 2 (function
      | [procedure; args] -> apply procedure (as_list "apply" args) | _ -> assert false);
    fixed "display" 1 (function
      | [VString text] -> print_endline text; VBool false
      | [value] -> print_endline (string_of_value value); VBool false
      | _ -> assert false);
    fixed "error" 1 (function
      | [value] -> fail (as_string "error" value) | _ -> assert false);
  ]

let make_global_env argv =
  let frame = make_frame () in
  List.iter (fun (name, value) -> define frame name value) (builtin_bindings ());
  define frame "argv" (VVector (Array.of_list (List.map (fun s -> VString s) argv)));
  [frame]

let eval_define args env =
  match env, args with
  | frame :: _, [Symbol name; expression] ->
      let value = eval expression env in
      define frame name value;
      VSymbol name
  | frame :: _, [List (Symbol name :: params); body] ->
      let params = List.map
        (function Symbol param -> param | _ -> fail "define: parameter is not a name")
        params
      in
      define frame name (VClosure (params, body, env));
      VSymbol name
  | _ -> fail "define: malformed definition"

let rec eval_program forms env =
  match forms with
  | [] -> VBool false
  | [form] -> eval_toplevel form env
  | form :: rest -> ignore (eval_toplevel form env); eval_program rest env

and eval_toplevel form env =
  match form with
  | List (Symbol "define" :: args) -> eval_define args env
  | List (Symbol "begin" :: forms) -> eval_program forms env
  | expression -> eval expression env
