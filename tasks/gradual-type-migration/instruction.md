Your task is to implement type migration for a gradually typed lambda
calculus.

## What Is Provided

The language, including its syntax, type system, and precision relation, is
documented in `/app/Language.md`. A reference implementation, along with its
source code, is compiled and ready to run at `/app/gtlc/_build/default/gtlc.exe`.

- Use `gtlc.exe exec FILE.gtlc` to run a program.

- Use `gtlc.exe is-migration ORIGINAL.gtlc MIGRATED.gtlc` to check if
  `MIGRATED.gtlc` has syntactically more precise type annotations than
  `ORIGINAL.gtlc`. This is a syntactic check only. Making types
  more precise can change the behavior of a program as described below.

- Use `gtlc.exe count-anys FILE.gtlc` to count annotations and ascriptions whose
  complete type is `any`, using the TypeWhich benchmark metric.

The environment has Python, OCaml, Rust, and Z3 installed. You can write
code in any programming language available in the environment.

## What You Must Build

Write an executable type-migration tool with exactly this command-line
interface:

```bash
/app/migrate FILE.gtlc
```

`FILE.gtlc` is a closed, well-scoped program whose lambda parameters have no
type annotations. On success, print exactly one migrated program to standard
output and exit with status 0. You may print diagnostics to standard error.

The migrated program must parse according to `/app/Language.md`, be well
typed, annotate every lambda parameter, and make `is-migration` print `true`
when given the input and migrated program.

The migration must be compatible in the sense defined by `/app/Language.md`:
in every well-typed context that receives the program at type `any`, it must
preserve values, coercion failures, and divergence. Subject to compatibility,
make the annotations as precise as possible. If several maximally precise
compatible migrations are incomparable, you may produce any one of them.
