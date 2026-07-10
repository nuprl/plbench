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
      raise (Ast.Error (Printf.sprintf "syntax error at line %d, column %d"
        pos.pos_lnum column))

let execute program args =
  try
    let forms = parse (read_file program) in
    ignore (Interp.eval_program forms (Interp.make_global_env args))
  with
  | Ast.Error message
  | Sys_error message ->
      prerr_endline ("error: " ^ message);
      exit 1

let () =
  let open Cmdliner in
  let program =
    Arg.(required & pos 0 (some file) None
         & info [] ~docv:"PROGRAM" ~doc:"MiniScheme source file to execute.")
  in
  let arguments =
    Arg.(value & pos_right 0 string []
         & info [] ~docv:"ARG" ~doc:"Program argument supplied through argv.")
  in
  let info = Cmd.info "minischeme" ~doc:"Execute a MiniScheme program" in
  exit (Cmd.eval (Cmd.v info Term.(const execute $ program $ arguments)))
