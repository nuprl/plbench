# nuprl/ilvm-self-hosting-compiler

Agents write a MiniScheme-to-ILVM compiler in MiniScheme. The only deliverable
is `/app/compiler.scm`.

## Reference interpreters

The verifier contains private reference interpreters for both languages:

- `tests/minischeme_ref/` is an OCaml interpreter built with `ocamllex` and
  `ocamlyacc`.
- `tests/ilvm_ref/` is the repository's Rust reference ILVM interpreter.

Neither implementation is copied into the agent environment. Comparing
against both references prevents bugs in agent-written development tools from
affecting the score.

## Grading

For each `.scm` program under `tests/examples/`, the verifier first runs the
program with the reference MiniScheme interpreter. There are no hardcoded
expected-output tables.

The verifier then tests the submitted compiler two ways:

1. **Direct:** interpret `compiler.scm` on the test source, then run the emitted
   ILVM program.
2. **Self-hosted:** interpret `compiler.scm` on its own source to obtain an ILVM
   compiler, use that compiler on the test source, then run the emitted ILVM
   program.

Each result must have the same output and success-or-failure outcome as the
reference MiniScheme run. The two pass rates contribute equally:

```
reward = 0.5 * direct + 0.5 * self_hosted
```

This is behavioral self-hosting. The generated compiler need not reproduce its
own ILVM text byte-for-byte.

## Oracle

The bundled oracle is a real MiniScheme-to-ILVM compiler written in Python,
not MiniScheme. Its `compiler.scm` is an explicit aborting stub containing a
private marker. The single oracle branch in `run_source_compiler` invokes the
Python compiler during source-interpreted compilation.

Consequently, the oracle compiles the examples correctly in the direct pass.
When asked to compile itself, it compiles the aborting stub; that generated
ILVM program cannot compile the examples, so the self-hosted pass scores zero.
The oracle therefore earns `0.5` without pretending to self-host.

The marker is long enough to prevent accidental collisions. A submission that
copies it deliberately can obtain the same direct-only score; this is an
accepted limitation of the partial-credit oracle.
