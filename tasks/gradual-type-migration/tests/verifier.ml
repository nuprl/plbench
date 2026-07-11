module Paths = struct
  let migrator = "/app/migrate"
  let environment_gtlc = "/app/gtlc/_build/default/gtlc.exe"
  let cases = "/tests/cases.yaml"
  let reward = "/logs/verifier/reward.txt"
end

let expected_gtlc_md5 = "eeaca52811ad981325cf0e7114b29282"
let migration_timeout_seconds = 15
let execution_timeout_seconds = 2

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
      if not (has_hole context) then
        failwith (case.name ^ ": context does not contain HOLE"))
    case.contexts

let fill_context context expression =
  Str.global_replace (Str.regexp_string "HOLE") ("(" ^ expression ^ ")") context

type outcome = Value of string | Runtime_failure | Divergence

let show_outcome = function
  | Value value -> Printf.sprintf "value %S" value
  | Runtime_failure -> "runtime failure"
  | Divergence -> "divergence"

let execute ~gtlc source =
  with_source_file "gtlc-exec-" source (fun path ->
      match
        Command.run ~timeout_seconds:execution_timeout_seconds ~executable:gtlc
          ~arguments:[ "exec"; path ]
      with
      | Error message -> failwith ("cannot invoke trusted GTLC: " ^ message)
      | Ok { status = 0; stdout; _ } -> Value (String.trim stdout)
      | Ok { status = 124; _ } -> Divergence
      | Ok _ -> Runtime_failure)

let outcomes ~gtlc case expression =
  List.map
    (fun context -> execute ~gtlc (fill_context context expression))
    case.Fixtures.contexts

let count_anys ~gtlc source =
  with_source_file "gtlc-count-anys-" source (fun path ->
      match
        Command.run ~timeout_seconds:migration_timeout_seconds ~executable:gtlc
          ~arguments:[ "count-anys"; path ]
      with
      | Error message -> failwith ("cannot invoke trusted GTLC: " ^ message)
      | Ok { status = 0; stdout; _ } -> (
          match int_of_string_opt (String.trim stdout) with
          | Some count when count >= 0 -> count
          | _ ->
              failwith (Printf.sprintf "trusted count-anys printed %S" stdout))
      | Ok output ->
          failwith
            (Printf.sprintf "trusted count-anys failed: %s"
               (Command.diagnostic output)))

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

let precision_grade ~gtlc (case : Fixtures.case) migrated =
  let oracle_anys = count_anys ~gtlc case.oracle_migration in
  let migrated_anys = count_anys ~gtlc migrated in
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

let grade ~gtlc (case : Fixtures.case) =
  let expected = outcomes ~gtlc case case.program in
  with_source_file
    ("gtlc-challenge-" ^ case.name ^ "-")
    case.program
    (fun input_path ->
      match run_migrator input_path with
      | Error _ as error -> error
      | Ok migrated -> (
          match check_migration ~gtlc case.program migrated with
          | Error _ as error -> error
          | Ok () -> (
              let actual = outcomes ~gtlc case migrated in
              match first_difference expected actual with
              | None -> Ok (precision_grade ~gtlc case migrated)
              | Some (index, expected, actual) ->
                  Error
                    (Printf.sprintf "context %d changed outcome from %s to %s"
                       index (show_outcome expected) (show_outcome actual)))))

let grade_all ~gtlc cases =
  List.fold_left
    (fun total_score case ->
      match grade ~gtlc case with
      | Ok grade ->
          Printf.printf "%s: PASS — anys=%d/%d; score=%.4f\n%!"
            case.Fixtures.name grade.oracle_anys grade.migrated_anys grade.score;
          total_score +. grade.score
      | Error message ->
          Printf.printf "%s: FAIL — %s\n%!" case.Fixtures.name message;
          total_score)
    0. cases

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
          List.iter validate_fixture cases;
          let total_score = grade_all ~gtlc cases in
          let total = List.length cases in
          let score = if total = 0 then 0. else total_score /. float total in
          Printf.printf "score=%.4f\n%!" score;
          write_reward score;
          Ok ())
  with Failure message | Sys_error message ->
    Printf.eprintf "VERIFIER ERROR: %s\n%!" message;
    write_reward 0.;
    Error ()

let () = match run () with Ok () -> () | Error () -> exit 1
