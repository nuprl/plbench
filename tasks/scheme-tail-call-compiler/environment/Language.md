# The MiniScheme Language

MiniScheme is a small, strict, Scheme-like language. This document defines
the language's runtime semantics: values, expressions, special forms, and
builtins. The reference interpreter is `/app/minischeme`.

The benchmark asks for a source-to-source compiler that preserves this
language's behavior while restoring proper tail calls under a depth limit.
This document does not prescribe a compilation strategy.

## 1. Grammar

Terminals are shown in double quotes. `name`, `integer`, `float`, `boolean`,
and `string` are the lexical classes described in §2. A trailing `...` means
zero or more repetitions; `+` means one or more repetitions.

```
Program  ::= TopForm ...

TopForm  ::= Define
           | Expr
           | "(" "begin" TopForm + ")"

Define   ::= "(" "define" name Expr ")"
           | "(" "define" "(" name name ... ")" Expr ")"

Expr     ::= integer | float | boolean | string | name
           | "(" ")"
           | VectorDatum
           | "(" "quote" Datum ")"
           | "'" Datum
           | "(" "lambda" "(" name ... ")" Expr ")"
           | "(" "if" Expr Expr Expr ")"
           | "(" "let" "(" Binding ... ")" Expr ")"
           | "(" "letrec" "(" Binding ... ")" Expr ")"
           | "(" "begin" Expr + ")"
           | "(" "and" Expr ... ")"
           | "(" "or" Expr ... ")"
           | "(" "cond" Clause ... ")"
           | "(" "set!" name Expr ")"
           | "(" "while" Expr Expr ")"
           | "(" Expr Expr ... ")"

Binding  ::= "(" name Expr ")"
Clause   ::= "(" Expr Expr ")"
           | "(" "else" Expr ")"

Datum    ::= integer | float | boolean | string | name
           | "(" Datum ... ")"
           | VectorDatum

VectorDatum ::= "#(" Datum ... ")"
```

`define` is a top-level form, including when nested in a top-level `begin`;
it is not an expression. A `begin` must contain at least one form or
expression. The grammar admits the empty list and vector literals in
expression position so they can be parsed, but evaluating them is a runtime
type error.

## 2. Lexical Structure

Whitespace separates tokens and is otherwise insignificant.

Line comments begin with `;` and run to the end of the line.

Strings are delimited by double quotes and support the escapes `\n`, `\t`,
`\"`, and `\\`. A literal newline may also occur inside a string.

Booleans are `#t` and `#f`. Integers are decimal OCaml integers.
Floating-point numbers are atoms accepted by OCaml's `float_of_string` whose
text contains a `.`. All other atoms are symbols. Atoms may contain letters,
digits, and these characters:

```
! $ % & * + - . / : < = > ? @ ^ _ ~ #
```

The quote abbreviation `'x` is parsed as `(quote x)`.

Vector literals use `#(datum ...)`. Vector literals are data; evaluating an
unquoted vector literal as an expression is a runtime type error. Use the
`vector` builtin to construct vectors during evaluation.

## 3. Values

Runtime values are:

- integers
- floats
- booleans
- strings
- symbols
- proper lists
- vectors
- procedures, either closures or builtins

Only `#f` is false in conditionals and short-circuiting forms. Every other
value is truthy.

## 4. Expressions

Self-evaluating expressions are integers, floats, booleans, and strings.

A symbol expression looks up the symbol in the current lexical environment.
Referencing a symbol with no binding—no enclosing lexical binding, top-level
definition, or builtin of that name—is a static error: a well-formed program
has no free variables anywhere in it. Quoted data is exempt because it is
data, not an expression.

A non-empty list expression is either a special form or an application. For
an application, the operator and all operands are evaluated left-to-right,
then the operator value is applied to the argument values. Applying a
non-procedure or supplying the wrong number of arguments is a runtime type
error.

The empty list, unquoted symbols, unquoted lists-as-data, unquoted vectors,
and procedure values are not self-evaluating expressions.

## 5. Special Forms

`(quote datum)` returns `datum` without evaluating it.

`(lambda (name ...) body)` creates a lexical closure. Lambdas have one body
expression and fixed arity.

`(if test then else)` evaluates `test`; if it is truthy, evaluates `then`,
otherwise evaluates `else`.

`(let ((name expr) ...) body)` evaluates each binding expression
left-to-right in the outer environment, binds the results in a fresh child
environment, and evaluates `body` there.

`(letrec ((name expr) ...) body)` creates a fresh child environment,
pre-binds every name to `#f`, evaluates the binding expressions left-to-right
in the child environment, replaces each pre-binding with its value, and
evaluates `body` in the child environment.

