# Static analysis for Fil-C panics

## What Is Provided

Fil-C is a "fanatically compatible memory-safe implementation of C and C++.  All
memory safety errors are caught as Fil-C panics." The environment provides the
Fil-C compiler (`filcc`) and a shallow clone of its source code at `/app/fil-c`
for reference.

## What You Must Build

Develop a sound, conservative static analysis for C99 programs that determines
whether a program may produce a Fil-C panic. Only C99 programs need to be
supported.

Implement the analysis as the executable `/app/analyze` with this interface:

```text
/app/analyze input.c
```

For a valid C input, your program must print either `SAFE` or `MAY PANIC` and
exit with code 0. You can print debugging output to standard error.

The runtime environment for development and running the analysis has 4GB RAM
and 2 CPU cores.