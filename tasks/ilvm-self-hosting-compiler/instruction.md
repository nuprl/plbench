Your task is to design and implement a self-hosting compiler from a small
Scheme-like language, MiniScheme, to a small register-based assembly
language, ILVM.

## What Is Provided

ILVM is documented in `/app/ILVM.md`. MiniScheme is documented in
`/app/Scheme.md`. Neither language has an implementation installed for
you. You will need some way to run ILVM programs yourself while
developing — write an interpreter, write a compiler to native code,
whatever's fastest for you — but that tooling of yours isn't graded.

We have also installed Python, OCaml, and Rust in this environment for you
to use.

## What You Must Build

Install both of the following:

```
/app/compiler.scm    # the compiler's source, itself a MiniScheme program
/app/compiler.ilvm   # compiler.scm, compiled to ILVM by your own compiler
```

`compiler.scm` must be a well-formed MiniScheme program. When the compiler is
run, it receives exactly one command-line argument: the complete source text
of a MiniScheme program, available as `(vector-ref argv 0)`. The compiler must
`display` the complete source text of an equivalent ILVM program — one that,
when run, behaves like the input program would under MiniScheme's semantics.
`compiler.ilvm` must be the result of compiling `compiler.scm` with your own
compiler: it must itself correctly implement everything `compiler.scm`
specifies, as an ILVM program.

Every compiled program must expose its command-line arguments through
MiniScheme's predefined `argv` variable as specified in `/app/Scheme.md`.
`/app/ILVM.md` describes how those arguments are supplied to and represented
by the ILVM interpreter.

In addition:

- A MiniScheme runtime error — whether from the `error` builtin or from a
  runtime type error as defined in `/app/Scheme.md` (e.g. `(car '())`) —
  must compile to an ILVM `abort;`. This is the only failure signal: there
  is no separate "compile error" exit code, no stderr. The underlying
  ILVM implementation's own process exits with a nonzero status when the
  program it's running aborts, and with status 0 for any successful
  `exit(v)` regardless of `v`.
- On success, the compiler's entire output (via `print`/`print_str`) is the
  compiled ILVM program's source text and nothing else — no wrapper or
  diagnostic output.

Illustrative usage, once you have some way to run ILVM programs (`ilvm`
below stands in for whatever implementation you build or use):

```bash
ilvm -m MEM -r REGS /app/compiler.ilvm -f test_program.scm > out.ilvm
ilvm -m MEM -r REGS out.ilvm
```

I will grade you using my own ILVM implementation, not one you wrote and
not one you can see. Your compiler's correctness is judged independently
of whatever ILVM tooling you built for your own use.

I will test the compiler two ways.

**Self-hosting.** I will run `compiler.ilvm` on the source text of
`compiler.scm` itself, producing a second compiler, `compiler2.ilvm`.
Then, for a battery of MiniScheme test programs, I will compile each one
with both `compiler.ilvm` and `compiler2.ilvm`, run both compiled results,
and check that they behave identically (same output, same success/abort
outcome). Both runs must actually succeed and agree — if either aborts,
or they disagree, that test case fails.

**Correctness.** Independently, for the same battery of test programs, I
will check that running the program compiled by `compiler.ilvm` produces
the output I expect from that program's actual MiniScheme semantics.

You do not need to support every corner of MiniScheme to score well. I
will test your compiler on a range of programs from simple arithmetic up
through recursion, closures, and lists, and your score is proportional to
how much you get right. Getting the easy cases solid and self-hosting
right matters more than chasing full coverage.
