# Worked MiniML semantics

This directory contains a complete worked instance of the canonical
`SemanticsTemplate.lean` interface. In the repository, the interface is the
parent module; in the task container, it is `/app/SemanticsTemplate.lean` and
this directory is `/example`.

- `Semantics.lean` defines typed MiniML syntax, an independent inductive `HasType`
  judgment and independent inductive substitution-based one-step `Step`
  relation, progress and preservation, a statically validating parser, a pure
  recursive fuel-bounded big-step interpreter proved sound and complete for
  zero or more `Step`s, and the value
  `MiniML.development : SemanticsTemplate.Development`.
- `impl` provides an OCaml implementation of the same language and CLI.

There is no local copy or symlink of the template. Lean resolves the canonical
module through `LEAN_PATH`.

MiniML has no program-argument or `argv` facility. The paths and optional fuel
shown below are host CLI controls and are not values supplied to the modeled
program.

From the parent `environment` directory in the repository, first compile the
canonical template, then run the two implementations with:

```text
lean -o SemanticsTemplate.olean SemanticsTemplate.lean
LEAN_PATH=. lean --run example-semantics/Semantics.lean --check example-semantics/examples/closure.miniml
LEAN_PATH=. lean --run example-semantics/Semantics.lean example-semantics/examples/closure.miniml
dune build --root example-semantics/impl main.exe
example-semantics/impl/_build/default/main.exe --check example-semantics/examples/closure.miniml
example-semantics/impl/_build/default/main.exe example-semantics/examples/closure.miniml
```
