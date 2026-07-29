type ty = TInt | TBool | TFun of ty * ty

type expr =
  | EInt of int
  | EBool of bool
  | EVar of string
  | EAdd of expr * expr
  | EIf of expr * expr * expr
  | ELam of string * ty * expr
  | EApp of expr * expr
  | ELet of string * expr * expr

type value =
  | VInt of int
  | VBool of bool
  | VClosure of string * ty * expr * environment

and environment = (string * value) list

type token = Left | Right | Colon | Atom of string

exception Error of string

let fail message = raise (Error message)

let delimiter = function
  | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ':' -> true
  | _ -> false

let lex source =
  let length = String.length source in
  let rec loop index output =
    if index = length then List.rev output
    else
      match source.[index] with
      | (' ' | '\t' | '\r' | '\n') -> loop (index + 1) output
      | '(' -> loop (index + 1) (Left :: output)
      | ')' -> loop (index + 1) (Right :: output)
      | ':' -> loop (index + 1) (Colon :: output)
      | _ ->
          let finish = ref index in
          while !finish < length && not (delimiter source.[!finish]) do
            incr finish
          done;
          let atom = String.sub source index (!finish - index) in
          loop !finish (Atom atom :: output)
  in
  loop 0 []

let rec parse_type = function
  | Atom "Int" :: rest -> TInt, rest
  | Atom "Bool" :: rest -> TBool, rest
  | Left :: Atom "->" :: rest ->
      let argument, rest = parse_type rest in
      let result, rest = parse_type rest in
      (match rest with
       | Right :: remaining -> TFun (argument, result), remaining
       | _ -> fail "function type is missing ')'")
  | _ -> fail "expected a type"

let rec parse_expr = function
  | [] -> fail "unexpected end of input"
  | Atom "true" :: rest -> EBool true, rest
  | Atom "false" :: rest -> EBool false, rest
  | Atom atom :: rest ->
      (match int_of_string_opt atom with
       | Some number -> EInt number, rest
       | None -> EVar atom, rest)
  | Left :: Atom "+" :: rest ->
      let left, rest = parse_expr rest in
      let right, rest = parse_expr rest in
      (match rest with
       | Right :: remaining -> EAdd (left, right), remaining
       | _ -> fail "+ expression is missing ')'")
  | Left :: Atom "if" :: rest ->
      let condition, rest = parse_expr rest in
      let yes, rest = parse_expr rest in
      let no, rest = parse_expr rest in
      (match rest with
       | Right :: remaining -> EIf (condition, yes, no), remaining
       | _ -> fail "if expression is missing ')'")
  | Left :: Atom "fun" :: Atom parameter :: Colon :: rest ->
      let parameter_type, rest = parse_type rest in
      let body, rest = parse_expr rest in
      (match rest with
       | Right :: remaining -> ELam (parameter, parameter_type, body), remaining
       | _ -> fail "fun expression is missing ')'")
  | Left :: Atom "let" :: Atom name :: rest ->
      let value, rest = parse_expr rest in
      let body, rest = parse_expr rest in
      (match rest with
       | Right :: remaining -> ELet (name, value, body), remaining
       | _ -> fail "let expression is missing ')'")
  | Left :: rest ->
      let fn, rest = parse_expr rest in
      let argument, rest = parse_expr rest in
      (match rest with
       | Right :: remaining -> EApp (fn, argument), remaining
       | _ -> fail "application is missing ')'")
  | Right :: _ -> fail "unexpected ')'"
  | Colon :: _ -> fail "unexpected ':'"

let parse source =
  match parse_expr (lex source) with
  | expression, [] -> expression
  | _ -> fail "extra input after expression"

let rec equal_ty left right =
  match left, right with
  | TInt, TInt | TBool, TBool -> true
  | TFun (left_argument, left_result), TFun (right_argument, right_result) ->
      equal_ty left_argument right_argument && equal_ty left_result right_result
  | _ -> false

let rec infer context = function
  | EInt _ -> TInt
  | EBool _ -> TBool
  | EVar name ->
      (match List.assoc_opt name context with
       | Some ty -> ty
       | None -> fail ("unbound variable: " ^ name))
  | EAdd (left, right) ->
      if equal_ty (infer context left) TInt && equal_ty (infer context right) TInt
      then TInt else fail "an operand of + is not Int"
  | EIf (condition, yes, no) ->
      if not (equal_ty (infer context condition) TBool) then
        fail "if condition is not Bool";
      let yes_type = infer context yes in
      let no_type = infer context no in
      if equal_ty yes_type no_type then yes_type
      else fail "if branches have different types"
  | ELam (parameter, parameter_type, body) ->
      TFun (parameter_type, infer ((parameter, parameter_type) :: context) body)
  | EApp (fn, argument) ->
      (match infer context fn with
       | TFun (expected, result) ->
           if equal_ty expected (infer context argument) then result
           else fail "function argument has the wrong type"
       | _ -> fail "application operator is not a function")
  | ELet (name, value, body) ->
      let value_type = infer context value in
      infer ((name, value_type) :: context) body

let rec eval fuel environment expression =
  if fuel = 0 then fail "fuel exhausted";
  let remaining = fuel - 1 in
  match expression with
  | EInt value -> VInt value
  | EBool value -> VBool value
  | EVar name ->
      (match List.assoc_opt name environment with
       | Some value -> value
       | None -> fail ("unbound runtime variable: " ^ name))
  | EAdd (left, right) ->
      (match eval remaining environment left, eval remaining environment right with
       | VInt left, VInt right -> VInt (left + right)
       | _ -> fail "impossible typed addition")
  | EIf (condition, yes, no) ->
      (match eval remaining environment condition with
       | VBool true -> eval remaining environment yes
       | VBool false -> eval remaining environment no
       | _ -> fail "impossible typed condition")
  | ELam (parameter, parameter_type, body) ->
      VClosure (parameter, parameter_type, body, environment)
  | EApp (fn, argument) ->
      let function_value = eval remaining environment fn in
      let argument_value = eval remaining environment argument in
      (match function_value with
       | VClosure (parameter, _, body, closure_environment) ->
           eval remaining ((parameter, argument_value) :: closure_environment) body
       | _ -> fail "impossible typed application")
  | ELet (name, value, body) ->
      let value = eval remaining environment value in
      eval remaining ((name, value) :: environment) body

let rec string_of_ty = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TFun (argument, result) ->
      "(-> " ^ string_of_ty argument ^ " " ^ string_of_ty result ^ ")"

let string_of_value = function
  | VInt value -> string_of_int value
  | VBool true -> "true"
  | VBool false -> "false"
  | VClosure _ -> "<function>"

let read_file path =
  let input = open_in_bin path in
  let length = in_channel_length input in
  let source = really_input_string input length in
  close_in input;
  source

let run () =
  try
    match Array.to_list Sys.argv with
    | [_; "--check"; path] ->
        print_endline (string_of_ty (infer [] (parse (read_file path))))
    | [_; path] ->
        let expression = parse (read_file path) in
        ignore (infer [] expression);
        print_endline (string_of_value (eval 1000 [] expression))
    | [_; path; fuel] ->
        let expression = parse (read_file path) in
        ignore (infer [] expression);
        print_endline (string_of_value (eval (int_of_string fuel) [] expression))
    | _ ->
        prerr_endline "usage: miniml [--check] PROGRAM [FUEL]";
        exit 2
  with
  | Error message -> prerr_endline message; exit 1
  | Sys_error message -> prerr_endline message; exit 1
  | Failure message -> prerr_endline message; exit 1

let () = run ()
