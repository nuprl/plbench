type typ = Int | Bool | Any | Arr of typ * typ
type binary_operator = Add | Multiply

type expr =
  | Lit_int of int
  | Lit_bool of bool
  | Var of string
  | Fun of string * typ option * expr
  | App of expr * expr
  | Bin of binary_operator * expr * expr
  | If of expr * expr * expr
  | Let of string * expr * expr
  | Ann of expr * typ

let rec show_typ = function
  | Int -> "int"
  | Bool -> "bool"
  | Any -> "any"
  | Arr (domain, codomain) ->
      let domain =
        match domain with
        | Arr _ -> "(" ^ show_typ domain ^ ")"
        | _ -> show_typ domain
      in
      domain ^ " -> " ^ show_typ codomain

let show_annotation = function None -> "" | Some typ -> " : " ^ show_typ typ
let show_binary_operator = function Add -> "+" | Multiply -> "*"

let rec show_expr = function
  | Lit_int value -> string_of_int value
  | Lit_bool value -> string_of_bool value
  | Var name -> name
  | Fun (parameter, annotation, body) ->
      Printf.sprintf "(fun %s%s . %s)" parameter
        (show_annotation annotation)
        (show_expr body)
  | App (function_, argument) ->
      Printf.sprintf "(%s %s)" (show_expr function_) (show_expr argument)
  | Bin (operator, left, right) ->
      Printf.sprintf "(%s %s %s)" (show_expr left)
        (show_binary_operator operator)
        (show_expr right)
  | If (condition, yes, no) ->
      Printf.sprintf "(if %s then %s else %s)" (show_expr condition)
        (show_expr yes) (show_expr no)
  | Let (name, value, body) ->
      Printf.sprintf "(let %s = %s in %s)" name (show_expr value)
        (show_expr body)
  | Ann (expression, typ) ->
      Printf.sprintf "(%s : %s)" (show_expr expression) (show_typ typ)

let rec has_annotation = function
  | Lit_int _ | Lit_bool _ | Var _ -> false
  | Fun (_, Some _, _) | Ann _ -> true
  | Fun (_, None, body) -> has_annotation body
  | App (left, right) | Bin (_, left, right) | Let (_, left, right) ->
      has_annotation left || has_annotation right
  | If (condition, yes, no) ->
      has_annotation condition || has_annotation yes || has_annotation no
