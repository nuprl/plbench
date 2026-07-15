# Memory-safe C

Your task is to add memory safety to the chibicc C compiler. You only need
to support the C99 standard.

## What Is Provided

The chibicc source tree is provided at `/app/chibicc`. It has already been
built, and standard C development tools are installed. The programming
environment and test environment has 1GB RAM and 2 CPU cores.

## What You Must Build

Implement a memory-safe, garbage-collected C compiler at `/app/safec` with
exactly this command-line interface:

```text
/app/safec input.c -o output
```

Support the C accepted by the supplied chibicc, focusing on the C99 subset.
Inline assembly and nonlocal jumps through the `setjmp`/`longjmp` family are out
of scope. Programs using supported features must compile even when executing
them would violate memory safety. Detect a violation when it occurs instead of
rejecting the program. Provide spatial and temporal memory safety for every
memory access. Enforce the bounds of each C subobject, not only those of its
enclosing allocation. Bounds must be byte-precise: every byte accessed must lie
within the exact object or subobject designated by the pointer. An access even
one byte outside that range is a memory-safety violation, regardless of whether
the address remains in the same machine word, enclosing allocation, or mapped
memory page.

Do not allow an integer value to create a pointer that can be used for a memory
access, whether through a conversion or through type-punning. Pointer
arithmetic must not use overflow or wraparound to make an invalid access appear
valid.

A `printf` conversion that consumes a pointer, including `%s` or `%n`, must
report a memory-safety violation when executed.

For a non-null argument and nonzero size, `realloc` must accept only the
beginning of a heap object and return a distinct new object. With a zero size,
it must return `NULL`. It must never change or invalidate the old object.

Garbage-collect heap objects automatically. `free` must be a no-op for every
argument. Provide this function:

```c
void __safe_collect(void);
```

`__safe_collect` must complete a garbage collection before returning.

A memory-safety violation must terminate execution with a nonzero status and
write `BCHECK:` or `RUNTIME ERROR:` to standard error.
