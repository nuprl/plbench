type benchmark = {
  name : string;
  program : string;
  context : string option; [@default None]
  maximal_migrations : string list;
}
[@@deriving yaml]

type benchmarks = benchmark list [@@deriving yaml]

let cases_path = "/tests/cases.yaml"

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let load_benchmarks () =
  let ( let* ) = Result.bind in
  let decoded =
    let* yaml = Yaml.of_string (read_file cases_path) in
    benchmarks_of_yaml yaml
  in
  match decoded with
  | Ok benchmarks -> benchmarks
  | Error (`Msg message) -> failwith ("invalid benchmark YAML: " ^ message)

let normalized source =
  String.concat " " (Str.split (Str.regexp "[ \\t\\r\\n]+") source)

let find_benchmark program =
  let expected = normalized program in
  load_benchmarks ()
  |> List.find_opt (fun benchmark -> normalized benchmark.program = expected)

let migrate path =
  match find_benchmark (read_file path) with
  | Some { maximal_migrations = migration :: _; _ } -> print_endline migration
  | Some _ -> failwith "benchmark has no maximal migration"
  | None -> failwith "input is not a reference benchmark"

let () =
  if Array.length Sys.argv <> 2 then begin
    Printf.eprintf "usage: %s FILE.gtlc\n" Sys.argv.(0);
    exit 2
  end;
  try migrate Sys.argv.(1)
  with Failure message ->
    Printf.eprintf "reference migration failed: %s\n" message;
    exit 1
