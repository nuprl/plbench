exception Error of string

let parse source =
  if String.length source > 1_000_000 then raise (Error "program is too large");
  let lexbuf = Lexing.from_string source in
  try Gtlc_parser.program Lexer.token lexbuf with
  | Lexer.Error message -> raise (Error message)
  | Gtlc_parser.Error ->
      raise
        (Error
           (Printf.sprintf "syntax error at byte %d"
              (Lexing.lexeme_start lexbuf)))
