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

let run ~timeout_seconds ~executable ~input =
  let stdout_path = Filename.temp_file "migration-" ".out" in
  let stderr_path = Filename.temp_file "migration-" ".err" in
  Fun.protect
    ~finally:(fun () ->
      remove_file stdout_path;
      remove_file stderr_path)
    (fun () ->
      let command =
        Printf.sprintf "timeout %ds %s %s > %s 2> %s" timeout_seconds
          (Filename.quote executable)
          (Filename.quote input)
          (Filename.quote stdout_path)
          (Filename.quote stderr_path)
      in
      let status = Sys.command command in
      let stdout = read_file stdout_path in
      let stderr = read_file stderr_path in
      if status <> 0 then
        let diagnostic = if stderr = "" then stdout else stderr in
        Error
          (Printf.sprintf "migration exited %d: %s" status
             (abbreviated diagnostic))
      else if String.length stdout > output_limit then
        Error "migration output exceeds 1 MB"
      else Ok stdout)
