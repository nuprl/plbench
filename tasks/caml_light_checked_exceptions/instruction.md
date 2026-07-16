# Checked exceptions for Caml Light

## What Is Provided

Caml Light 0.75 is built from source in `/app/caml-light`. It is intentionally
built as an i386 program; do not port it to amd64. The source uses the original
Caml Light syntax, not modern OCaml syntax.

Use these commands while developing:

```text
/app/build.sh
/app/test.sh
```

`build.sh` bootstraps the modified compiler to a fixpoint and installs it.
`test.sh` rebuilds the compiler and runs a small public checked-exception test
suite. Keep the compiler implementation bootstrappable: the first generation
of modified compiler sources must compile with the provided compiler.

## What You Must Build

Modify the Caml Light type system and type-inference algorithm so that all
ordinary exceptions are statically checked.

Every function arrow must carry the complete set of ordinary exception
constructors that can escape when that function is applied. This information
must be part of inferred types, type unification/generalization, compiled
interfaces, and printed function types. You may choose a reasonable concrete
syntax and internal representation for exception sets, but distinct exception
constructors must not be conflated merely because their payload types match.

Exception checking must work across user-defined and standard-library
exceptions, exception handlers, recursion, curried functions, and higher-order
code. A source file's top-level phrases must have no escaping ordinary
exceptions. Defining a function that may raise is permitted; calling it from
top-level code is permitted only when all of its possible exceptions are
handled.

Document the design in `/app/Design.md`. Explain the representation of
exception sets in types, how inference and generalization handle them, how the
information is preserved in compiled interfaces, and any important design
choices or limitations.

The analysis may exclude asynchronous and resource-exhaustion failures that
programs cannot ordinarily name or control, such as stack overflow and
out-of-memory failure. It must check user-defined exceptions and synchronous
exceptions explicitly exposed by Caml Light and its standard library.

The verifier first applies a hard soundness gate: all programs whose top-level
evaluation raises an ordinary exception must be rejected. It then scores the
fraction of programs with fully handled internal exceptions that compile,
link, and terminate normally. Rejecting every program therefore earns zero.
