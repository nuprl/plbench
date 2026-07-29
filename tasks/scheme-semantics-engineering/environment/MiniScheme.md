# The MiniScheme Language

MiniScheme is a small, strict, Scheme-like language. This document defines its
syntax, static semantics, runtime values, expressions, special forms, and
builtins. A reference checker and interpreter are provided in this environment.

## 1. Grammar

Terminals are shown in double quotes. `name`, `integer`, `boolean`, and
`string` are the lexical classes described in §2. A trailing `...` means
zero or more repetitions; `?` marks an optional item.

```
Program  ::= TopForm ...

TopForm  ::= Define
           | Expr
           | "(" "begin" TopForm ... ")"

Define   ::= "(" "define" name Expr ")"
           | "(" "define" "(" name name ... ")" Expr ")"

Expr     ::= integer | boolean | string | name
           | "(" ")"
           | VectorDatum
           | "(" "quote" Datum ")"
           | "'" Datum
           | "(" "lambda" "(" name ... ")" Expr ")"
           | "(" "if" Expr Expr Expr ")"
           | "(" "let" "(" Binding ... ")" Expr ")"
           | "(" "letrec" "(" Binding ... ")" Expr ")"
           | "(" "begin" Expr ... ")"
           | "(" "and" Expr ... ")"
           | "(" "or" Expr ... ")"
           | "(" "cond" Clause ... ElseClause? ")"
           | "(" Expr Expr ... ")"

Binding  ::= "(" name Expr ")"
Clause    ::= "(" Expr Expr ")"
ElseClause ::= "(" "else" Expr ")"

Datum    ::= integer | boolean | string | name
           | "(" Datum ... ")"
           | VectorDatum

VectorDatum ::= "#(" Datum ... ")"
```

`define` is a top-level form, including when nested in a top-level `begin`;
it is not an expression. The datum parser accepts the empty list and vector
literals in expression position, but the static checker rejects them there.

## 2. Lexical Structure

Whitespace separates tokens and is otherwise insignificant.

Line comments begin with `;` and run to the end of the line.

Strings are delimited by double quotes and support the escapes `\n`, `\t`,
`\"`, and `\\`.

Booleans are `#t` and `#f`. Numbers are decimal signed integers. All other
non-delimiter atoms are symbols.

The quote abbreviation `'x` is parsed as `(quote x)`.

Vector literals use `#(datum ...)`. Vector literals are data; an unquoted vector
literal is not a valid expression. Use the `vector` builtin to construct vectors
during evaluation.

## 3. Static Semantics

The reference executable has two modes:

```text
minischeme --check PROGRAM
minischeme PROGRAM
```

`--check` parses and statically validates the program without executing it.
Normal execution performs exactly the same check before evaluation. Successful
checking produces no output. Diagnostics distinguish `parse error:`,
`static error:`, and `runtime error:`.

Static checking validates every special-form shape and binder. Lambda
parameters and `let`/`letrec` binding names must be symbols and must be distinct
within their binder. `define` is permitted only as a top-level form, including
inside a top-level `begin`. Empty-list and vector datums are not expressions.
`cond` clauses must have two elements, and an `else` clause must be last.

Every variable reference must be statically bound. The initial scope contains
all builtins. Lambda parameters and `let` bindings have lexical
scope; `let` initializers use the outer scope, while `letrec` initializers use
the recursively extended scope. All top-level definition names are collected
before checking, including definitions inside top-level `begin`, so forward and
mutually recursive global references are statically valid. Quoted data is not
name-resolved.

Top-level definition cells are allocated before execution. Reading a declared
global before its defining form executes, or reading a `letrec` binding during
its own unfinished initialization, is a runtime uninitialized-binding error.
Type and procedure-arity mismatches, applying non-procedures, division by zero,
invalid indexes, failed dynamic operations, and `(error ...)` are also runtime
errors.

## 4. Values

Runtime values are:

- integers
- booleans
- strings
- symbols
- proper lists
- vectors
- procedures, either closures or builtins

Only `#f` is false in conditionals and short-circuiting forms. Every other
value is truthy.

## 5. Expressions

Self-evaluating expressions are integers, booleans, and strings.

A symbol expression looks up its statically established binding in the current
lexical environment. A symbol with no lexical, global, or builtin binding is
rejected statically. Quoted symbols are data and are not looked up.

A non-empty list expression is either a special form or an application. For an
application, the operator is evaluated first. The operands are then evaluated
from right to left, and the resulting values retain their original argument
positions when the operator is applied. This order is observable through
`display`. Applying a non-procedure or the wrong number of arguments is a
runtime type error.

