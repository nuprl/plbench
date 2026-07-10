# The MiniScheme Language

MiniScheme is a small, strict, Scheme-like language. This document defines
the language's runtime semantics: values, expressions, special forms, and
builtins. No interpreter or compiler for it is provided in this environment —
that is what you are building.

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
it is not an expression. The grammar admits the empty list and vector literals
in expression position so they can be parsed, but evaluating them is a runtime
type error.

## 2. Lexical Structure

Whitespace separates tokens and is otherwise insignificant.

Line comments begin with `;` and run to the end of the line.

Strings are delimited by double quotes and support the escapes `\n`, `\t`,
`\"`, and `\\`.

Booleans are `#t` and `#f`. Numbers are decimal signed integers. All other
non-delimiter atoms are symbols.

The quote abbreviation `'x` is parsed as `(quote x)`.

Vector literals use `#(datum ...)`. Vector literals are data; evaluating an
unquoted vector literal as an expression is a runtime type error. Use the
`vector` builtin to construct vectors during evaluation.

## 3. Values

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

## 4. Expressions

Self-evaluating expressions are integers, booleans, and strings.

A symbol expression looks up the symbol in the current lexical environment.
Referencing a symbol with no binding — no enclosing lexical binding, no
top-level definition, no builtin of that name, and not the predefined `argv`
binding — is a static error: a well-formed program has no free variables
anywhere in it (quoted data is exempt, since it's data, not an expression).

A non-empty list expression is either a special form or an application. For an
application, the operator and all operands are evaluated left-to-right, then
the operator value is applied to the argument values. Applying a non-procedure
or the wrong number of arguments is a runtime type error.

The empty list, unquoted symbols, unquoted lists-as-data, unquoted vectors, and
procedure values are not self-evaluating expressions.

## 5. Special Forms

`(quote datum)` returns `datum` without evaluating it.

`(lambda (name ...) body)` creates a lexical closure. Lambdas have one body
expression and fixed arity.

`(if test then else)` evaluates `test`; if it is truthy, evaluates `then`,
otherwise evaluates `else`.

`(let ((name expr) ...) body)` evaluates each binding expression in the outer
environment, binds the results in a fresh child environment, and evaluates
`body` there.

`(letrec ((name expr) ...) body)` creates a fresh child environment, pre-binds
each name, evaluates each binding expression in the child environment, replaces
the pre-bindings with those values, and evaluates `body` in the child
environment.

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

## 6. Builtins

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

## 7. Programs

A program is a sequence of top-level forms: `define`s and expressions
(commonly `display` calls used for their side effect). Top-level forms
execute in order. A well-formed program is closed (see "Expressions" above)
and every special form is well-formed; a program that isn't is a static
error, not a runtime one.

Every program has a predefined binding named `argv`. Its value is a vector of
the program's command-line argument strings. The first actual argument is at
index `0`; unlike C's `argv`, the vector does not include the program name.
The vector may be empty. Command-line arguments must be NUL-free ASCII. ILVM
rejects non-ASCII arguments, and its packed argument strings use NUL as their
terminator.
