{
open Parser

let error lexbuf message =
  let pos = Lexing.lexeme_start_p lexbuf in
  let column = pos.pos_cnum - pos.pos_bol + 1 in
  Error.fail Error.Parse
    (Printf.sprintf "%s at line %d, column %d" message pos.pos_lnum column)

let register lexbuf text =
  try REG (int_of_string (String.sub text 1 (String.length text - 1)))
  with Failure _ -> error lexbuf ("register index out of range: " ^ text)
}

let digit = ['0'-'9']
let alpha_num = ['a'-'z' 'A'-'Z' '0'-'9']

rule token = parse
  [' ' '\t' '\r'] { token lexbuf }
| '\n' { Lexing.new_line lexbuf; token lexbuf }
| "//" [^ '\n']* { token lexbuf }
| "ifz" { IFZ }
| "else" { ELSE }
| "goto" { GOTO }
| "exit" { EXIT }
| "abort" { ABORT }
| "malloc" { MALLOC }
| "memsize" { MEMSIZE }
| "free" { FREE }
| "print_str" { PRINT_STR }
| "print" { PRINT }
| "array" { ARRAY }
| "block" { BLOCK }
| '{' { LBRACE }
| '}' { RBRACE }
| '(' { LPAREN }
| ')' { RPAREN }
| ',' { COMMA }
| ';' { SEMI }
| ">>>" { USHR }
| ">>" { SHR }
| "<<" { SHL }
| "==" { EQEQ }
| '=' { ASSIGN }
| '+' { PLUS }
| '-' { MINUS }
| '*' { STAR }
| '/' { SLASH }
| '%' { PERCENT }
| '&' { AMP }
| '|' { BAR }
| '^' { CARET }
| '<' { LT }
| '~' { TILDE }
| 'r' digit+ as text { register lexbuf text }
| digit+ as text { NAT text }
| '"' (alpha_num+ as text) '"' { ID text }
| eof { EOF }
| _ as ch { error lexbuf (Printf.sprintf "unexpected character %C" ch) }
