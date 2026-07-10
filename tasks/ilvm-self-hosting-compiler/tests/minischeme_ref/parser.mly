%{
open Ast

let atom token =
  if token = "#t" then Bool true
  else if token = "#f" then Bool false
  else
    try
      if String.contains token '.' then Float (float_of_string token)
      else Int (int_of_string token)
    with Failure _ -> Symbol token
%}

%token EOF LPAREN RPAREN QUOTE VECTOR_START
%token <string> ATOM STRING
%start program
%type <Ast.t list> program datums
%type <Ast.t> datum

%%

program:
  datums EOF { $1 }
;

datums:
  /* empty */ { [] }
| datum datums { $1 :: $2 }
;

datum:
  LPAREN datums RPAREN { List $2 }
| VECTOR_START datums RPAREN { Vector (Array.of_list $2) }
| QUOTE datum { List [Symbol "quote"; $2] }
| STRING { String $1 }
| ATOM { atom $1 }
;
