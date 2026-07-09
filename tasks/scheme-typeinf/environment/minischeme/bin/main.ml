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

let read_file path =
  let ic = open_in path in
  let len = in_channel_length ic in
  let src = really_input_string ic len in
  close_in ic;
  Reader.read_all src

let run loads expr =
  if expr = None && loads = [] then (
    prerr_endline "error: expected -l FILE or -e EXPR";
    2)
  else
    try
      let load_forms = List.map read_file loads in
      let expr_forms =
        match expr with
        | None -> []
        | Some source -> Reader.read_all source
      in
      let forms = List.concat load_forms @ expr_forms in
      Reader.validate_closed ~initial:(Eval.builtin_names ()) forms;
      let env = Eval.make_global_env () in
      ignore (Eval.eval_toplevel forms env);
      0
    with exn -> report_error exn

let loads =
  let doc = "Load FILE before evaluating the main program." in
  Arg.(value & opt_all file [] & info [ "l"; "load" ] ~docv:"FILE" ~doc)

let expr =
  let doc = "Evaluate EXPR after any loaded files." in
  Arg.(value & opt (some string) None & info [ "e"; "eval" ] ~docv:"EXPR" ~doc)

let cmd =
  let doc = "run MiniScheme programs non-interactively" in
  let info = Cmd.info "minischeme" ~version:"0.1" ~doc in
  Cmd.v info Term.(const run $ loads $ expr)

let () = exit (Cmd.eval' cmd)
