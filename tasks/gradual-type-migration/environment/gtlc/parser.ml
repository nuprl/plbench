exception Error of string

let parse source =
  let lexbuf = Lexing.from_string source in
  try Gtlc_parser.program Lexer.token lexbuf with
  | Lexer.Error message -> raise (Error message)
  | Gtlc_parser.Error ->
      raise
        (Error (Printf.sprintf "syntax error at byte %d" (Lexing.lexeme_start lexbuf)))


let parse_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> parse (really_input_string channel (in_channel_length channel)))
