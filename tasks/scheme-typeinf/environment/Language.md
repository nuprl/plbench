# The MiniScheme Language

MiniScheme is a small, strict, Scheme-like language used by the
`scheme-typeinf` task. The reference interpreter is `/app/minischeme`.

The task asks for a sound type checker. This document defines the runtime
language; it does not prescribe any static type system.

## Lexical Structure

Whitespace separates tokens and is otherwise insignificant.

Line comments begin with `;` and run to the end of the line.

Strings are delimited by double quotes and support the escapes `\n`, `\t`,
`\"`, and `\\`.

Booleans are `#t` and `#f`. Integers are decimal OCaml integers. Floating-point
numbers are tokens accepted by `float_of_string` that contain `.`. All other
non-delimiter atoms are symbols.

The quote abbreviation `'x` is parsed as `(quote x)`.

Vector literals use `#(datum ...)`. Vector literals are data; evaluating an
unquoted vector literal as an expression is a runtime type error. Use the
`vector` builtin to construct vectors during evaluation.

## Values

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

## Expressions

Self-evaluating expressions are integers, floats, booleans, and strings.

A symbol expression looks up the symbol in the current lexical environment. In
command-line programs, unbound variables are rejected by the pre-evaluation
closedness check.

A non-empty list expression is either a special form or an application. For an
application, the operator and all operands are evaluated left-to-right, then
the operator value is applied to the argument values. Applying a non-procedure
or the wrong number of arguments is a runtime type error.

The empty list, unquoted symbols, unquoted lists-as-data, unquoted vectors, and
procedure values are not self-evaluating expressions.

## Special Forms

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

## Builtins

Arithmetic:

- `+`, `*`: any number of integer or float arguments
- `-`, `/`: one or more integer or float arguments
- `=`, `<`, `>`, `<=`, `>=`: two or more numeric arguments, returning boolean

Predicates:

- `number?`, `integer?`, `float?`, `boolean?`, `string?`, `symbol?`
- `procedure?`, `null?`, `pair?`, `list?`, `vector?`

Booleans and equality:

- `not`: accepts a boolean and returns its negation
- `eq?`: identity-like equality for symbols, booleans, the empty list, and
  object identity for other values
- `equal?`: structural equality

Lists:

- `cons`
- `car`, `cdr`: require a non-empty list
- `list`
- `length`
- `append`: concatenates lists
- `list-ref`: requires an integer index in bounds

Vectors:

- `vector`
- `vector-length`
- `vector-ref`: requires an integer index in bounds

Strings and symbols:

- `string-length`
- `string-append`
- `string-ref`: returns a one-character string and requires an integer index in
  bounds
- `string->symbol`
- `symbol->string`

Other:

- `apply`: applies a procedure to a list of arguments
- `display`: writes one value to stdout and returns `#f`; strings are written
  without surrounding quotes or escape re-encoding, and other values use the
  interpreter's printed representation
- `error`: raises a runtime error with a string message

## Pre-Evaluation Checks

After reading source text and before evaluation, the interpreter checks that
special forms are well-formed and that the combined program is closed. For the
command-line interpreter, the combined program is the sequence of all `-l`
files, followed by the optional `-e` expression. A symbol is closed if it is a
builtin, a top-level definition in the combined program, or bound by a lexical
form such as `lambda`, `let`, or `letrec`. Quoted data is not checked for free
variables.

## Command-Line Interface

The reference interpreter is non-interactive:

```bash
/app/minischeme [-l FILE]... [-e EXPR]
```

Files passed with `-l` are loaded in order. If `-e` is present, the expression
string is evaluated last. The interpreter does not print final values
automatically; use `display` for output. Runtime and parse errors are printed
as `error: ...` on stderr with a non-zero exit status.
