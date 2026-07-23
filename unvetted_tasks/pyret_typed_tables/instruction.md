# Static Type Checking for Tables in Pyret

## What Is Provided

A checkout of the Pyret language implementation is at `/app/pyret-lang`, already
built. Pyret is a self-hosted language with two compiler backends that live
side by side in that repository: the Pyret-hosted ("regular") compiler and a
TypeScript compiler under `lang/src/ts-compiler/`. Build and test commands are
run from `/app/pyret-lang/lang`:

```bash
cd /app/pyret-lang/lang
make ts-compiler        # (re)build the TypeScript compiler
make ts-test            # TypeScript compiler test suites
make all-pyret-test     # the Pyret-hosted ("regular") test suite
```

Two reference documents are provided and are the only external material you
need:

* `/app/b2t2-paper.txt` — "Types for Tables: A Language Design Benchmark" (Lu,
  Greenman, Krishnamurthi), a text rendering of the paper, including its Table
  API and example programs.
* `/app/core.arr` — the Bootstrap "core" library, a body of real Pyret code
  that uses tables heavily.

The environment already has Node, and the compiler builds and its tests pass
as delivered. Read the task below in full before starting.

## Your Task

Design and implement type checking for tables in Pyret.

This is a broad design space. You should be philosophically aligned with
`/app/b2t2-paper.txt` and be able to show representative examples from it
passing.

The type system should also be able to meaningfully type-check the
table-related functions in `/app/core.arr`, for example things like group()
that take column names as arguments, or functions that append column names.
You don't have to type-check that whole file; mine it for representative
examples.

For table data that comes from unknown sources, you can require annotations.
You are also welcome to design new language features (e.g. a new import form
that can, at module resolution time, load a CSV file and calculate its types)
if it gives interesting new opportunities in that space. The focus is still on
typing existing code, but don't get so stuck that you can't try out a small
suggestion that unlocks a lot of opportunities.

Constraints:

- Focus your implementation on the TypeScript compiler (there are two backends,
  use TypeScript)
- All existing tests (make all-pyret-test) must pass in the regular and
  TypeScript implementations
- You should write substantial new tests, and tests extracting functions from
  examples above (and other examples; you can look around for Pyret code in the
  Bootstrap starter files that helps pull your design in useful directions)
- You must maintain soundness; if you can't figure out how to type check
  a feature, leave it untypable rather than making it unsound
- You *cannot* change code generation or runtime functions (e.g. no "if only
  tables worked like *this*, it would be fine")

Freedoms:

- You can design new type syntax and new syntactic forms for bindings and
  annotations around tables, and associated machinery
- You can fix bugs you find in the type checker along the way if they are clear
  soundness or algorithmic errors in the type checker (and you're allowed to
  change associated tests' expected outcomes when you fix a bug).
- You have free reign to change type checker representations, rewrite type
  checker logic, re-plumb type information or re-represent type information.
  If it helps you to change all the internal representations in the type
  checker or a core constraint-solving algorithm or add extra passes, do so.
- The checking does not have to be enforced dynamically. We already punt on
  checking e.g. the Number in List<Number> dynamically. Dynamic checking can be
  best-effort as long as the overall system is sound.

Reporting back:

- Give a general report of your approach in terms of the grammar of new types
  and the type rules you introduced
- Report on bugs you found
- Report on features that are not reasonably typable (e.g. they must have type
  Any or similar)
- Report on your high-level strategies for implementation
- Report on alternate designs that are constrained or difficult in some way,
  but might work better if you were given the ability to make some language
  changes

## Deliverables

Leave the following in place in the container when you are done. They are how
your work is evaluated, so treat the paths and behavior as a contract.

1. **Your modified TypeScript compiler, built.** `cd /app/pyret-lang/lang &&
   make ts-compiler` must succeed, and the pre-existing test suites must still
   pass (`make ts-test` and `make all-pyret-test`), as required by the
   constraints above.

2. **A single-file type checker at `/app/typecheck-example`.** This must be an
   executable that type-checks one Pyret program with your modified TypeScript
   compiler:

   ```bash
   /app/typecheck-example FILE.arr
   ```

   It must exit with status 0 when `FILE.arr` has no type error, and with a
   non-zero status when `FILE.arr` contains a type error (printing the type
   error to stdout or stderr). This is the same type checking your example
   programs rely on; it is invoked on ordinary Pyret programs, both
   well-typed and ill-typed.

3. **Typed example programs in `/app/typed-examples/`,** one program per `.arr`
   file. Each program must type-check successfully under
   `/app/typecheck-example`, and each must exercise your table types on real
   table operations (constructing tables and/or operating on tables, rows, and
   columns) rather than trivial code. Include programs adapted from the B2T2
   examples and from `core.arr`'s table-related functions — the representative
   examples the task asks you to show passing.

4. **A design report at `/app/DESIGN.md`** that covers the "Reporting back"
   items above — your type grammar and type rules, bugs you found, features you
   left untypable and why, your implementation strategy, and alternate designs
   that would need language changes — and briefly documents how someone writes
   and reads the new table types. Write it so a reader who has the paper and
   `core.arr` in hand, but has not seen your diff, can understand and evaluate
   your design.
