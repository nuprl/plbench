(** Grader for compatible gradual type migrations.

    Each benchmark supplies an original program, an expert migration, and
    closing contexts with recorded outcomes. Before grading submissions, the
    verifier authenticates the reference GTLC executable and validates every
    fixture against both the original and expert programs. A candidate earns
    credit only when it is a syntactic migration and matches the original in
    every context. Its score is then determined by its number of [any]
    decorations relative to the expert migration. *)

module Paths = struct
  let migrator = "/app/migrate"
  let environment_gtlc = "/app/gtlc/_build/default/gtlc.exe"
  let cases = "/tests/cases.yaml"
  let reward = "/logs/verifier/reward.txt"
end

let expected_gtlc_md5 = "99e9a9ec4075280fd24e582bd77a89a8"
let migration_timeout_seconds = 15
let execution_timeout_seconds = 10

exception Hard_reward_zero of string
(** Raised when a migration tool emits a program that cannot stand alone as a
    well-formed, well-typed GTLC program. One such output invalidates the whole
    run rather than only its challenge. *)

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let remove_file path = try Sys.remove path with Sys_error _ -> ()

let with_source_file prefix source action =
  let path = Filename.temp_file prefix ".gtlc" in
  Fun.protect
    ~finally:(fun () -> remove_file path)
    (fun () ->
      write_file path source;
      action path)

let write_reward score = write_file Paths.reward (Printf.sprintf "%.6f\n" score)

let copy_file source destination =
  let input_channel = open_in_bin source in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input_channel)
    (fun () ->
      let output_channel = open_out_bin destination in
      Fun.protect
        ~finally:(fun () -> close_out_noerr output_channel)
        (fun () ->
          let buffer = Bytes.create 65_536 in
          let rec copy () =
            match input input_channel buffer 0 (Bytes.length buffer) with
            | 0 -> ()
            | count ->
                output output_channel buffer 0 count;
                copy ()
          in
          copy ()))

(** Copy the environment's GTLC executable out of the agent-controlled tree,
    authenticate it once, and make the private copy read-and-execute only. *)
let install_trusted_gtlc () =
  let path = Filename.temp_file "trusted-gtlc-" ".exe" in
  try
    copy_file Paths.environment_gtlc path;
    let actual = Digest.file path |> Digest.to_hex in
    if not (String.equal actual expected_gtlc_md5) then
      failwith
        (Printf.sprintf "trusted GTLC executable has MD5 %s; expected %s" actual
           expected_gtlc_md5);
    Unix.chmod path 0o500;
    path
  with exception_ ->
    remove_file path;
    raise exception_

let has_hole context =
  try
    ignore (Str.search_forward (Str.regexp_string "HOLE") context 0);
    true
  with Not_found -> false

let validate_fixture (case : Fixtures.case) =
  if case.contexts = [] then
    failwith (case.name ^ ": contexts must not be empty");
  List.iter
    (fun context ->
      if not (has_hole context.Fixtures.source) then
        failwith (case.name ^ ": context does not contain HOLE"))
    case.contexts

let fill_context context expression =
  Str.global_replace (Str.regexp_string "HOLE") ("(" ^ expression ^ ")") context

(** An observable result of running a closed GTLC program. Static failures are
    represented separately because they invalidate trusted fixtures, whereas a
    guarded cast failure is an ordinary dynamic outcome. *)
type outcome =
  | Value of string
  | Runtime_failure
  | Divergence
  | Static_failure of string

let show_outcome = function
  | Value value -> Printf.sprintf "value %S" value
  | Runtime_failure -> "runtime failure"
  | Divergence -> "divergence"
  | Static_failure message -> Printf.sprintf "static failure (%s)" message

let parse_expected_outcome = function
  | "runtime failure" -> Runtime_failure
  | "divergence" -> Divergence
  | value -> Value value

let contains ~substring text =
  try
    ignore (Str.search_forward (Str.regexp_string substring) text 0);
    true
  with Not_found -> false

let reports_static_failure stderr =
  contains ~substring:"static error:" stderr
  || contains ~substring:"parse error:" stderr

(** Run [source] with the trusted evaluator. Exceeding the execution deadline
    represents divergence; other dynamic failures represent failed casts. *)
