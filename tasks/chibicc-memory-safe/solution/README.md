# Oracle solution

The environment provides uninstrumented chibicc at commit
`90d1f7f199cc55b13c7fdb5839d1409806633fdb`. This directory stores only the
oracle patch, runtime, compiler driver, and installation script. The patch
implements memory-safe pointers in chibicc's x86-64 code generator.

`solve.sh` applies `chibicc.patch` to `/app/chibicc`, then builds and installs
the compiler in `/app`; `/app/safec` is the graded entry point. The canonical
verifier under `tests/` contains safe
programs with exact output expectations and adversarial spatial and temporal
violations.
