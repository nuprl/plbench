let () =
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--version" then begin
    print_endline "ILVM 0.2.3";
    exit 0
  end;
  try
    let config = Cli.parse Sys.argv in
    let source = Cli.read_file config.input in
    let result =
      Ilvm.run ~heap_size:config.heap_size
        ~register_count:config.register_count ~arguments:config.arguments source
    in
    Printf.printf "Normal termination. Result = %ld\n" result
  with
  | Error.Error (_, message) ->
      Printf.printf "An error occurred.\n%s\n" message;
      exit 1
  | Sys_error message ->
      Printf.printf "An error occurred.\n%s\n" message;
      exit 1
