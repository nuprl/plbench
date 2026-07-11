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
        match domain with Arr _ -> "(" ^ show_typ domain ^ ")" | _ -> show_typ domain
      in
      domain ^ " -> " ^ show_typ codomain


let show_annotation = function None -> "" | Some typ -> " : " ^ show_typ typ
let show_binary_operator = function Add -> "+" | Multiply -> "*"

let rec show_expr = function
  | Lit_int value -> string_of_int value
  | Lit_bool value -> string_of_bool value
  | Var name -> name
  | Fun (parameter, annotation, body) ->
      Printf.sprintf "(fun %s%s . %s)" parameter (show_annotation annotation)
        (show_expr body)
  | App (function_, argument) ->
      Printf.sprintf "(%s %s)" (show_expr function_) (show_expr argument)
  | Bin (operator, left, right) ->
      Printf.sprintf "(%s %s %s)" (show_expr left)
        (show_binary_operator operator)
        (show_expr right)
  | If (condition, yes, no) ->
      Printf.sprintf "(if %s then %s else %s)" (show_expr condition) (show_expr yes)
        (show_expr no)
  | Let (name, value, body) ->
      Printf.sprintf "(let %s = %s in %s)" name (show_expr value) (show_expr body)
  | Ann (expression, typ) ->
      Printf.sprintf "(%s : %s)" (show_expr expression) (show_typ typ)


let count_any_annotation = function Any -> 1 | Int | Bool | Arr _ -> 0

let rec count_anys = function
  | Lit_int _ | Lit_bool _ | Var _ -> 0
  | Fun (_, annotation, body) ->
      Option.fold ~none:1 ~some:count_any_annotation annotation + count_anys body
  | App (left, right) | Bin (_, left, right) | Let (_, left, right) ->
      count_anys left + count_anys right
  | If (condition, yes, no) -> count_anys condition + count_anys yes + count_anys no
  | Ann (expression, typ) -> count_anys expression + count_any_annotation typ


let%test "only a decoration whose whole type is any counts" =
  count_anys (Fun ("f", Some (Arr (Any, Arr (Int, Any))), Ann (Var "f", Any))) = 1


let%test "a missing annotation counts as implicit any" =
  count_anys (Fun ("x", None, Var "x")) = 1
