(** Reader entry points for MiniScheme source text.

    The implementation delegates tokenization and parsing to the OCaml lexer
    and Menhir parser in this directory. Reader errors are normalized to
    {!Value.Parse_error} so the CLI reports syntax failures the same way as
    other MiniScheme errors. *)

let parse_error lexbuf msg =
  let pos = lexbuf.Lexing.lex_curr_p in
  let column = pos.pos_cnum - pos.pos_bol + 1 in
  Value.Parse_error
    (Printf.sprintf "%s at line %d, column %d" msg pos.pos_lnum column)

open Value

let syntax_error msg = raise (Parse_error msg)

module StringSet = Set.Make (String)

let special = function
  | "quote" | "lambda" | "if" | "let" | "letrec" | "begin" | "and" | "or"
  | "cond" | "while" | "set!" | "define" ->
      true
  | _ -> false

let ensure_params who params =
  List.iter
    (function
      | Symbol _ -> ()
      | _ -> syntax_error (who ^ ": params must be symbols"))
    params

let rec validate_toplevel = function
  | List (Symbol "define" :: parts) -> validate_define parts
  | List (Symbol "begin" :: rest) ->
      if rest = [] then syntax_error "begin: expected at least one expression";
      List.iter validate_toplevel rest
  | expr -> validate_expr expr

and validate_expr = function
  | Bool _ | Int _ | Float _ | String _ | Symbol _ | Vector _ -> ()
  | Closure _ | Builtin _ -> ()
  | List [] -> ()
  | List (Symbol name :: _ as expr) when special name -> validate_special name expr
  | List exprs -> List.iter validate_expr exprs

and validate_special name expr =
  match (name, expr) with
  | "quote", [ _; _ ] -> ()
  | "quote", _ -> syntax_error "quote: expected 1 argument"
  | "lambda", [ _; List params; body ] ->
      ensure_params "lambda" params;
      validate_expr body
  | "lambda", _ -> syntax_error "lambda: expected (lambda (params) body)"
  | "if", [ _; test; thn; els ] ->
      validate_expr test;
      validate_expr thn;
      validate_expr els
  | "if", _ -> syntax_error "if: expected (if test then else)"
  | ("let" | "letrec"), [ _; List bindings; body ] ->
      List.iter (validate_binding name) bindings;
      validate_expr body
  | "let", _ -> syntax_error "let: expected (let ((x e) ...) body)"
  | "letrec", _ -> syntax_error "letrec: expected (letrec ((x e) ...) body)"
  | "begin", _ :: es when es <> [] -> List.iter validate_expr es
  | "begin", _ -> syntax_error "begin: expected at least one expression"
  | ("and" | "or"), _ :: es -> List.iter validate_expr es
  | "cond", _ :: clauses -> List.iter validate_cond_clause clauses
  | "while", [ _; test; body ] ->
      validate_expr test;
      validate_expr body
  | "while", _ -> syntax_error "while: expected (while test body)"
  | "set!", [ _; Symbol _; value_expr ] -> validate_expr value_expr
  | "set!", _ -> syntax_error "set!: expected (set! name expression)"
  | "define", _ -> syntax_error "define: only valid at top level"
  | _ -> ()

and validate_binding who = function
  | List [ Symbol _; expr ] -> validate_expr expr
  | _ -> syntax_error (who ^ ": bad binding")

and validate_cond_clause = function
  | List [ Symbol "else"; body ] -> validate_expr body
  | List [ test; body ] ->
      validate_expr test;
      validate_expr body
  | _ -> syntax_error "cond: bad clause"

and validate_define = function
  | [ Symbol _; expr ] -> validate_expr expr
  | [ List (Symbol _ :: params); body ] ->
      ensure_params "define" params;
      validate_expr body
  | _ -> syntax_error "define: bad syntax"

let rec collect_defines names = function
  | [] -> names
  | List (Symbol "define" :: [ Symbol name; _ ]) :: rest ->
      collect_defines (StringSet.add name names) rest
  | List (Symbol "define" :: [ List (Symbol name :: _); _ ]) :: rest ->
      collect_defines (StringSet.add name names) rest
  | List (Symbol "begin" :: body) :: rest ->
      collect_defines (collect_defines names body) rest
  | _ :: rest -> collect_defines names rest

