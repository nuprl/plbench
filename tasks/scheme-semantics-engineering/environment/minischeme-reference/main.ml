let read_file path =
  let input = open_in_bin path in
  let length = in_channel_length input in
  let source = really_input_string input length in
  close_in input;
  source

let parse source =
  let lexbuf = Lexing.from_string source in
  try Parser.program Lexer.token lexbuf with
  | Parsing.Parse_error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      let column = pos.pos_cnum - pos.pos_bol + 1 in
    raise (Ast.Parse_error (Printf.sprintf "syntax error at line %d, column %d"
        pos.pos_lnum column))

let execute check_only program =
  try
    let forms = parse (read_file program) in
    let checked = Checker.check forms in
    if not check_only then
      ignore (Interp.eval_program (Checker.forms checked)
        (Interp.make_global_env (Checker.global_names checked)))
  with
  | Ast.Parse_error message ->
      prerr_endline ("parse error: " ^ message);
      exit 1
  | Ast.Static_error message ->
      prerr_endline ("static error: " ^ message);
      exit 1
  | Ast.Runtime_error message ->
      prerr_endline ("runtime error: " ^ message);
      exit 1
  | Sys_error message ->
      prerr_endline ("system error: " ^ message);
      exit 1

let () =
  let open Cmdliner in
  let program =
    Arg.(required & pos 0 (some file) None
         & info [] ~docv:"PROGRAM" ~doc:"MiniScheme source file to execute.")
  in
  let check_only =
    Arg.(value & flag
         & info ["check"] ~doc:"Check syntax and static semantics without executing.")
  in
  let info = Cmd.info "minischeme" ~doc:"Check or execute a MiniScheme program" in
  exit (Cmd.eval (Cmd.v info Term.(const execute $ check_only $ program)))