The empty list, unquoted lists-as-data, unquoted vectors, and procedure values
are not self-evaluating expressions.

## 6. Special Forms

`(quote datum)` returns `datum` without evaluating it.

`(lambda (name ...) body)` creates a lexical closure. Lambdas have one body
expression and fixed arity.

`(if test then else)` evaluates `test`; if it is truthy, evaluates `then`,
otherwise evaluates `else`.

`(let ((name expr) ...) body)` evaluates the binding expressions from right to
left in the outer environment, binds the results in their original order in a
fresh child environment, and evaluates `body` there.

`(letrec ((name expr) ...) body)` creates a fresh child environment, pre-binds
each name, evaluates the binding expressions from left to right in the child
environment, replaces the pre-bindings with those values, and evaluates `body`
in the child environment.

`(begin expr ...)` evaluates each expression in order and returns the last
value. At top level, a `begin` is flattened so its nested `define` forms are
also top-level definitions.

`(and expr ...)` evaluates expressions left-to-right and short-circuits on the
first false value. With no operands, it returns `#t`.

`(or expr ...)` evaluates expressions left-to-right and short-circuits on the
first truthy value. With no operands, it returns `#f`.

`(cond (test body) ... (else body))` evaluates clauses in order and returns the
body of the first truthy test. If there is no `else` clause and no test
matches, evaluation raises a runtime type error.

`(define name expr)` and `(define (name param ...) body)` are valid only at top
level. They install a binding and return the defined name as a symbol.

## 7. Builtins

The forms below describe builtin arity and required argument types after
operand evaluation. Metavariables are: `v` for any value, `n` and `i` for an
integer, `b` for a boolean, `s` for a string, `sym` for a symbol,
`xs` for a proper list, `vec` for a vector, and `proc` for a procedure.
Numbered metavariables have the same type, and `...` means zero or more
additional arguments of the preceding kind.

Arithmetic:

- `(+ n ...)`, `(* n ...)`: zero or more numeric arguments
- `(- n n ...)`, `(/ n n ...)`: one or more numeric arguments
- `(= n1 n2 n ...)`, `(< n1 n2 n ...)`, `(> n1 n2 n ...)`,
  `(<= n1 n2 n ...)`, `(>= n1 n2 n ...)`: two or more numeric arguments,
  returning a boolean

All arithmetic produces integers. Division is integer division truncated toward
zero; unary `(/ n)` computes the integer quotient `1 / n`. Division by zero is
a runtime error.

Predicates:

- `(number? v)`, `(integer? v)`, `(boolean? v)`, `(string? v)`,
  `(symbol? v)`
- `(procedure? v)`, `(null? v)`, `(pair? v)`, `(list? v)`, `(vector? v)`

Booleans and equality:

- `(not b)`: returns the boolean's negation
- `(eq? v1 v2)`: identity-like equality for symbols, booleans, and the empty
  list, and object identity for other values
- `(equal? v1 v2)`: structural equality

Lists:

- `(cons v xs)`
- `(car xs)`, `(cdr xs)`: `xs` must be non-empty
- `(list v ...)`
- `(length xs)`
- `(append xs ...)`: concatenates zero or more lists
- `(list-ref xs i)`: `i` must be in bounds

Vectors:

- `(vector v ...)`
- `(vector-length vec)`
- `(vector-ref vec i)`: `i` must be in bounds

Strings and symbols:

- `(string-length s)`
- `(string-append s ...)`
- `(string-ref s i)`: returns a one-character string; `i` must be in bounds
- `(string->symbol s)`
- `(symbol->string sym)`
- `(char-code s)`: `s` must contain exactly one character; returns its ASCII
  code point (0-127) as an integer
- `(code-char i)`: `i` must be in `0..127`; returns the corresponding
  one-character string

Other:

- `(apply proc xs)`: applies `proc` to the arguments in `xs`
- `(display v)`: writes `v` followed by a newline to stdout and returns
  `#f`; strings are written without surrounding quotes or escape re-encoding,
  and other values use the standard printed representation (integers in
  decimal, `#t`/`#f`, symbols by name, proper lists as `(a b c)`,
  vectors as `#(a b c)`)
- `(error s)`: raises a runtime error with message `s`

## 8. Programs

A program is a sequence of top-level forms: `define`s and expressions
(commonly `display` calls used for their side effect). Top-level forms execute
in order after the complete program passes static checking. Malformed forms,
invalid binders, and unbound variable references are static errors; dynamic
failures during evaluation are runtime errors.