let check_symbol scope name =
  if not (StringSet.mem name scope) then
    syntax_error ("unbound variable: " ^ name)

let extend_scope names scope =
  List.fold_left (fun acc name -> StringSet.add name acc) scope names

let symbol_names who params =
  List.map
    (function
      | Symbol name -> name
      | _ -> syntax_error (who ^ ": params must be symbols"))
    params

let binding_name who = function
  | List [ Symbol name; _ ] -> name
  | _ -> syntax_error (who ^ ": bad binding")

let binding_expr who = function
  | List [ Symbol _; expr ] -> expr
  | _ -> syntax_error (who ^ ": bad binding")

let rec check_closed_toplevel scope = function
  | List (Symbol "define" :: [ Symbol _; expr ]) -> check_closed_expr scope expr
  | List (Symbol "define" :: [ List (Symbol _ :: params); body ]) ->
      let scope = extend_scope (symbol_names "define" params) scope in
      check_closed_expr scope body
  | List (Symbol "begin" :: body) ->
      List.iter (check_closed_toplevel scope) body
  | expr -> check_closed_expr scope expr

and check_closed_expr scope = function
  | Bool _ | Int _ | Float _ | String _ | Vector _ -> ()
  | Closure _ | Builtin _ -> ()
  | Symbol name -> check_symbol scope name
  | List [] -> ()
  | List (Symbol name :: _ as expr) when special name ->
      check_closed_special scope name expr
  | List exprs -> List.iter (check_closed_expr scope) exprs

and check_closed_special scope name expr =
  match (name, expr) with
  | "quote", [ _; _ ] -> ()
  | "lambda", [ _; List params; body ] ->
      let scope = extend_scope (symbol_names "lambda" params) scope in
      check_closed_expr scope body
  | "if", [ _; test; thn; els ] ->
      check_closed_expr scope test;
      check_closed_expr scope thn;
      check_closed_expr scope els
  | "let", [ _; List bindings; body ] ->
      List.iter
        (fun binding -> check_closed_expr scope (binding_expr "let" binding))
        bindings;
      let scope = extend_scope (List.map (binding_name "let") bindings) scope in
      check_closed_expr scope body
  | "letrec", [ _; List bindings; body ] ->
      let scope =
        extend_scope (List.map (binding_name "letrec") bindings) scope
      in
      List.iter
        (fun binding -> check_closed_expr scope (binding_expr "letrec" binding))
        bindings;
      check_closed_expr scope body
  | "begin", _ :: es | "and", _ :: es | "or", _ :: es ->
      List.iter (check_closed_expr scope) es
  | "cond", _ :: clauses -> List.iter (check_closed_cond_clause scope) clauses
  | "while", [ _; test; body ] ->
      check_closed_expr scope test;
      check_closed_expr scope body
  | "set!", [ _; Symbol name; value_expr ] ->
      check_symbol scope name;
      check_closed_expr scope value_expr
  | "define", _ -> syntax_error "define: only valid at top level"
  | _ -> assert false

and check_closed_cond_clause scope = function
  | List [ Symbol "else"; body ] -> check_closed_expr scope body
  | List [ test; body ] ->
      check_closed_expr scope test;
      check_closed_expr scope body
  | _ -> syntax_error "cond: bad clause"

let validate_closed ~initial forms =
  let initial_scope =
    List.fold_left
      (fun scope name -> StringSet.add name scope)
      StringSet.empty initial
  in
  let scope = collect_defines initial_scope forms in
  List.iter (check_closed_toplevel scope) forms

let read_all (src : string) : Value.t list =
  let lexbuf = Lexing.from_string src in
  try
    let forms = Parser.program Lexer.token lexbuf in
    List.iter validate_toplevel forms;
    forms
  with Parser.Error -> raise (parse_error lexbuf "syntax error")
