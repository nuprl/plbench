open Syntax

exception Static_error of string
exception Runtime_error of string

type ir =
  | ILit_int of int
  | ILit_bool of bool
  | IVar of string
  | IFun of string * ir
  | IApp of ir * ir
  | IBin of binary_operator * ir * ir
  | IIf of ir * ir * ir
  | ILet of string * ir * ir
  | ICast of typ * typ * ir

let rec consistent left right =
  match (left, right) with
  | Any, _ | _, Any -> true
  | Arr (left_domain, left_codomain), Arr (right_domain, right_codomain) ->
      consistent left_domain right_domain && consistent left_codomain right_codomain
  | _ -> left = right


let rec type_leq less_precise more_precise =
  match (less_precise, more_precise) with
  | Any, _ -> true
  | Arr (left_domain, left_codomain), Arr (right_domain, right_codomain) ->
      type_leq left_domain right_domain && type_leq left_codomain right_codomain
  | _ -> less_precise = more_precise


let rec common_branch_type left right =
  match (left, right) with
  | _ when left = right -> left
  | Any, typ | typ, Any -> typ
  | Arr (left_domain, left_codomain), Arr (right_domain, right_codomain)
    when consistent left right ->
      Arr
        ( common_branch_type left_domain right_domain,
          common_branch_type left_codomain right_codomain )
  | _ -> Any


let cast_ir source target expression = ICast (source, target, expression)

let rec elaborate environment = function
  | Lit_int value -> (Int, ILit_int value)
  | Lit_bool value -> (Bool, ILit_bool value)
  | Var name -> elaborate_variable environment name
  | Fun (parameter, annotation, body) ->
      elaborate_function environment parameter annotation body
  | App (function_, argument) -> elaborate_application environment function_ argument
  | Bin (operator, left, right) -> elaborate_binary environment operator left right
  | If (condition, yes, no) -> elaborate_if environment condition yes no
  | Let (name, value, body) -> elaborate_let environment name value body
  | Ann (expression, target) ->
      let source, expression = elaborate environment expression in
      (target, cast_ir source target expression)


and elaborate_variable environment name =
  match List.assoc_opt name environment with
  | Some typ -> (typ, IVar name)
  | None -> raise (Static_error ("unbound identifier " ^ name))


and elaborate_function environment parameter annotation body =
  let domain = Option.value ~default:Any annotation in
  let codomain, body = elaborate ((parameter, domain) :: environment) body in
  (Arr (domain, codomain), IFun (parameter, body))


and elaborate_application environment function_ argument =
  let function_type, function_ = elaborate environment function_ in
  let argument_type, argument = elaborate environment argument in
  match function_type with
  | Arr (domain, codomain) ->
      (codomain, IApp (function_, cast_ir argument_type domain argument))
  | _ ->
      let dynamic_function = cast_ir function_type (Arr (Any, Any)) function_ in
      let dynamic_argument = cast_ir argument_type Any argument in
      (Any, IApp (dynamic_function, dynamic_argument))


and elaborate_binary environment operator left right =
  let left_type, left = elaborate environment left in
  let right_type, right = elaborate environment right in
  (Int, IBin (operator, cast_ir left_type Int left, cast_ir right_type Int right))


and elaborate_if environment condition yes no =
  let condition_type, condition = elaborate environment condition in
  let yes_type, yes = elaborate environment yes in
  let no_type, no = elaborate environment no in
  let result_type = common_branch_type yes_type no_type in
  ( result_type,
    IIf
      ( cast_ir condition_type Bool condition,
        cast_ir yes_type result_type yes,
        cast_ir no_type result_type no ) )


and elaborate_let environment name value body =
  let value_type, value = elaborate environment value in
  let body_type, body = elaborate ((name, value_type) :: environment) body in
  (body_type, ILet (name, value, body))


let infer expression = fst (elaborate [] expression)

let rec erase_ascriptions = function
  | Ann (expression, _) -> erase_ascriptions expression
  | expression -> expression


let binder_depth ~select_name binders name =
  let rec search depth = function
    | [] -> None
    | binder :: rest ->
        if select_name binder = name then Some depth else search (depth + 1) rest
  in
  search 0 binders


let variables_match binders left right =
  match
    ( binder_depth ~select_name:fst binders left,
      binder_depth ~select_name:snd binders right )
  with
  | None, None -> left = right
  | Some left, Some right -> left = right
  | _ -> false


