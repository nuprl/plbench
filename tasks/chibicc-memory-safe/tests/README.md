# Verifier test suite

This directory is the single canonical test corpus for the task. There are no
separate oracle copies.

## Layout

- `safe/*.c` contains defined, valid programs. Each program prints values
  computed through the pointer operations it exercises.
- `safe/*.out` is the exact expected stdout for the corresponding C program.
- `unsafe/*.c` contains programs that perform one deliberate spatial or
  temporal safety violation at runtime.
- `test_suite.py` first checks every case with GCC in strict C99 mode, then
  compiles and executes every case with the submitted compiler.
- `test.sh` is Harbor's entry point and writes the final reward.

## Grading behavior

For a safe case, compilation must succeed, execution must finish within eight
seconds with status zero, stdout must exactly equal the sibling `.out` file,
and stderr must not contain `BCHECK:` or `RUNTIME ERROR:`. Exact output checks
ensure that loads, stores, pointer derivation, and libc wrappers produce the
correct values rather than merely avoiding a trap.

The corpus covers integer and floating-point accesses, global and automatic
objects, heap graphs, static pointer initializers,
subobject bounds, bulk and string operations, pointer-representation attacks,
integer overflow during pointer scaling, and reachability-only heap lifetime.

For an unsafe case, compilation must still succeed: rejecting an otherwise
supported C program is not a memory-safety implementation. At runtime, the
program must finish within eight seconds with a nonzero status and a checked
diagnostic (`BCHECK:` or `RUNTIME ERROR:`) on stderr. A
bare segmentation fault, timeout, or successful exit fails.

Every compiled program runs with `RLIMIT_AS` fixed at 1 GiB. In particular,
`safe/garbage_collection.c` allocates and touches 2 GiB cumulatively while
retaining no reference to earlier blocks. It must print the exact completion
checksum. It also keeps a linked heap graph alive solely through a global
capability root and verifies that graph after repeated collections. Without
reclamation the program reaches the address-space limit; a collector that
frees reachable objects fails the retained-graph checksum.

`safe/garbage_collection_cycles.c` exercises synchronous forced collection
through `__safe_collect()`. The test first forces collection with only a two-object
cycle rooted by a pointer nested inside a global struct, then creates more than 2 GiB of
short-lived cyclic graphs. Collection is forced every 16 cycles, when only a
few MiB have been allocated, so this checks tracing and cycle reclamation
independently of the automatic pressure threshold. The globally rooted cycle
must still contain its original values after all collections. A separate heap
object reachable only through an automatic variable verifies
active-stack rooting across the same collections.

The runner accumulates candidate-solution failures so one invocation reports
the entire suite. A source that fails `gcc -std=c99 -pedantic-errors` or a
missing `.out` file is a verifier defect and raises immediately rather than
being graded as a solution failure.

The positive lifetime cases require `free` to be a no-op, including repeated
and interior-pointer calls. `safe/heap_uaf.c` drops its direct pointer to B,
forces collection, and verifies that B remains live through the pointer stored
in A. `safe/realloc_uaf.c` verifies that successful reallocation creates a
distinct object without invalidating aliases to the old one.

## Local oracle run

After installing the oracle into a temporary directory, run:

```bash
SAFEC=/tmp/chibicc-oracle-app/safec \
TEST_ROOT="$PWD/tasks/chibicc-memory-safe/tests" \
python3 tasks/chibicc-memory-safe/tests/test_suite.py
```

Harbor requires no overrides: it supplies `/app/safec` and mounts this
directory at `/tests`.
