# Design a sound type inference algorithm for MiniScheme

The environment provides **MiniScheme**, a small Scheme-like language
implemented in OCaml at:

```
/app/mscheme
```

Source lives under `/app/mscheme-src` (dune project). MiniScheme supports
higher-order functions, lists, vectors, strings, booleans, floats, ints,
symbols, and `quote` / `'` (programs-as-data).

Examples:

```
/app/mscheme -e '(+ 1 2)'
/app/mscheme path/to/prog.scm
/app/mscheme -l lib.scm -e '(my-fn 3)'
/app/mscheme -l /app/mceval.scm -e '(ms-eval (quote (+ 1 2)) (ms-initial-env))'
```

There is **no** prescribed type system. You invent the types and the
inference algorithm. The only hard requirement is **soundness**:

> If your checker accepts a program, evaluating that program with
> `/app/mscheme` must not raise a **runtime type error**.

Runtime type errors include: applying a non-procedure, wrong arity, builtin
argument of the wrong sort (e.g. `car` of an int), out-of-bounds
`list-ref` / `vector-ref` / `string-ref`, and unbound variables. The host
prints `error: …` and exits non-zero.

Incompleteness is fine: rejecting programs that would run is allowed.
Unsound acceptance is not.

## What to produce

Install an executable type checker at:

```
/app/typeinf
```

Usage:

```
/app/typeinf FILE.scm
```

- Exit status **0** and a line of stdout describing the inferred type (any
  format you like) means the program is accepted as well-typed.
- Exit status **non-zero** means the program is rejected (ill-typed or
  outside the fragment you support).

## Challenge (for you)

1. Implement type inference for MiniScheme as above.
2. Write a **metacircular interpreter** for MiniScheme *in* MiniScheme
   and install it at `/app/mceval.scm`. It must provide:

   - `(ms-initial-env)` — an initial environment value
   - `(ms-eval expr env)` — evaluate expression datum `expr` in `env`

   Load / exercise it with the host:

   ```
   /app/mscheme -l /app/mceval.scm -e '(ms-eval (quote (+ 1 2)) (ms-initial-env))'
   ```

   That command should print `3`. Use `quote` / `'` freely — that is how
   programs are represented as heterogeneous lists of symbols and literals.
3. Run your type checker on that metacircular interpreter (and on small
   clients that exercise it). We do **not** specify how you type
   heterogeneous lists (unions, recursive AST types, gradual typing, soft
   typing, …).

The verifier grades `/app/typeinf` on a hidden suite (required `ok`/`bad`
programs plus optional `hard-ok` programs, including typing the
metacircular interpreter) and checks the `ms-eval` API above.
