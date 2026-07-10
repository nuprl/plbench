# Self-Hosting Compiler for MiniScheme using ILVM

This task requires the agent to write a self-hosted compiler for MiniScheme that
targets ILVM, which is a small, WebAssembly-like virtual machine. The agent
receives a natural language specification of both languages, but no implementation.
The agent may build its own interpreters or other development tools, but only
the submitted compiler is graded.


The verifier has reference interpreters for both MiniScheme and ILVM and
several MiniScheme programs to test the compiler. We use each test program
as follows:

1. We run it with the reference MiniScheme interpreter and record its behavior:
   its standard output and whether it succeeds or fails.
2. We compile it with the submitted compiler, which we run using our reference
   MiniScheme interpreter. We run the output program with the reference ILVM
   interpreter. We compare its behavior with the expected behavior from (1).
3. We have the submitted compiler compile itself to ILVM, using the reference
   interpreter to bootstrap. We then compile each test program to ILVM using
   this MiniScheme compiler (in ILVM) and compare its behavior with (1).

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
