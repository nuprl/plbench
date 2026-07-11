open Syntax

let annotation_type = Option.value ~default:Any

let rec peel_ascriptions types = function
  | Ann (expression, typ) -> peel_ascriptions (typ :: types) expression
  | expression -> (List.rev types, expression)


let rec types_leq left right =
  match (left, right) with
  | [], [] -> true
  | left_type :: left, right_type :: right ->
      Semantics.type_leq left_type right_type && types_leq left right
  | [], right_type :: right -> Semantics.type_leq Any right_type && types_leq [] right
  | left_type :: left, [] -> Semantics.type_leq left_type Any && types_leq left []


let rec syntax_leq left right =
  let left_types, left = peel_ascriptions [] left in
  let right_types, right = peel_ascriptions [] right in
  types_leq left_types right_types
  &&
  match (left, right) with
  | Lit_int left, Lit_int right -> left = right
  | Lit_bool left, Lit_bool right -> left = right
  | Var left, Var right -> String.equal left right
  | Fun (left_name, left_type, left_body), Fun (right_name, right_type, right_body) ->
      String.equal left_name right_name
      && Semantics.type_leq (annotation_type left_type) (annotation_type right_type)
      && syntax_leq left_body right_body
  | App (left_function, left_argument), App (right_function, right_argument) ->
      syntax_leq left_function right_function && syntax_leq left_argument right_argument
  | ( Bin (left_operator, left_left, left_right),
      Bin (right_operator, right_left, right_right) ) ->
      left_operator = right_operator
      && syntax_leq left_left right_left
      && syntax_leq left_right right_right
  | If (left_condition, left_yes, left_no), If (right_condition, right_yes, right_no) ->
      syntax_leq left_condition right_condition
      && syntax_leq left_yes right_yes && syntax_leq left_no right_no
  | Let (left_name, left_value, left_body), Let (right_name, right_value, right_body) ->
      String.equal left_name right_name
      && syntax_leq left_value right_value
      && syntax_leq left_body right_body
  | _ -> false


let check ~original ~migrated =
  ignore (Semantics.infer original);
  ignore (Semantics.infer migrated);
  syntax_leq original migrated


let parse source = Parser.parse source

let%test "a missing annotation denotes any" =
  check ~original:(parse "fun x . x") ~migrated:(parse "fun x : int . x")


let%test "precision is directional at every annotation" =
  not (check ~original:(parse "fun x : int . x") ~migrated:(parse "fun x : any . x"))


let%test "an interior annotation cannot change to an incomparable type" =
  not
    (check
       ~original:(parse "(fun f : int -> int . f 0) (fun x : int . x)")
       ~migrated:(parse "(fun f : int -> int . f 0) (fun x : bool . x)"))


let%test "binder names are syntax" =
  not (check ~original:(parse "fun x . x") ~migrated:(parse "fun y . y"))


let%test "expression ascriptions are pointwise type decorations" =
  check ~original:(parse "fun x . x") ~migrated:(parse "fun x : any . (x : int)")


let%test_unit "ill-typed programs raise instead of returning false" =
  match check ~original:(parse "x") ~migrated:(parse "x") with
  | _ -> failwith "expected a static error"
  | exception Semantics.Static_error _ -> ()
