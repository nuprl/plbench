type output = { status : int; stdout : string; stderr : string }

let output_limit = 1_000_000
let diagnostic_limit = 500

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let remove_file path = try Sys.remove path with Sys_error _ -> ()

let abbreviated text =
  String.sub text 0 (min diagnostic_limit (String.length text))

let diagnostic output =
  abbreviated (if output.stderr = "" then output.stdout else output.stderr)

let run ~timeout_seconds ~executable ~arguments =
  let stdout_path = Filename.temp_file "gtlc-command-" ".out" in
  let stderr_path = Filename.temp_file "gtlc-command-" ".err" in
  Fun.protect
    ~finally:(fun () ->
      remove_file stdout_path;
      remove_file stderr_path)
    (fun () ->
      let words = List.map Filename.quote (executable :: arguments) in
      let command =
        Printf.sprintf "timeout --preserve-status %ds %s > %s 2> %s"
          timeout_seconds (String.concat " " words)
          (Filename.quote stdout_path)
          (Filename.quote stderr_path)
      in
      let status = Sys.command command in
      let stdout = read_file stdout_path in
      let stderr = read_file stderr_path in
      if
        String.length stdout > output_limit
        || String.length stderr > output_limit
      then Error "subprocess output exceeds 1 MB"
      else Ok { status; stdout; stderr })
