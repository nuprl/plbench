# Gradually typed lambda calculus

This document defines the complete source and output language for the type
migration task. Files contain one expression and are UTF-8 text.

## Concrete syntax

```text
T ::= int | bool | any | T -> T | (T)

e ::= n | true | false | x
    | fun x . e
    | fun x : T . e
    | e e
    | e + e | e * e
    | if e then e else e
    | let x = e in e
    | e : T
    | (e)
```

`n` is a possibly negative decimal integer. As a recommendation to avoid
pointless differences between integer representations, programs for this task
keep integer literals between `-100` and `100`; implementations need not check
this range and may represent integers however they like. Identifiers begin
with an ASCII letter or underscore and continue with letters, digits, or
underscores.
Whitespace is insignificant. A comment begins with `//` and continues to the
end of its line.

Function application associates to the left and binds more tightly than `*`,
which binds more tightly than `+`. Both arithmetic operators associate to the
left. Function types associate to the right. Function bodies, conditional
branches, let bodies, and expression ascriptions extend as far to the right as
their enclosing parentheses allow.

Task inputs use only `fun x . e`; `fun x : T . e` is required in migrated
output. An expression ascription `(e : T)` may appear in migrated output. It
is an explicit guarded cast, not a change to the underlying program.

## Types, consistency, and precision

`any` is the dynamic type. Type consistency, written `S ~ T`, is the least
reflexive and symmetric relation satisfying:

```text
any ~ T
S1 ~ T1 and S2 ~ T2  implies  (S1 -> S2) ~ (T1 -> T2)
```

Consistency is not transitive. In particular, `int ~ any` and `any ~ bool`,
but `int` is not consistent with `bool`.

Type precision is written `S <= T`, meaning that `T` is at least as precise
as `S`:

```text
any <= T
int <= int
bool <= bool
S1 <= T1 and S2 <= T2  implies  (S1 -> S2) <= (T1 -> T2)
```

There is no subtyping and function arguments are not contravariant in the
precision relation.

## Static semantics

An omitted lambda annotation means `any`. Variables and literals have their
usual types. A lambda has type `S -> T` when its parameter annotation is `S`
and its body has type `T`.

At an application, a function of type `S -> T` accepts an argument whose type
is consistent with `S` and produces `T`. A value of type `any` in function
position is treated as `any -> any`. The two operands of `+` and `*` are used
at type `int`, and their result is `int`. A conditional uses its condition at
type `bool`; its branches are cast to their most precise common consistent
type, or to `any` when their types are incompatible. A let-bound variable has
the type of its definition. An ascription `(e : T)` uses the value of `e` at
type `T`.

Every use at a merely consistent type inserts a guarded runtime cast. Uses at
inconsistent types are also accepted, but insert a cast that is certain to
fail if reached. This choice is important: an error in unreachable code does
not cause migration to reject the whole program.

## Guarded runtime semantics

Evaluation is call by value with lexical scope. Integer arithmetic and
conditionals have their usual behavior after inserted casts are performed.
The observable outcomes are an integer, a boolean, a function value, a failed
cast, or divergence.

Casting a base value to `any` attaches an `int` or `bool` tag. Casting a
function to `any` attaches a `fun` tag and preserves its argument and result
checks. Casting from `any` checks and removes the corresponding tag. Casting
between function types is higher order: a cast from `S1 -> S2` to `T1 -> T2`
checks arguments from `T1` to `S1` and results from `S2` to `T2`. Casting
between inconsistent types proceeds through `any`, and therefore fails at the
incompatible tag check when evaluated.

## Compatible type migration

Type decorations are lambda annotations and expression ascriptions. Ignoring
type decorations, the original and migrated programs must have exactly the
same syntax, including every variable and binder name. At each corresponding
position, the original decoration type must be no more precise than the
migrated decoration type. A missing decoration is treated as `any`. Both
programs must be well typed.

The required safety property is the paper's stronger, context-restricted
definition instantiated at `any`. For every well-typed closing context that
expects the program at type `any`, the original and migrated programs must:

- both terminate with equally observable base values or corresponding
  function values;
- both stop at failed casts; or
- both diverge.

Thus changing `fun x . x` into `fun x : int . x` is not compatible: an
untyped caller may pass `true`, which succeeds before migration and fails
afterward. More precise annotations inside a closed computation are useful
when they preserve this contextual behavior.

This language and safety criterion are based on the GTLC and Definitions
3.1--3.4 of *Solver-Based Gradual Type Migration* (Phipps-Costin et al.,
OOPSLA 2021), and the concrete syntax follows the TypeWhich parser.
