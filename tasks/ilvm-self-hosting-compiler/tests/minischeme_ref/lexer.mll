{
open Parser

let error lexbuf message =
  let pos = Lexing.lexeme_start_p lexbuf in
  let column = pos.pos_cnum - pos.pos_bol + 1 in
  raise (Ast.Error (Printf.sprintf "%s at line %d, column %d"
    message pos.pos_lnum column))

}

let atom_char =
  [^ ' ' '\t' '\r' '\n' '(' ')' '"' '\'' ';']

rule token = parse
  [' ' '\t' '\r'] { token lexbuf }
| '\n' { Lexing.new_line lexbuf; token lexbuf }
| ';' [^ '\n']* { token lexbuf }
| "#(" { VECTOR_START }
| '(' { LPAREN }
| ')' { RPAREN }
| '\'' { QUOTE }
| '"' { string (Buffer.create 16) lexbuf }
| atom_char+ as atom { ATOM atom }
| eof { EOF }
| _ as ch { error lexbuf (Printf.sprintf "unexpected character %C" ch) }

and string buffer = parse
  '"' { STRING (Buffer.contents buffer) }
| "\\n" { Buffer.add_char buffer '\n'; string buffer lexbuf }
| "\\t" { Buffer.add_char buffer '\t'; string buffer lexbuf }
| "\\\"" { Buffer.add_char buffer '"'; string buffer lexbuf }
| "\\\\" { Buffer.add_char buffer '\\'; string buffer lexbuf }
| '\\' (_ as ch) { error lexbuf (Printf.sprintf "bad escape \\%c" ch) }
| '\n' {
    Lexing.new_line lexbuf;
    Buffer.add_char buffer '\n';
    string buffer lexbuf
  }
| eof { error lexbuf "unterminated string" }
| _ as ch { Buffer.add_char buffer ch; string buffer lexbuf }
