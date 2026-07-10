let run ?(arguments = []) ?(emit = fun _ -> ()) source =
  Ilvm.run ~heap_size:500 ~register_count:10 ~arguments ~emit source

let result_is expected source = run source = expected

let result_with_args_is expected arguments source =
  run ~arguments source = expected

let errors source =
  match run source with
  | _ -> false
  | exception Error.Error _ -> true

let%test "trailing whitespace" =
  result_is 200l "block 0 { exit(200); }   \n"

let%test "trailing garbage" =
  errors "block 0 { exit(200); } xxx"

let%test "exit" =
  result_is 200l "block 0 { exit(200); }"

let%test "register copy" =
  result_is 200l "block 0 { r0 = 200; r2 = r0; exit(r2); }"

let%test "addition" =
  result_is 211l
    "block 0 { r0 = 200; r1 = 11; r3 = r0 + r1; exit(r3); }"

let%test "load and store" =
  result_is 42l
    "block 0 { r0 = 200; *r0 = 42; r1 = *r0; exit(r1); }"

let%test "direct goto" =
  result_is 201l
    "block 0 { r2 = 200; goto(10); } block 10 { r2 = r2 + 1; exit(r2); }"

let%test "indirect goto" =
  result_is 210l
    "block 0 { r2 = 200; r3 = 10; goto(r3); } block 10 { r2 = r2 + r3; exit(r2); }"

let%test "ifz" =
  result_is 30l
    "block 0 { r2 = 1; ifz r2 { exit(20); } else { exit(30); } }"

let%test "factorial" =
  result_is 120l
    "block 0 { r2 = 1; r1 = 5; goto(1); } block 1 { ifz r1 { exit(r2); } else { r2 = r2 * r1; r1 = r1 - 1; goto(1); } }"

let%test "malloc" =
  result_is 2l "block 0 { r1 = malloc(10); exit(r1); }"

let%test "no-argument heap layout" =
  result_is 2l "block 0 { r1 = *1; r2 = r0 + r1; exit(r2); }"

let%test "argument heap layout" =
  result_with_args_is 1751711752l ["hi"]
    "block 0 { r1 = *1; r2 = *2; r3 = *r2; r6 = r1 + r2; r6 = r6 + r3; r6 = r6 + r0; exit(r6); }"

let%test "malloc follows arguments" =
  result_with_args_is 7l ["abc"; "defg"]
    "block 0 { r1 = malloc(1); exit(r1); }"

let%test "print_str" =
  let output = ref [] in
  let result =
    run ~arguments:["hello"] ~emit:(fun line -> output := line :: !output)
      "block 0 { r1 = *2; print_str(r1); exit(0); }"
  in
  result = 0l && List.rev !output = ["hello"]

let%test "print variants" =
  let output = ref [] in
  let result =
    run ~emit:(fun line -> output := line :: !output)
      "block 0 { print(42); print(\"hello123\"); print(array(10, 3)); exit(0); }"
  in
  result = 0l
  && List.rev !output = ["42"; "hello123"; "[10; 11; 12; ]"]

let%test "bitwise operations" =
  result_is 38l
    "block 0 { r0 = 12 & 10; r1 = 12 | 10; r2 = r0 ^ r1; r3 = ~ r2; r4 = -8 >> 1; r5 = -8 >>> 1; r6 = 3 << 4; r7 = r3 + r4; r7 = r7 + r6; r8 = r5 == 2147483644; r7 = r7 + r8; exit(r7); }"

let%test "negative immediates" =
  result_is (-7l) "block 0 { r0 = -7; exit(r0); }"

let%test "negative arithmetic" =
  result_is (-12l) "block 0 { r0 = -7; r1 = r0 - 5; exit(r1); }"

let%test "memsize" =
  result_is 500l "block 0 { r0 = memsize; exit(r0); }"

let%test "line comments" =
  result_is 10l "block 0 { r0 = 10; // comment\n exit(r0); }"

let%test "malloc OOM" =
  match
    Ilvm.run ~heap_size:20 ~register_count:10
      "block 0 { r1 = malloc(1); *r1 = 1234; goto(0); }"
  with
  | _ -> false
  | exception Error.Error (Error.Runtime, "malloc OOM") -> true
  | exception Error.Error _ -> false

let%test "duplicate blocks" =
  errors "block 0 { exit(0); } block 0 { exit(1); }"

let%test "missing block zero" =
  errors "block 1 { exit(0); }"

let%test "division by zero" =
  errors "block 0 { r1 = 1 / 0; exit(r1); }"

let%test "large straight-line block" =
  let out = Buffer.create 1_000_000 in
  Buffer.add_string out "block 0 { ";
  for _ = 1 to 100_000 do Buffer.add_string out "r1 = r1 + 1; " done;
  Buffer.add_string out "exit(r1); }";
  result_is 100_000l (Buffer.contents out)

let%test "CLI literal and file arguments" =
  let path = Filename.temp_file "ilvm-argument" ".txt" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      let channel = open_out_bin path in
      output_string channel "file contents";
      close_out channel;
      let config = Cli.parse
        [| "ilvm"; "-m"; "500"; "-r"; "10"; "program.ilvm";
           "-l"; "arg1"; "-f"; path; "-l"; "arg2" |]
      in
      config.heap_size = 500
      && config.register_count = 10
      && config.input = "program.ilvm"
      && config.arguments = ["arg1"; "file contents"; "arg2"])

let%test "CLI rejects unknown argument marker" =
  match Cli.parse [| "ilvm"; "program.ilvm"; "-x"; "arg" |] with
  | _ -> false
  | exception Error.Error (Error.Usage, message) ->
      String.length message > 0
  | exception Error.Error _ -> false

let%test "CLI rejects missing argument value" =
  match Cli.parse [| "ilvm"; "program.ilvm"; "-l" |] with
  | _ -> false
  | exception Error.Error (Error.Usage, message) ->
      String.length message > 0
  | exception Error.Error _ -> false
