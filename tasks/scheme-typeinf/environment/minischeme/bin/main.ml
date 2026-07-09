(** Non-interactive MiniScheme command-line interface. *)

open Cmdliner

let report_error = function
  | Value.Type_error msg
  | Value.Runtime_error msg
  | Value.Parse_error msg
  | Sys_error msg ->
      prerr_endline ("error: " ^ msg);
      1
  | exn ->
      prerr_endline ("error: " ^ Printexc.to_string exn);
      1

let run loads expr files =
  if expr = None && files = [] then (
    prerr_endline "error: expected -e EXPR or FILE";
    2)
  else
    try
      let env = Eval.make_global_env () in
      List.iter (fun path -> ignore (Eval.load_file path env)) loads;
      let result = ref None in
      List.iter
        (fun path -> result := Some (Eval.load_file path env))
        files;
      Option.iter
        (fun source ->
          result := Some (Eval.eval_toplevel (Reader.read_all source) env))
        expr;
      Option.iter (fun value -> print_endline (Value.to_string value)) !result;
      0
    with exn -> report_error exn

let loads =
  let doc = "Load FILE before evaluating the main program." in
  Arg.(value & opt_all file [] & info [ "l"; "load" ] ~docv:"FILE" ~doc)

let expr =
  let doc = "Evaluate EXPR after any loaded files and positional files." in
  Arg.(value & opt (some string) None & info [ "e"; "eval" ] ~docv:"EXPR" ~doc)

let files =
  let doc = "MiniScheme source file to evaluate." in
  Arg.(value & pos_all file [] & info [] ~docv:"FILE" ~doc)

let cmd =
  let doc = "run MiniScheme programs non-interactively" in
  let info = Cmd.info "minischeme" ~version:"0.1" ~doc in
  Cmd.v info Term.(const run $ loads $ expr $ files)

let () = exit (Cmd.eval' cmd)
