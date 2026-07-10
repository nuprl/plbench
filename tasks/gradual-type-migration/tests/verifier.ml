open Syntax

module Paths = struct
  let migrator = "/app/migrate"
  let cases = "/tests/cases.yaml"
  let reward = "/logs/verifier/reward.txt"
end

let ( let* ) = Result.bind

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let write_reward score = write_file Paths.reward (Printf.sprintf "%.6f\n" score)

type fixture = {
  specification : Fixtures.case;
  input_path : string;
  original : expr;
  maxima : expr list;
  precision_possible : int;
}

let fixture_failure (case : Fixtures.case) message =
  failwith (Printf.sprintf "%s: %s" case.name message)

let require case = function
  | Ok value -> value
  | Error message -> fixture_failure case message

let parse case ~description source =
  require case (Migration.parse ~description source)

let fill_context context expression =
  Str.global_replace (Str.regexp_string "HOLE")
    ("(" ^ Syntax.show_expr expression ^ ")")
    context

let observe_in_context case context expression =
  fill_context context expression
  |> parse case ~description:"witness context does not parse"
  |> Semantics.run

let check_compatible_witness case ~original maximum =
  let original_outcome = Semantics.run original in
  let maximum_outcome = Semantics.run maximum in
  if original_outcome <> maximum_outcome then
    fixture_failure case "a maximum changes the empty-context outcome";
  match case.Fixtures.context with
  | None -> ()
  | Some context ->
      if
        observe_in_context case context original
        <> observe_in_context case context maximum
      then fixture_failure case "a maximum changes the witness-context outcome"

let prepare_maximum case original source =
  let maximum = parse case ~description:"maximum does not parse" source in
  ignore (require case (Migration.validate ~original ~migrated:maximum));
  check_compatible_witness case ~original maximum;
  maximum

let prepare_fixture (case : Fixtures.case) =
  let original = parse case ~description:"input does not parse" case.program in
  if Syntax.has_annotation original then
    fixture_failure case "input contains an annotation";
  let maxima =
    List.map (prepare_maximum case original) case.maximal_migrations
  in
  let precision_possible =
    maxima
    |> List.filter_map (fun maximum ->
        Migration.precision_below ~candidate:maximum ~maximum)
    |> List.fold_left (fun best (_, possible) -> max best possible) 0
  in
  let input_path = Filename.temp_file ("gtlc-" ^ case.name ^ "-") ".gtlc" in
  write_file input_path case.program;
  { specification = case; input_path; original; maxima; precision_possible }

type passing_grade = {
  result_type : typ;
  precision_earned : int;
  precision_possible : int;
}

let better_precision left right =
  let left_earned, left_possible = left in
  let right_earned, right_possible = right in
  match (left_possible, right_possible) with
  | 0, 0 -> 0
  | 0, _ -> 1
  | _, 0 -> -1
  | _ ->
      Int.compare (left_earned * right_possible) (right_earned * left_possible)

let best_compatible_maximum candidate maxima =
  let compatible =
    maxima
    |> List.filter_map (fun maximum ->
        Migration.precision_below ~candidate ~maximum)
    |> List.sort better_precision |> List.rev
  in
  match compatible with best :: _ -> Some best | [] -> None

let grade fixture =
  let* output =
    Command.run ~timeout_seconds:15 ~executable:Paths.migrator
      ~input:fixture.input_path
  in
  let* migrated = Migration.parse ~description:"output parse error" output in
  let* result_type = Migration.validate ~original:fixture.original ~migrated in
  match best_compatible_maximum migrated fixture.maxima with
  | None -> Error "annotations are more precise than every compatible maximum"
  | Some (precision_earned, precision_possible) ->
      Ok { result_type; precision_earned; precision_possible }

type totals = { passed : int; precision_earned : int; precision_possible : int }

let empty_totals = { passed = 0; precision_earned = 0; precision_possible = 0 }

let ratio numerator denominator =
  if denominator = 0 then 1. else float numerator /. float denominator

let report_result (totals : totals) (fixture : fixture) result =
  match result with
  | Error message ->
      Printf.printf "%s: FAIL — %s\n%!" fixture.specification.name message;
      {
        totals with
        precision_possible =
          totals.precision_possible + fixture.precision_possible;
      }
  | Ok grade ->
      Printf.printf "%s: PASS — type=%s; precision=%d/%d (%.3f)\n%!"
        fixture.specification.name
        (show_typ grade.result_type)
        grade.precision_earned grade.precision_possible
        (ratio grade.precision_earned grade.precision_possible);
      {
        passed = totals.passed + 1;
        precision_earned = totals.precision_earned + grade.precision_earned;
        precision_possible =
          totals.precision_possible + grade.precision_possible;
      }

let report_summary ~fixture_count totals =
  let safety = ratio totals.passed fixture_count in
  let precision = ratio totals.precision_earned totals.precision_possible in
  let score = (0.5 *. safety) +. (0.5 *. precision) in
  Printf.printf "mean_score=%.4f (safety=%d/%d=%.4f; precision=%d/%d=%.4f)\n%!"
    score totals.passed fixture_count safety totals.precision_earned
    totals.precision_possible precision;
  write_reward score

let grade_all fixtures =
  List.fold_left
    (fun totals fixture -> report_result totals fixture (grade fixture))
    empty_totals fixtures

let run () =
  if not (Sys.file_exists Paths.migrator) then begin
    Printf.eprintf "missing executable %s\n%!" Paths.migrator;
    write_reward 0.;
    Error ()
  end
  else
    try
      let cases = Fixtures.load Paths.cases in
      let fixtures = List.map prepare_fixture cases in
      report_summary ~fixture_count:(List.length fixtures) (grade_all fixtures);
      Ok ()
    with Failure message ->
      Printf.eprintf "VERIFIER ERROR: %s\n%!" message;
      Error ()

let () = match run () with Ok () -> () | Error () -> exit 1
