# Verifier

The Python driver uses fixed paths and runs four steps in order:

1. Load `/tests/cases/does_throw` and `/tests/cases/safe`.
2. Rebuild and install the submitted compiler with `/app/build.sh`.
3. Apply the hard soundness gate.
4. Score safe programs if the soundness gate passes.

Each fixture is copied to a fresh directory under the neutral name `input.ml`
before compilation. This keeps its descriptive filename and test category out
of the compiler command.

## Soundness gate

The `cases/does_throw` programs each have an ordinary exception that escapes
top-level evaluation. The compiler must reject every program. If it accepts
even one, the driver raises an exception and stops before precision scoring.

## Precision score

The `cases/safe` programs exercise exception-raising code internally while
handling every exception before it reaches top level. The reward is the
fraction that compile, link, and terminate normally. A conservative rejection
receives no credit for that case. Thus a compiler that rejects every program
can pass the soundness gate but still scores zero.

Build errors, compiler timeouts, missing executables, and inconsistent test
data are not converted into synthetic results. They raise normally.
