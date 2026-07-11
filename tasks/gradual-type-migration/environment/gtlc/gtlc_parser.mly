%{
open Syntax
%}

%token <int> INT
%token <string> ID
%token TRUE FALSE
%token FUN IF THEN ELSE LET IN
%token INT_TYPE BOOL_TYPE ANY_TYPE
%token ARROW LPAREN RPAREN DOT COLON PLUS TIMES EQUAL EOF

%start <Syntax.expr> program

%%

program:
  | expression EOF { $1 }

expression:
  | FUN ID annotation DOT expression { Fun ($2, $3, $5) }
  | IF expression THEN expression ELSE expression { If ($2, $4, $6) }
  | LET ID EQUAL expression IN expression { Let ($2, $4, $6) }
  | ascribed_expression { $1 }

annotation:
  | { None }
  | COLON typ { Some $2 }

ascribed_expression:
  | additive_expression { $1 }
  | additive_expression COLON typ { Ann ($1, $3) }

additive_expression:
  | multiplicative_expression { $1 }
  | additive_expression PLUS multiplicative_expression { Bin (Add, $1, $3) }

multiplicative_expression:
  | application_expression { $1 }
  | multiplicative_expression TIMES application_expression { Bin (Multiply, $1, $3) }

application_expression:
  | atom { $1 }
  | application_expression atom { App ($1, $2) }

atom:
  | INT { Lit_int $1 }
  | TRUE { Lit_bool true }
  | FALSE { Lit_bool false }
  | ID { Var $1 }
  | LPAREN expression RPAREN { $2 }

typ:
  | type_atom { $1 }
  | type_atom ARROW typ { Arr ($1, $3) }

type_atom:
  | INT_TYPE { Int }
  | BOOL_TYPE { Bool }
  | ANY_TYPE { Any }
  | LPAREN typ RPAREN { $2 }
