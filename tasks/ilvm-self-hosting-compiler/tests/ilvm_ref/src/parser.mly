%{
open Syntax

let magnitude text =
  try Int64.of_string text
  with Failure _ -> Error.fail Error.Parse ("integer literal out of range: " ^ text)

let positive text =
  let n = magnitude text in
  if Int64.compare n 2147483647L > 0 then
    Error.fail Error.Parse ("integer literal out of range: " ^ text);
  Int64.to_int32 n

let negative text =
  let n = magnitude text in
  if Int64.compare n 2147483648L > 0 then
    Error.fail Error.Parse ("integer literal out of range: -" ^ text);
  Int64.to_int32 (Int64.neg n)

let make_instr rev_actions control =
  { actions = Array.of_list (List.rev rev_actions); control }
%}

%token EOF LBRACE RBRACE LPAREN RPAREN COMMA SEMI ASSIGN
%token IFZ ELSE GOTO EXIT ABORT MALLOC MEMSIZE FREE PRINT PRINT_STR ARRAY BLOCK
%token PLUS MINUS STAR SLASH PERCENT AMP BAR CARET SHL SHR USHR EQEQ LT TILDE
%token <string> NAT ID
%token <int> REG

%start program
%type <Syntax.block list> program blocks
%type <Syntax.instr> instr
%type <Syntax.action list> rev_actions
%type <Syntax.action> action
%type <Syntax.control> control
%type <Syntax.value> value
%type <int32> signed_int
%type <Syntax.op2> op2
%type <Syntax.printable> printable

%%

program:
  blocks EOF { List.rev $1 }
;

blocks:
  block { [$1] }
| blocks block { $2 :: $1 }
;

block:
  BLOCK signed_int LBRACE instr RBRACE { ($2, $4) }
;

instr:
  rev_actions control { make_instr $1 $2 }
;

rev_actions:
  /* empty */ { [] }
| rev_actions action { $2 :: $1 }
;

control:
  GOTO LPAREN value RPAREN SEMI { Goto $3 }
| EXIT LPAREN value RPAREN SEMI { Exit $3 }
| ABORT SEMI { Abort }
| IFZ value LBRACE instr RBRACE ELSE LBRACE instr RBRACE
    { Ifz ($2, $4, $8) }
;

action:
  REG ASSIGN STAR value SEMI { Load ($1, $4) }
| STAR REG ASSIGN value SEMI { Store ($2, $4) }
| REG ASSIGN MALLOC LPAREN value RPAREN SEMI { Malloc ($1, $5) }
| REG ASSIGN MEMSIZE SEMI { Mem_size $1 }
| REG ASSIGN TILDE value SEMI { Op1 ($1, Bit_not, $4) }
| REG ASSIGN value op2 value SEMI { Op2 ($1, $4, $3, $5) }
| REG ASSIGN value SEMI { Copy ($1, $3) }
| FREE LPAREN REG RPAREN SEMI { Free $3 }
| PRINT LPAREN printable RPAREN SEMI { Print $3 }
| PRINT_STR LPAREN value RPAREN SEMI { Print_str $3 }
;

printable:
  ID { Id $1 }
| value { Value $1 }
| ARRAY LPAREN value COMMA value RPAREN { Array ($3, $5) }
;

value:
  REG { Reg $1 }
| signed_int { Imm $1 }
;

signed_int:
  NAT { positive $1 }
| PLUS NAT { positive $2 }
| MINUS NAT { negative $2 }
;

op2:
  PLUS { Add }
| MINUS { Sub }
| STAR { Mul }
| SLASH { Div }
| PERCENT { Mod }
| AMP { Bit_and }
| BAR { Bit_or }
| CARET { Bit_xor }
| SHL { Shl }
| SHR { Shr }
| USHR { Ushr }
| EQEQ { Eq }
| LT { Lt }
;