let rec structurally_equal_with binders left right =
  match (erase_ascriptions left, erase_ascriptions right) with
  | Lit_int left, Lit_int right -> left = right
  | Lit_bool left, Lit_bool right -> left = right
  | Var left, Var right -> variables_match binders left right
  | Fun (left_name, _, left_body), Fun (right_name, _, right_body) ->
      structurally_equal_with ((left_name, right_name) :: binders) left_body right_body
  | App (left_function, left_argument), App (right_function, right_argument) ->
      structurally_equal_with binders left_function right_function
      && structurally_equal_with binders left_argument right_argument
  | ( Bin (left_operator, left_left, left_right),
      Bin (right_operator, right_left, right_right) ) ->
      left_operator = right_operator
      && structurally_equal_with binders left_left right_left
      && structurally_equal_with binders left_right right_right
  | If (left_condition, left_yes, left_no), If (right_condition, right_yes, right_no) ->
      structurally_equal_with binders left_condition right_condition
      && structurally_equal_with binders left_yes right_yes
      && structurally_equal_with binders left_no right_no
  | Let (left_name, left_value, left_body), Let (right_name, right_value, right_body) ->
      structurally_equal_with binders left_value right_value
      && structurally_equal_with
           ((left_name, right_name) :: binders)
           left_body right_body
  | _ -> false


let structurally_equal = structurally_equal_with []

let rec all_lambdas_annotated = function
  | Lit_int _ | Lit_bool _ | Var _ -> true
  | Fun (_, annotation, body) -> Option.is_some annotation && all_lambdas_annotated body
  | App (left, right) | Bin (_, left, right) | Let (_, left, right) ->
      all_lambdas_annotated left && all_lambdas_annotated right
  | If (condition, yes, no) ->
      all_lambdas_annotated condition
      && all_lambdas_annotated yes && all_lambdas_annotated no
  | Ann (expression, _) -> all_lambdas_annotated expression


type value =
  | VInt of int
  | VBool of bool
  | Closure of string * ir * value_environment
  | Proxy of value * typ * typ
  | Tagged of string * value

and value_environment = (string * value) list

type outcome = Function | Integer of int | Boolean of bool

let ground_tag = function
  | Arr _ -> "fun"
  | Int -> "int"
  | Bool -> "bool"
  | Any -> "any"


let rec cast source target value =
  if source = target then value
  else
    match (source, target) with
    | Any, target -> cast_from_any target value
    | source, Any -> cast_to_any source value
    | Arr _, Arr _ -> wrap_function source target value
    | _ -> cast Any target (cast source Any value)


and cast_from_any target = function
  | Tagged (tag, value) when tag = ground_tag target -> (
      match target with Arr _ -> cast (Arr (Any, Any)) target value | _ -> value)
  | _ -> raise (Runtime_error "guarded cast failed")


and cast_to_any source value =
  let value =
    match source with Arr _ -> cast source (Arr (Any, Any)) value | _ -> value
  in
  Tagged (ground_tag source, value)


and wrap_function source target = function
  | (Closure _ | Proxy _) as value -> Proxy (value, source, target)
  | _ -> raise (Runtime_error "guarded function cast received a non-function")


let rec evaluate environment = function
  | ILit_int value -> VInt value
  | ILit_bool value -> VBool value
  | IVar name -> List.assoc name environment
  | IFun (parameter, body) -> Closure (parameter, body, environment)
  | IApp (function_, argument) ->
      let function_ = evaluate environment function_ in
      let argument = evaluate environment argument in
      apply function_ argument
  | IBin (operator, left, right) ->
      evaluate_binary operator (evaluate environment left) (evaluate environment right)
  | IIf (condition, yes, no) -> (
      match evaluate environment condition with
      | VBool true -> evaluate environment yes
      | VBool false -> evaluate environment no
      | _ -> raise (Runtime_error "conditional guard is not a boolean"))
  | ILet (name, value, body) ->
      let value = evaluate environment value in
      evaluate ((name, value) :: environment) body
  | ICast (source, target, expression) ->
      cast source target (evaluate environment expression)


and evaluate_binary operator left right =
  match (left, right) with
  | VInt left, VInt right ->
      VInt (match operator with Add -> left + right | Multiply -> left * right)
  | _ -> raise (Runtime_error "arithmetic operand is not an integer")


and apply function_ argument =
  match function_ with
  | Closure (parameter, body, environment) ->
      evaluate ((parameter, argument) :: environment) body
  | Proxy
      ( function_,
        Arr (source_domain, source_codomain),
        Arr (target_domain, target_codomain) ) ->
      let argument = cast target_domain source_domain argument in
      let result = apply function_ argument in
      cast source_codomain target_codomain result
  | _ -> raise (Runtime_error "application operator is not a function")


let observe = function
  | VInt value | Tagged (_, VInt value) -> Integer value
  | VBool value | Tagged (_, VBool value) -> Boolean value
  | Closure _ | Proxy _ | Tagged (_, Closure _) | Tagged (_, Proxy _) -> Function
  | Tagged _ -> assert false


let run expression =
  let _, expression = elaborate [] expression in
  observe (evaluate [] expression)


let%test "an annotated identity application evaluates" =
  run (Parser.parse "let id = fun x : int . x in id 4") = Integer 4


let%test_unit "a static error is raised before evaluation" =
  match run (Parser.parse "missing") with
  | _ -> failwith "expected a static error"
  | exception Static_error _ -> ()


let%test_unit "a guarded cast can fail at runtime" =
  match run (Parser.parse "(true : int)") with
  | _ -> failwith "expected a runtime error"
  | exception Runtime_error _ -> ()
