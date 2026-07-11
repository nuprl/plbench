open Syntax

let annotation_type = Option.value ~default:Any

let rec syntax_leq left right =
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
  | Ann (left_expression, left_type), Ann (right_expression, right_type) ->
      Semantics.type_leq left_type right_type
      && syntax_leq left_expression right_expression
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


let%test_unit "an ill-typed incomparable annotation raises" =
  match
    check
      ~original:(parse "(fun f : int -> int . f 0) (fun x : int . x)")
      ~migrated:(parse "(fun f : int -> int . f 0) (fun x : bool . x)")
  with
  | _ -> failwith "expected a static error"
  | exception Semantics.Static_error _ -> ()


let%test "binder names are syntax" =
  not (check ~original:(parse "fun x . x") ~migrated:(parse "fun y . y"))


let%test "corresponding ascription types may become more precise" =
  check ~original:(parse "fun x . (x : any)")
    ~migrated:(parse "fun x : any . (x : int)")


let%test "ascriptions cannot be inserted" =
  not
    (check ~original:(parse "fun x . x")
       ~migrated:(parse "fun x : any . (x : any)"))


let%test "ascriptions cannot be removed" =
  not
    (check ~original:(parse "fun x . (x : any)")
       ~migrated:(parse "fun x : any . x"))


let%test_unit "ill-typed programs raise instead of returning false" =
  match check ~original:(parse "x") ~migrated:(parse "x") with
  | _ -> failwith "expected a static error"
  | exception Semantics.Static_error _ -> ()
