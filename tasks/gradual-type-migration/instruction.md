Your task is to implement type migration for a gradually typed lambda calculus.

## What Is Provided

The language, including its syntax, semantics, type system, migration relation,
and compatibility requirement, is documented in `/app/Language.md`. A reference
implementation and its source code are provided in `/app/gtlc`. It is compiled
and ready to run at `/app/gtlc/_build/default/gtlc.exe`.

- Use `gtlc.exe exec FILE.gtlc` to type-check and evaluate a program.

- Use `gtlc.exe is-migration ORIGINAL.gtlc MIGRATED.gtlc` to check whether
  `MIGRATED.gtlc` is a pointwise syntactic migration of `ORIGINAL.gtlc` under
  the precision relation in `/app/Language.md`.

- Use `gtlc.exe count-anys FILE.gtlc` to count annotations and ascriptions whose
  complete type is `any`, using the TypeWhich benchmark metric.

## What You Must Build

Write an executable type-migration tool with exactly this command-line
interface:

```bash
/app/migrate FILE.gtlc
```

`FILE.gtlc` is a closed, well-scoped program whose lambda parameters are
unannotated. On success, print exactly one migrated program to standard output
and exit with status 0. Write any diagnostics to standard error.

The migrated program must parse according to `/app/Language.md`, type-check,
annotate every lambda parameter, and satisfy:

```bash
/app/gtlc/_build/default/gtlc.exe is-migration FILE.gtlc MIGRATED.gtlc
```

The migration must be compatible as defined by `/app/Language.md`: in every
well-typed context that receives the program at type `any`, it must preserve
values, coercion failures, and divergence. Subject to compatibility, make its
annotations maximally precise. If several maximally precise compatible
migrations are incomparable, you may produce any one of them.