let execute ~gtlc source =
  with_source_file "gtlc-exec-" source (fun path ->
      match
        Command.run ~timeout_seconds:execution_timeout_seconds ~executable:gtlc
          ~arguments:[ "exec"; path ]
      with
      | Error message -> failwith ("cannot invoke trusted GTLC: " ^ message)
      | Ok { status = 0; stdout; _ } -> Value (String.trim stdout)
      | Ok { status = 137 | 143; _ } -> Divergence
      | Ok { stderr; _ } when reports_static_failure stderr ->
          Static_failure (String.trim stderr)
      | Ok _ -> Runtime_failure)

let outcomes ~gtlc case expression =
  List.map
    (fun context ->
      execute ~gtlc (fill_context context.Fixtures.source expression))
    case.Fixtures.contexts

let expected_outcomes (case : Fixtures.case) =
  List.map
    (fun context -> parse_expected_outcome context.Fixtures.expected)
    case.contexts

(** Ask the trusted implementation for the benchmark precision metric. Only
    decorations whose complete type is [any] are counted. *)
let query_any_count ~gtlc source =
  with_source_file "gtlc-count-anys-" source (fun path ->
      match
        Command.run ~timeout_seconds:migration_timeout_seconds ~executable:gtlc
          ~arguments:[ "count-anys"; path ]
      with
      | Error message -> failwith ("cannot invoke trusted GTLC: " ^ message)
      | Ok { status = 0; stdout; _ } -> (
          match int_of_string_opt (String.trim stdout) with
          | Some count when count >= 0 -> Ok count
          | _ ->
              failwith (Printf.sprintf "trusted count-anys printed %S" stdout))
      | Ok output ->
          Error (Command.diagnostic output))

let count_anys ~gtlc source =
  match query_any_count ~gtlc source with
  | Ok count -> count
  | Error message -> failwith ("trusted count-anys failed: " ^ message)

let require_candidate_any_count ~gtlc case_name source =
  match query_any_count ~gtlc source with
  | Ok count -> count
  | Error message ->
      raise
        (Hard_reward_zero
           (Printf.sprintf "%s: migration does not type-check: %s" case_name
              message))

let run_migrator input_path =
  match
    Command.run ~timeout_seconds:migration_timeout_seconds
      ~executable:Paths.migrator ~arguments:[ input_path ]
  with
  | Error message -> Error ("cannot invoke migration tool: " ^ message)
  | Ok output when output.status <> 0 ->
      Error
        (Printf.sprintf "migration exited %d: %s" output.status
           (Command.diagnostic output))
  | Ok output -> Ok output.stdout

(** Check that both programs type-check and that [migrated] differs from
    [original] only through pointwise-more-precise corresponding types. *)
let check_migration ~gtlc original migrated =
  with_source_file "gtlc-original-" original (fun original_path ->
      with_source_file "gtlc-migrated-" migrated (fun migrated_path ->
          match
            Command.run ~timeout_seconds:migration_timeout_seconds
              ~executable:gtlc
              ~arguments:[ "is-migration"; original_path; migrated_path ]
          with
          | Error message -> failwith ("cannot invoke trusted GTLC: " ^ message)
          | Ok { status = 0; stdout; _ } -> (
              match String.trim stdout with
              | "true" -> Ok ()
              | "false" -> Error "output is not a syntactic migration"
              | output ->
                  failwith
                    (Printf.sprintf "trusted is-migration printed %S" output))
          | Ok output ->
              Error
                (Printf.sprintf "is-migration rejected output: %s"
                   (Command.diagnostic output))))

let first_difference expected actual =
  let rec search index expected actual =
    match (expected, actual) with
    | expected :: _, actual :: _ when expected <> actual ->
        Some (index, expected, actual)
    | _ :: expected, _ :: actual -> search (index + 1) expected actual
    | [], [] -> None
    | _ -> assert false
  in
  search 1 expected actual

type passing_grade = { oracle_anys : int; migrated_anys : int; score : float }
type fixture = { specification : Fixtures.case; expected : outcome list }

