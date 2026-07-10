{
open Gtlc_parser

exception Error of string

let integer lexbuf = INT (int_of_string (Lexing.lexeme lexbuf))
}

let digit = ['0'-'9']
let initial = ['a'-'z' 'A'-'Z' '_']
let subsequent = ['a'-'z' 'A'-'Z' '0'-'9' '_']
let identifier = initial subsequent*

rule token = parse
  | [' ' '\t' '\r' '\n']+ { token lexbuf }
  | "//" [^ '\n']* { token lexbuf }
  | "fun" { FUN }
  | "if" { IF }
  | "then" { THEN }
  | "else" { ELSE }
  | "let" { LET }
  | "in" { IN }
  | "true" { TRUE }
  | "false" { FALSE }
  | "int" { INT_TYPE }
  | "bool" { BOOL_TYPE }
  | "any" { ANY_TYPE }
  | "->" { ARROW }
  | '(' { LPAREN }
  | ')' { RPAREN }
  | '.' { DOT }
  | ':' { COLON }
  | '+' { PLUS }
  | '*' { TIMES }
  | '=' { EQUAL }
  | '-' digit+ { integer lexbuf }
  | digit+ { integer lexbuf }
  | identifier as name { ID name }
  | eof { EOF }
  | _ as character {
      raise
        (Error
           (Printf.sprintf "unexpected character %C at byte %d" character
              (Lexing.lexeme_start lexbuf)))
    }
