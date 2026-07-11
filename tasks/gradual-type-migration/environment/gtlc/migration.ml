open Syntax

let annotation_type = Option.value ~default:Any

let ( let* ) = Option.bind

let rec type_distance less more =
  match (less, more) with
  | Any, Any -> Some 0
  | Any, (Int | Bool) -> Some 1
  | Any, Arr (domain, codomain) ->
      let* domain = type_distance Any domain in
      let* codomain = type_distance Any codomain in
      Some (1 + domain + codomain)
  | Int, Int | Bool, Bool -> Some 0
  | Arr (less_domain, less_codomain), Arr (more_domain, more_codomain) ->
      let* domain = type_distance less_domain more_domain in
      let* codomain = type_distance less_codomain more_codomain in
      Some (domain + codomain)
  | _ -> None

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

let rec syntax_distance less more =
  match (less, more) with
  | Lit_int less, Lit_int more when less = more -> Some 0
  | Lit_bool less, Lit_bool more when less = more -> Some 0
  | Var less, Var more when String.equal less more -> Some 0
  | Fun (less_name, less_type, less_body), Fun (more_name, more_type, more_body)
    when String.equal less_name more_name ->
      let* annotation =
        type_distance (annotation_type less_type) (annotation_type more_type)
      in
      let* body = syntax_distance less_body more_body in
      Some (annotation + body)
  | App (less_function, less_argument), App (more_function, more_argument) ->
      let* function_ = syntax_distance less_function more_function in
      let* argument = syntax_distance less_argument more_argument in
      Some (function_ + argument)
  | Bin (less_operator, less_left, less_right), Bin (more_operator, more_left, more_right)
    when less_operator = more_operator ->
      let* left = syntax_distance less_left more_left in
      let* right = syntax_distance less_right more_right in
      Some (left + right)
  | If (less_condition, less_yes, less_no), If (more_condition, more_yes, more_no) ->
      let* condition = syntax_distance less_condition more_condition in
      let* yes = syntax_distance less_yes more_yes in
      let* no = syntax_distance less_no more_no in
      Some (condition + yes + no)
  | Let (less_name, less_value, less_body), Let (more_name, more_value, more_body)
    when String.equal less_name more_name ->
      let* value = syntax_distance less_value more_value in
      let* body = syntax_distance less_body more_body in
      Some (value + body)
  | Ann (less_expression, less_type), Ann (more_expression, more_type) ->
      let* annotation = type_distance less_type more_type in
      let* expression = syntax_distance less_expression more_expression in
      Some (annotation + expression)
  | _ -> None

let distance ~less_precise ~more_precise =
  ignore (Semantics.infer less_precise);
  ignore (Semantics.infer more_precise);
  syntax_distance less_precise more_precise


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

let%test "function precision counts one structural and two component moves" =
  distance ~less_precise:(parse "fun f . f")
    ~more_precise:(parse "fun f : int -> int . f")
  = Some 3

let%test "case 04 candidate realizes three of five available moves" =
  let baseline =
    parse "(fun f . (fun y . f) (f 5)) (fun x . 10 + x)"
  in
  let candidate =
    parse "(fun f:any -> int. (fun y:int. f) (f 5)) (fun x:any. 10 + x)"
  in
  let expert =
    parse "(fun f:int -> int. (fun y:int. f) (f 5)) (fun x:int. 10 + x)"
  in
  distance ~less_precise:baseline ~more_precise:candidate = Some 3
  && distance ~less_precise:baseline ~more_precise:expert = Some 5

let%test "incomparable annotations have no precision distance" =
  distance ~less_precise:(parse "fun x : int . x")
    ~more_precise:(parse "fun x : bool . x")
  = None


let%test_unit "ill-typed programs raise instead of returning false" =
  match check ~original:(parse "x") ~migrated:(parse "x") with
  | _ -> failwith "expected a static error"
  | exception Semantics.Static_error _ -> ()
