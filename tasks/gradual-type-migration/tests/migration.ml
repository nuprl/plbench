open Syntax

let parse ~description source =
  try Ok (Parser.parse source)
  with Parser.Error message -> Error (description ^ ": " ^ message)

let validate ~original ~migrated =
  if not (Semantics.structurally_equal original migrated) then
    Error "output changes program structure after annotations are erased"
  else if not (Semantics.all_lambdas_annotated migrated) then
    Error "not every lambda parameter is annotated"
  else
    try
      let original_type = Semantics.infer original in
      let migrated_type = Semantics.infer migrated in
      if Semantics.type_leq original_type migrated_type then Ok migrated_type
      else
        Error
          (Printf.sprintf "result type %s is not at least as precise as %s"
             (show_typ migrated_type) (show_typ original_type))
    with Semantics.Static_error message -> Error ("static error: " ^ message)

let rec peel_ascriptions types = function
  | Ann (expression, typ) -> peel_ascriptions (typ :: types) expression
  | expression -> (List.rev types, expression)

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
