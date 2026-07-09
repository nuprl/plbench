(** Reader entry points for MiniScheme source text.

    The implementation delegates tokenization and parsing to the OCaml lexer
    and Menhir parser in this directory. Reader errors are normalized to
    {!Value.Parse_error} so the CLI reports syntax failures the same way as
    other MiniScheme errors. *)

let parse_error lexbuf msg =
  let pos = lexbuf.Lexing.lex_curr_p in
  let column = pos.pos_cnum - pos.pos_bol + 1 in
  Value.Parse_error
    (Printf.sprintf "%s at line %d, column %d" msg pos.pos_lnum column)

let read_all (src : string) : Value.t list =
  let lexbuf = Lexing.from_string src in
  try Parser.program Lexer.token lexbuf with
  | Parser.Error -> raise (parse_error lexbuf "syntax error")
