Your task is to write a self-hosting compiler from MiniScheme to ILVM.

## What Is Provided

MiniScheme is specified in `/app/Scheme.md`; ILVM is specified in
`/app/ILVM.md`. No implementation of either language is available during your
work. Python, OCaml, and Rust are installed if you want to build development
tools of your own. Those tools are not graded.

## What You Must Build

Install one file:

```
/app/compiler.scm
```

It must be a well-formed MiniScheme program. When run, it receives exactly one
command-line argument: the complete source text of another MiniScheme program,
available as `(vector-ref argv 0)`. It must `display` the complete source text
of an equivalent ILVM program and no other output.

Every program it compiles must implement MiniScheme's semantics, including the
predefined `argv` variable. A MiniScheme runtime error must execute ILVM's
`abort;` instruction.

## Grading

The verifier has private reference interpreters for both languages. It runs
every test program with the MiniScheme interpreter to establish its behavior,
then grades your compiler in two passes:

- **Direct:** run `compiler.scm` with the MiniScheme interpreter, run the ILVM
  program it emits, and compare that program with the reference behavior.
- **Self-hosted:** run `compiler.scm` with the MiniScheme interpreter on its own
  source, producing an ILVM compiler. Use that compiler to compile each test,
  run the result, and compare it with the same reference behavior.

Each pass contributes half of the reward, averaged over the test programs.
There is no byte-for-byte fixed-point requirement: the compiler produced by
self-compilation only needs to compile programs correctly.

The tests range from simple arithmetic through recursion, closures, lists,
strings, `let`/`letrec`, and vectors. Partial language support earns partial
credit.