(** Validate trusted benchmark data before invoking the submitted migrator.
    The expert must be a valid migration, and both the original and expert must
    produce every outcome recorded in YAML. The observed original outcomes are
    retained as the candidate's behavioral baseline. *)
let prepare_fixture ~gtlc (case : Fixtures.case) =
  validate_fixture case;
  (match check_migration ~gtlc case.program case.oracle_migration with
  | Ok () -> ()
  | Error message ->
      failwith
        (Printf.sprintf "%s: best migration is invalid: %s" case.name message));
  let recorded = expected_outcomes case in
  let original = outcomes ~gtlc case case.program in
  (match first_difference recorded original with
  | None -> ()
  | Some (index, expected, actual) ->
      failwith
        (Printf.sprintf "%s: original program has %s in context %d; expected %s"
           case.name (show_outcome actual) index (show_outcome expected)));
  let oracle = outcomes ~gtlc case case.oracle_migration in
  (match first_difference recorded oracle with
  | None -> ()
  | Some (index, expected, actual) ->
      failwith
        (Printf.sprintf "%s: best migration has %s in context %d; expected %s"
           case.name (show_outcome actual) index (show_outcome expected)));
  { specification = case; expected = original }

(** Compute expert-relative precision credit. A candidate with fewer [any]
    decorations than the expert indicates a bad expert or insufficient contexts
    and therefore aborts verification instead of awarding unsound credit. *)
let precision_grade ~gtlc (case : Fixtures.case) migrated_anys =
  let oracle_anys = count_anys ~gtlc case.oracle_migration in
  if migrated_anys < oracle_anys then
    failwith
      (Printf.sprintf
         "%s: migration has %d anys, fewer than the oracle's %d; the oracle is \
          likely incorrect"
         case.name migrated_anys oracle_anys);
  let score =
    if migrated_anys = 0 then 1. else float oracle_anys /. float migrated_anys
  in
  { oracle_anys; migrated_anys; score }

(** Grade one challenge. An emitted program that fails its standalone static
    check raises [Hard_reward_zero]. Migration-tool failures with no output,
    invalid migrations, contextual static failures, and behavioral differences
    otherwise yield zero for this challenge. *)
let grade ~gtlc (fixture : fixture) =
  let case = fixture.specification in
  with_source_file
    ("gtlc-challenge-" ^ case.name ^ "-")
    case.program
    (fun input_path ->
      match run_migrator input_path with
      | Error _ as error -> error
      | Ok migrated -> (
          let migrated_anys =
            require_candidate_any_count ~gtlc case.name migrated
          in
          match check_migration ~gtlc case.program migrated with
          | Error _ as error -> error
          | Ok () -> (
              let actual = outcomes ~gtlc case migrated in
              match first_difference fixture.expected actual with
              | None -> Ok (precision_grade ~gtlc case migrated_anys)
              | Some (index, expected, actual) ->
                  Error
                    (Printf.sprintf "context %d changed outcome from %s to %s"
                       index (show_outcome expected) (show_outcome actual)))))

let grade_all ~gtlc fixtures =
  List.fold_left
    (fun total_score fixture ->
      match grade ~gtlc fixture with
      | Ok grade ->
          Printf.printf "%s: PASS — anys=%d/%d; score=%.4f\n%!"
            fixture.specification.name grade.oracle_anys grade.migrated_anys
            grade.score;
          total_score +. grade.score
      | Error message ->
          Printf.printf "%s: FAIL — %s\n%!" fixture.specification.name message;
          total_score)
    0. fixtures

(** Authenticate dependencies, validate all fixtures, grade every challenge,
    and write the mean per-challenge reward expected by Harbor. *)
let run () =
  try
    let gtlc = install_trusted_gtlc () in
    Fun.protect
      ~finally:(fun () -> remove_file gtlc)
      (fun () ->
        if not (Sys.file_exists Paths.migrator) then begin
          Printf.eprintf "missing executable %s\n%!" Paths.migrator;
          write_reward 0.;
          Error ()
        end
        else
          let cases = Fixtures.load Paths.cases in
          let fixtures = List.map (prepare_fixture ~gtlc) cases in
          let total_score = grade_all ~gtlc fixtures in
          let total = List.length fixtures in
          let score = if total = 0 then 0. else total_score /. float total in
          Printf.printf "score=%.4f\n%!" score;
          write_reward score;
          Ok ())
  with
  | Hard_reward_zero message ->
      Printf.eprintf "HARD ZERO: %s\n%!" message;
      write_reward 0.;
      Error ()
  | Failure message | Sys_error message ->
      Printf.eprintf "VERIFIER ERROR: %s\n%!" message;
    write_reward 0.;
    Error ()

let () = match run () with Ok () -> () | Error () -> exit 1
