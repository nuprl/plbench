open Ast

module Names = Set.Make (String)

type program = {
  forms : Ast.t list;
  globals : Names.t;
}

let forms program = program.forms
let global_names program = Names.elements program.globals

let fail message = raise (Static_error message)

let builtin_names =
  Names.of_list
    [ "+"; "-"; "*"; "/"; "="; "<"; ">"; "<="; ">=";
      "number?"; "integer?"; "boolean?"; "string?"; "symbol?";
      "procedure?"; "null?"; "pair?"; "list?"; "vector?";
      "not"; "eq?"; "equal?"; "cons"; "car"; "cdr"; "list";
      "length"; "append"; "list-ref"; "vector"; "vector-length";
      "vector-ref"; "string-length"; "string-append"; "string-ref";
      "string->symbol"; "symbol->string"; "char-code"; "code-char";
      "apply"; "display"; "error" ]

let add_names scope names =
  List.fold_left (fun result name -> Names.add name result) scope names

let ensure_distinct context names =
  let rec loop seen = function
    | [] -> ()
    | name :: rest ->
        if Names.mem name seen then
          fail (context ^ ": duplicate binding: " ^ name);
        loop (Names.add name seen) rest
  in
  loop Names.empty names

let binder_names context = function
  | List parameters ->
      let names =
        List.map
          (function
            | Symbol name -> name
            | _ -> fail (context ^ ": binder is not a name"))
          parameters
      in
      ensure_distinct context names;
      names
  | _ -> fail (context ^ ": expected a list of names")

let bindings context = function
  | List raw_bindings ->
      let parsed =
        List.map
          (function
            | List [Symbol name; expression] -> name, expression
            | _ -> fail (context ^ ": binding must have the form (name expression)"))
          raw_bindings
      in
      ensure_distinct context (List.map fst parsed);
      parsed
  | _ -> fail (context ^ ": expected a binding list")

let rec check_expression scope = function
  | Int _ | Bool _ | String _ -> ()
  | Symbol name ->
      if not (Names.mem name scope) then fail ("unbound variable: " ^ name)
  | Vector _ -> fail "vector literals are not expressions"
  | List [] -> fail "the empty list is not an expression"
  | List (Symbol "quote" :: arguments) ->
      (match arguments with
       | [_] -> ()
       | _ -> fail "quote: expected 1 argument")
  | List (Symbol "lambda" :: arguments) ->
      (match arguments with
       | [parameters; body] ->
           let names = binder_names "lambda" parameters in
           check_expression (add_names scope names) body
       | _ -> fail "lambda: expected (lambda (name ...) body)")
  | List (Symbol "if" :: arguments) ->
      (match arguments with
       | [test; yes; no] ->
           check_expression scope test;
           check_expression scope yes;
           check_expression scope no
       | _ -> fail "if: expected (if test then else)")
  | List (Symbol "let" :: arguments) -> check_let false scope arguments
  | List (Symbol "letrec" :: arguments) -> check_let true scope arguments
  | List (Symbol "begin" :: expressions)
  | List (Symbol "and" :: expressions)
  | List (Symbol "or" :: expressions) ->
      List.iter (check_expression scope) expressions
  | List (Symbol "cond" :: clauses) -> check_cond scope clauses
  | List (Symbol "define" :: _) -> fail "define: only valid at top level"
  | List (operator :: operands) ->
      check_expression scope operator;
      List.iter (check_expression scope) operands

and check_let recursive scope = function
  | [raw_bindings; body] ->
      let parsed = bindings (if recursive then "letrec" else "let") raw_bindings in
      let names = List.map fst parsed in
      let body_scope = add_names scope names in
      let initializer_scope = if recursive then body_scope else scope in
      List.iter
        (fun (_, expression) -> check_expression initializer_scope expression)
        parsed;
      check_expression body_scope body
  | _ ->
      fail
        (if recursive then "letrec: expected bindings and one body expression"
         else "let: expected bindings and one body expression")

and check_cond scope = function
  | [] -> ()
  | [List [Symbol "else"; body]] -> check_expression scope body
  | List [Symbol "else"; _] :: _ -> fail "cond: else clause must be last"
  | List [test; body] :: rest ->
      check_expression scope test;
      check_expression scope body;
      check_cond scope rest
  | _ -> fail "cond: malformed clause"

let rec collect_globals globals = function
  | [] -> globals
  | List [Symbol "define"; Symbol name; _] :: rest ->
      collect_globals (Names.add name globals) rest
  | List [Symbol "define"; List (Symbol name :: _); _] :: rest ->
      collect_globals (Names.add name globals) rest
  | List (Symbol "begin" :: forms) :: rest ->
      collect_globals (collect_globals globals forms) rest
  | _ :: rest -> collect_globals globals rest

let rec check_top_level scope = function
  | List [Symbol "define"; Symbol _; expression] ->
      check_expression scope expression
  | List [Symbol "define"; List (Symbol _ :: parameters); body] ->
      let names = binder_names "define" (List parameters) in
      check_expression (add_names scope names) body
  | List (Symbol "define" :: _) -> fail "define: malformed definition"
  | List (Symbol "begin" :: forms) -> List.iter (check_top_level scope) forms
  | expression -> check_expression scope expression

let check forms =
  let globals = collect_globals Names.empty forms in
  let scope = Names.union builtin_names globals in
  List.iter (check_top_level scope) forms;
  { forms; globals }
