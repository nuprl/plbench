Your task is to implement type migration for a gradually typed lambda calculus.

## What Is Provided

The language, including its syntax, semantics, and type system, is documented
in `/app/Language.md`. A reference implementation and its source code are
provided in `/app/gtlc`. It is compiled and ready to run at
`/app/gtlc/_build/default/gtlc.exe`.

- Use `gtlc.exe exec FILE.gtlc` to type-check and evaluate a program.

- Use `gtlc.exe type-check FILE.gtlc` to check that a program parses and is
  well typed. It produces no output on success.

- Use `gtlc.exe is-migration ORIGINAL.gtlc MIGRATED.gtlc` to check whether
  `MIGRATED.gtlc` is a pointwise syntactic migration of `ORIGINAL.gtlc` under
  the precision relation in `/app/Language.md`.

- Use `gtlc.exe precision-distance LESS.gtlc MORE.gtlc` to count the
  single-step type refinements between two pointwise-comparable programs.

- Use `gtlc.exe count-anys FILE.gtlc` to count the number of bare `any`
  annotations. A missing lambda annotation counts as an implicit bare `any`.

## What You Must Build

Write an executable type-migration tool with exactly this command-line
interface:

```bash
/app/migrate INPUT.gtlc > OUTPUT.gtlc
```

On success, print exactly one migrated program to standard output
and exit with status 0. Write any diagnostics to standard error.

The migrated program `OUTPUT.gtlc` must have the following properties:

1. It is at least as precise, syntactically, as the original program
   `INPUT.gtlc`; that is, `gtlc.exe is-migration INPUT.gtlc OUTPUT.gtlc` must
   print `true`. See `/app/gtlc/migration.ml` for the implementation.

2. It must be **behaviorally equivalent** to the original program. This means
   that the two programs must be indistinguishable in all `any`-typed
   program contexts.

   Here are some examples:

   - Consider the program `fun x . x`. We can migrate it to `fun x : int . x`,
     which is syntactically more precise. However, they are not behaviorally
     equivalent. In the context `(_ : any) true`, we can substitute both to get:

     + `( (fun x . x) : any) true` which returns true

     + `( (fun x : int . x) : any) true` which returns a runtime error because
       `true` is not an integer.

   - Consider the program `(fun x . x + 1)`. We can migrate it to
     `(fun x : int . x + 1)` which is syntactically more precise and
     behaviorally equivalent. In any context that applies the function, the
     argument `x` must be an integer. Before migration, the `+` will error.
     After migration, the dynamic check will error, but these are indistinguishable
     in the language.

Every program emitted by the migration tool must parse and type-check on its
own. If any emitted program fails this requirement, the reward for the entire
run is zero, rather than only the reward for that input.

The objective is to output the *most precise migration possible that is still
behaviorally equivalent.* I have a hidden suite of tests where I know the most
precise migration possible (deduced by reasoning through the program by hand).
You will be graded based on how close your result is to that most precise
migration. Note that on hard problems, there may be several solutions that are
equally precise, but you can output any out of them.
