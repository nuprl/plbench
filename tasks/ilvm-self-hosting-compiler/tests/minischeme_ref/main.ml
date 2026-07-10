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

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "usage: minischeme PROGRAM [ARG ...]";
    exit 2
  end;
  try
    let args =
      Array.to_list (Array.sub Sys.argv 2 (Array.length Sys.argv - 2))
    in
    let forms = parse (read_file Sys.argv.(1)) in
    ignore (Interp.eval_program forms (Interp.make_global_env args))
  with
  | Ast.Error message
  | Sys_error message ->
      prerr_endline ("error: " ^ message);
      exit 1
