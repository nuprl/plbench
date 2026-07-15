open Printf

type answer = Equivalent | Not_equivalent

type result_line = {
  name : string;
  answer : answer;
}

let cases_dir = "/tests/cases"
let checker = "/app/netkat-equivalence"
let reward_file = "/logs/verifier/reward.txt"

let finally cleanup f =
  match f () with
  | value -> cleanup (); value
  | exception exn -> cleanup (); raise exn

let read_file path =
  let channel = open_in_bin path in
  finally (fun () -> close_in_noerr channel) (fun () ->
      really_input_string channel (in_channel_length channel))

let write_file path contents =
  let channel = open_out path in
  finally (fun () -> close_out_noerr channel) (fun () -> output_string channel contents)

let nonempty_lines text =
  text
  |> String.split_on_char '\n'
  |> List.map String.trim
  |> List.filter (fun line -> line <> "")

let parse_result_line ~source line =
  match String.index_opt line ':' with
  | None -> Error (sprintf "%s: missing ':' in %S" source line)
  | Some colon ->
      let name = String.sub line 0 colon |> String.trim in
      let value =
        String.sub line (colon + 1) (String.length line - colon - 1)
        |> String.trim
      in
      if name = "" then Error (sprintf "%s: empty property name" source)
      else
        match value with
        | "equivalent" -> Ok { name; answer = Equivalent }
        | "not equivalent" -> Ok { name; answer = Not_equivalent }
        | _ -> Error (sprintf "%s: invalid result %S for %s" source value name)

let parse_results ~source text =
  let rec loop seen results = function
    | [] -> Ok (List.rev results)
    | line :: rest ->
        (match parse_result_line ~source line with
        | Error message -> Error message
        | Ok result when List.mem result.name seen ->
            Error (sprintf "%s: duplicate property %s" source result.name)
        | Ok result -> loop (result.name :: seen) (result :: results) rest)
  in
  loop [] [] (nonempty_lines text)

let contains text needle =
  try
    ignore (Str.search_forward (Str.regexp_string needle) text 0);
    true
  with Not_found -> false

let validate_documentation case_path source expected =
  List.iter
    (fun heading ->
      if not (contains source heading) then
        failwith (sprintf "%s is missing audit heading %S" case_path heading))
    [ "# Theme:"; "# Source:" ];
  List.iter
    (fun result ->
      let marker = "# Property " ^ result.name ^ ":" in
      if not (contains source marker) then
        failwith (sprintf "%s is missing documentation marker %S" case_path marker))
    expected

let run_checker case_path =
  let stdout_path = Filename.temp_file "netkat-eq-stdout-" ".txt" in
  let stderr_path = Filename.temp_file "netkat-eq-stderr-" ".txt" in
  finally
    (fun () ->
      Sys.remove stdout_path;
      Sys.remove stderr_path)
    (fun () ->
      let command =
        sprintf "ulimit -f 2048; timeout 30s %s %s > %s 2> %s"
          (Filename.quote checker) (Filename.quote case_path)
          (Filename.quote stdout_path) (Filename.quote stderr_path)
      in
      let status = Sys.command command in
      (status, read_file stdout_path, read_file stderr_path))

let answer_text = function
  | Equivalent -> "equivalent"
  | Not_equivalent -> "not equivalent"

let find_actual name actual =
  List.find_opt (fun result -> result.name = name) actual

let grade_case case_path expected_path =
  let source = read_file case_path in
  let expected =
    match parse_results ~source:expected_path (read_file expected_path) with
    | Ok [] -> failwith (sprintf "%s contains no expected properties" expected_path)
    | Ok results -> results
    | Error message -> failwith message
  in
  validate_documentation case_path source expected;
  let status, stdout, stderr = run_checker case_path in
  let parsed = parse_results ~source:"checker stdout" stdout in
  let actual_names =
    match parsed with Ok results -> List.map (fun r -> r.name) results | Error _ -> []
  in
  let expected_names = List.map (fun r -> r.name) expected in
  let unexpected = List.filter (fun name -> not (List.mem name expected_names)) actual_names in
  let structural_error =
    if status <> 0 then Some (sprintf "checker exited with status %d; stderr=%S" status stderr)
    else
      match parsed with
      | Error message -> Some message
      | Ok _ when unexpected <> [] ->
          Some (sprintf "unexpected properties: %s" (String.concat ", " unexpected))
      | Ok _ -> None
  in
  let actual = match parsed with Ok results -> results | Error _ -> [] in
  let passed = ref 0 in
  List.iter
    (fun wanted ->
      let ok =
        match structural_error, find_actual wanted.name actual with
        | None, Some got -> got.answer = wanted.answer
        | _ -> false
      in
      if ok then incr passed;
      let note =
        match structural_error with
        | Some message -> message
        | None ->
            (match find_actual wanted.name actual with
            | None -> "missing result"
            | Some got ->
                sprintf "expected %s, got %s"
                  (answer_text wanted.answer) (answer_text got.answer))
      in
      printf "%s/%s: %s%s\n%!"
        (Filename.basename case_path) wanted.name
        (if ok then "PASS" else "FAIL")
        (if ok then "" else " — " ^ note))
    expected;
  (!passed, List.length expected)

let discover_cases () =
  Sys.readdir cases_dir
  |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".nk")
  |> List.sort String.compare
  |> List.map (Filename.concat cases_dir)

let () =
  if not (Sys.file_exists checker) then begin
    eprintf "missing executable %s\n%!" checker;
    write_file reward_file "0.000000\n";
    exit 1
  end;
  let cases = discover_cases () in
  if cases = [] then begin
    eprintf "VERIFIER ERROR: no .nk cases under %s\n%!" cases_dir;
    exit 1
  end;
  try
    let passed, total =
      List.fold_left
        (fun (passed_acc, total_acc) case_path ->
          let expected_path = Filename.chop_suffix case_path ".nk" ^ ".expected" in
          if not (Sys.file_exists expected_path) then
            failwith (sprintf "missing expected file for %s" case_path);
          let passed, total = grade_case case_path expected_path in
          (passed_acc + passed, total_acc + total))
        (0, 0) cases
    in
    let score = float_of_int passed /. float_of_int total in
    printf "score=%.4f (%d/%d properties)\n%!" score passed total;
    write_file reward_file (sprintf "%.6f\n" score);
    exit (if passed = total then 0 else 1)
  with Failure message ->
    eprintf "VERIFIER ERROR: %s\n%!" message;
    exit 1
