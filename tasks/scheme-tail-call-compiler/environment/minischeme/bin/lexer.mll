{
open Parser

let parse_error lexbuf msg =
  let pos = lexbuf.Lexing.lex_curr_p in
  let column = pos.pos_cnum - pos.pos_bol + 1 in
  raise
    (Value.Parse_error
       (Printf.sprintf "%s at line %d, column %d" msg pos.pos_lnum column))
}

let atom_initial =
  ['a'-'z' 'A'-'Z' '0'-'9' '!' '$' '%' '&' '*' '+' '-' '.' '/' ':' '<' '='
   '>' '?' '@' '^' '_' '~' '#']

let atom_subsequent = atom_initial

rule token = parse
  | [' ' '\t' '\r'] { token lexbuf }
  | '\n' { Lexing.new_line lexbuf; token lexbuf }
  | ';' [^ '\n']* { token lexbuf }
  | "#(" { VECTOR_START }
  | '(' { LPAREN }
  | ')' { RPAREN }
  | '\'' { QUOTE }
  | '"' { string (Buffer.create 16) lexbuf }
  | atom_initial atom_subsequent* as atom { ATOM atom }
  | eof { EOF }
  | _ as ch {
      parse_error lexbuf
        (Printf.sprintf "unexpected character %C" ch)
    }

and string buf = parse
  | '"' { STRING (Buffer.contents buf) }
  | "\\n" { Buffer.add_char buf '\n'; string buf lexbuf }
  | "\\t" { Buffer.add_char buf '\t'; string buf lexbuf }
  | "\\\"" { Buffer.add_char buf '"'; string buf lexbuf }
  | "\\\\" { Buffer.add_char buf '\\'; string buf lexbuf }
  | '\\' (_ as ch) {
      parse_error lexbuf (Printf.sprintf "bad escape \\%c" ch)
    }
  | '\n' {
      Lexing.new_line lexbuf;
      Buffer.add_char buf '\n';
      string buf lexbuf
    }
  | eof { parse_error lexbuf "unterminated string" }
  | _ as ch {
      Buffer.add_char buf ch;
      string buf lexbuf
    }
