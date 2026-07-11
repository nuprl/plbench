open Syntax

let parse ~description source =
  try Ok (Parser.parse source)
  with Parser.Error message -> Error (description ^ ": " ^ message)

let rec peel_ascriptions types = function
  | Ann (expression, typ) -> peel_ascriptions (typ :: types) expression
  | expression -> (List.rev types, expression)

let annotation_type = Option.value ~default:Any

let rec pointwise_types_leq left right =
  match (left, right) with
  | [], [] -> true
  | left_type :: left, right_type :: right ->
      Semantics.type_leq left_type right_type && pointwise_types_leq left right
  | [], right_type :: right ->
      Semantics.type_leq Any right_type && pointwise_types_leq [] right
  | left_type :: left, [] ->
      Semantics.type_leq left_type Any && pointwise_types_leq left []

let rec syntax_leq left right =
  let left_types, left = peel_ascriptions [] left in
  let right_types, right = peel_ascriptions [] right in
  pointwise_types_leq left_types right_types
  &&
  match (left, right) with
  | Lit_int left, Lit_int right -> left = right
  | Lit_bool left, Lit_bool right -> left = right
  | Var left, Var right -> String.equal left right
  | ( Fun (left_name, left_type, left_body),
      Fun (right_name, right_type, right_body) ) ->
      String.equal left_name right_name
      && Semantics.type_leq
           (annotation_type left_type)
           (annotation_type right_type)
      && syntax_leq left_body right_body
  | App (left_function, left_argument), App (right_function, right_argument) ->
      syntax_leq left_function right_function
      && syntax_leq left_argument right_argument
  | ( Bin (left_operator, left_left, left_right),
      Bin (right_operator, right_left, right_right) ) ->
      left_operator = right_operator
      && syntax_leq left_left right_left
      && syntax_leq left_right right_right
  | ( If (left_condition, left_yes, left_no),
      If (right_condition, right_yes, right_no) ) ->
      syntax_leq left_condition right_condition
      && syntax_leq left_yes right_yes
      && syntax_leq left_no right_no
  | ( Let (left_name, left_value, left_body),
      Let (right_name, right_value, right_body) ) ->
      String.equal left_name right_name
      && syntax_leq left_value right_value
      && syntax_leq left_body right_body
  | _ -> false

let validate ~original ~migrated =
  try
    ignore (Semantics.infer original);
    let migrated_type = Semantics.infer migrated in
    if not (syntax_leq original migrated) then
      Error "output is not a pointwise syntactic migration of the input"
    else if not (Semantics.all_lambdas_annotated migrated) then
      Error "not every lambda parameter is annotated"
    else Ok migrated_type
  with Semantics.Static_error message -> Error ("static error: " ^ message)

let types_below candidates maxima =
  List.length candidates <= List.length maxima
  && List.for_all2 Semantics.type_leq candidates
       (List.filteri (fun index _ -> index < List.length candidates) maxima)

let rec decorations_below candidate maximum =
  let candidate_ascriptions, candidate = peel_ascriptions [] candidate in
  let maximum_ascriptions, maximum = peel_ascriptions [] maximum in
  types_below candidate_ascriptions maximum_ascriptions
  &&
  match (candidate, maximum) with
  | Lit_int _, Lit_int _ | Lit_bool _, Lit_bool _ | Var _, Var _ -> true
  | Fun (_, candidate_type, candidate_body), Fun (_, maximum_type, maximum_body)
    ->
      Option.fold ~none:false
        ~some:(fun candidate_type ->
          Option.fold ~none:false
            ~some:(Semantics.type_leq candidate_type)
            maximum_type)
        candidate_type
      && decorations_below candidate_body maximum_body
  | ( App (candidate_function, candidate_argument),
      App (maximum_function, maximum_argument) )
  | ( Bin (_, candidate_function, candidate_argument),
      Bin (_, maximum_function, maximum_argument) )
  | ( Let (_, candidate_function, candidate_argument),
      Let (_, maximum_function, maximum_argument) ) ->
      decorations_below candidate_function maximum_function
      && decorations_below candidate_argument maximum_argument
  | ( If (candidate_condition, candidate_yes, candidate_no),
      If (maximum_condition, maximum_yes, maximum_no) ) ->
      decorations_below candidate_condition maximum_condition
      && decorations_below candidate_yes maximum_yes
      && decorations_below candidate_no maximum_no
  | _ -> false

let rec decoration_types expression =
  let ascriptions, expression = peel_ascriptions [] expression in
  let nested =
    match expression with
    | Lit_int _ | Lit_bool _ | Var _ -> []
    | Fun (_, annotation, body) ->
        Option.to_list annotation @ decoration_types body
    | App (function_, argument) | Bin (_, function_, argument) ->
        decoration_types function_ @ decoration_types argument
    | If (condition, yes, no) ->
        decoration_types condition @ decoration_types yes @ decoration_types no
    | Let (_, value, body) -> decoration_types value @ decoration_types body
    | Ann _ -> assert false
  in
  ascriptions @ nested

let rec information = function
  | Any -> 0
  | Int | Bool -> 1
  | Arr (domain, codomain) -> 1 + information domain + information codomain

let precision_below ~candidate ~maximum =
  let candidate_types = decoration_types candidate in
  let maximum_types = decoration_types maximum in
  if not (decorations_below candidate maximum) then None
  else
    Some
      ( List.fold_left
          (fun total typ -> total + information typ)
          0 candidate_types,
        List.fold_left
          (fun total typ -> total + information typ)
          0 maximum_types )