`(begin expr ...)` evaluates each expression in order and returns the last
value. It requires at least one expression. At top level, a `begin` is
flattened so its nested `define` forms are also top-level definitions.

`(and expr ...)` evaluates expressions left-to-right and short-circuits on
the first false value. With no operands, it returns `#t`.

`(or expr ...)` evaluates expressions left-to-right and short-circuits on the
first truthy value. With no operands, it returns `#f`.

`(cond (test body) ... (else body))` evaluates clauses in order and returns
the body of the first truthy test. An `else` test always matches. If no clause
matches, evaluation raises a runtime type error.

`(set! name expr)` evaluates `expr`, updates the nearest enclosing lexical or
top-level binding of `name`, and returns the assigned value. The name must
already be bound. The program closedness check rejects an unbound target.

`(while test body)` repeatedly evaluates `test` and, while it is truthy,
evaluates `body`. The test is reevaluated before every iteration. The result
is the value returned by the final execution of `body`, or `#f` if the body
never runs. Iteration is implemented directly by the interpreter and does not
grow the evaluator stack from one iteration to the next, including when
`--max-stack-depth` is enabled.

`(define name expr)` and `(define (name param ...) body)` are valid only at
top level. They install a binding and return the defined name as a symbol.
All top-level definition names are in scope throughout the combined program,
including before their defining form executes; evaluation still proceeds in
source order, so reading a definition before it has been installed is a
runtime unbound-variable error.

## 6. Builtins

The forms below describe builtin arity and required argument types after
operand evaluation. Metavariables are: `v` for any value, `n` for a number,
`i` for an integer, `b` for a boolean, `s` for a string, `sym` for a symbol,
`xs` for a proper list, `vec` for a vector, and `proc` for a procedure.
Numbered metavariables have the same type, and `...` means zero or more
additional arguments of the preceding kind.

Arithmetic:

- `(+ n ...)`, `(* n ...)`: zero or more numeric arguments
- `(- n n ...)`, `(/ n n ...)`: one or more numeric arguments
- `(= n1 n2 n ...)`, `(< n1 n2 n ...)`, `(> n1 n2 n ...)`,
  `(<= n1 n2 n ...)`, `(>= n1 n2 n ...)`: two or more numeric arguments,
  returning a boolean

Arithmetic is left-to-right. `+`, `-`, and `*` return an integer if all their
arguments are integers and a float otherwise. `/` always returns a float.
Numeric comparisons convert integers to floats when comparing mixed numeric
types.

Predicates:

- `(number? v)`, `(integer? v)`, `(float? v)`, `(boolean? v)`, `(string? v)`,
  `(symbol? v)`
- `(procedure? v)`, `(null? v)`, `(pair? v)`, `(list? v)`, `(vector? v)`

Booleans and equality:

- `(not b)`: returns the boolean's negation
- `(eq? v1 v2)`: value equality for symbols and booleans, equality for the
  empty list, and object identity for other values
- `(equal? v1 v2)`: structural equality; integers and floats compare by
  numeric value

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

Other:

- `(apply proc xs)`: applies `proc` to the arguments in `xs`
- `(display v)`: writes `v` to stdout and returns `#f`; strings are written
  without surrounding quotes or escape re-encoding, and other values use the
  standard printed representation (integers and floats in decimal,
  `#t`/`#f`, symbols by name, proper lists as `(a b c)`, vectors as
  `#(a b c)`, and procedures in the interpreter's opaque procedure notation)
- `(error s)`: raises a runtime error with message `s`

## 7. Programs and the Runtime Interface

A program is a sequence of top-level forms: `define`s and expressions,
commonly `display` calls used for their side effect. Top-level forms execute
in order. A well-formed program is closed and every special form is
well-formed; malformed or open programs are rejected before evaluation.

The reference interpreter is non-interactive:

```bash
/app/minischeme [--max-stack-depth DEPTH] [-l FILE]... [-e EXPR]
```

Files passed with `-l` are loaded in order. If `-e` is present, its source
text is read after all loaded files. The resulting forms are combined into
one program for validation and evaluation. The interpreter does not print
final values automatically; use `(display v)` for output. Parse, static, and
runtime errors are printed as `error: ...` on stderr and produce a nonzero
exit status.

Without `--max-stack-depth`, logical stack counting is disabled and the
interpreter implements proper tail calls. With `--max-stack-depth DEPTH`,
every nested entry into expression evaluation consumes one logical stack
frame, including procedure calls in tail position, and evaluation fails as
soon as it would exceed `DEPTH`. The depth must be a positive integer.
