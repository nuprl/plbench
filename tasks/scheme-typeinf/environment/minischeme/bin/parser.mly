%{
open Value

let atom tok =
  if tok = "#t" then Bool true
  else if tok = "#f" then Bool false
  else
    try
      if String.contains tok '.' then Float (float_of_string tok)
      else Int (int_of_string tok)
    with Failure _ -> Symbol tok
%}

%token EOF
%token LPAREN
%token RPAREN
%token QUOTE
%token VECTOR_START
%token <string> ATOM
%token <string> STRING

%start <Value.t list> program

%%

program:
  | forms=datums EOF { forms }

datums:
  | { [] }
  | datum=datum rest=datums { datum :: rest }

datum:
  | LPAREN forms=datums RPAREN { List forms }
  | VECTOR_START forms=datums RPAREN { Vector (Array.of_list forms) }
  | QUOTE datum=datum { List [ Symbol "quote"; datum ] }
  | value=STRING { String value }
  | value=ATOM { atom value }
