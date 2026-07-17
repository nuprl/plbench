# Static Data-Race Detection for OpenMP C

## What Is Provided

The environment has Clang/LLVM, GCC, OpenMP, Python, and standard C/C++
development tools.

## What You Must Build

Build an executable static data-race detector at `/app/race-detector`. It must
accept exactly one C source path:

```text
/app/race-detector INPUT.c
```

The input program uses OpenMP 3.0 to 5.0. Print either `RACE` or `SAFE` to
standard output and exit with code 0. You can write diagnostics to standard error.

Print `RACE` when some valid execution permitted by the C and OpenMP semantics
can contain two unordered conflicting accesses to the same storage location,
with at least one access being a write. Print `SAFE` when no such execution
exists. Here are some examples:

```text
$ /app/race-detector /examples/race.c
RACE
$ /app/race-detector /examples/safe.c
SAFE
```

The execution environment has 4 CPU cores and 4 GB of memory.