# Oracle design

The baseline is uninstrumented chibicc commit
`90d1f7f199cc55b13c7fdb5839d1409806633fdb`. Chibicc supplies no
bounds-checking pass or runtime.

The oracle changes chibicc's x86-64 code generator so pointer derivation,
subobject narrowing, and every ordinary load/store call a new capability
runtime. Function prologues register fixed automatic objects and epilogues
invalidate their frame identities. VLA decay registers dynamic objects. An
emitted constructor registers globals before `main`.

Checked pointers are opaque one-word tokens interned against an object-lifetime
identity, narrowed lower/upper bounds, and cursor. Tokens are not native
addresses, so integer fabrication cannot acquire authority. Access helpers
resolve them only after complete-width spatial and liveness checks. `free` is
a no-op. `realloc` creates a separate allocation and leaves the old allocation
valid so aliases cannot dangle. Memory and string wrappers validate complete
operand ranges before calling libc on resolved native addresses.

Defined functions are registered before `main`. Indirect calls resolve their
target through that registry, allowing function pointers to be stored, passed,
and called without permitting arbitrary data to become a control-flow target.

The runtime uses mark-and-sweep collection at a 32 MiB allocation threshold
and exposes `__safe_collect` for synchronous forced collection. Registered
globals and the active native stack are scanned for exact issued capability tokens; marked
heap objects are recursively scanned for capability edges. Sweeping releases
unreachable payloads, object records, and capability records. Capability
tokens use a per-process random tag and randomized identifiers, are never
deliberately reused, and are accepted only through exact live metadata, so
reclamation cannot revive stale authority when libc reuses a native address.

This correctness-first oracle uses a deliberately closed, single-threaded
x86-64 Linux interface. Unchecked foreign calls, computed gotos, inline
assembly, and setjmp/longjmp variants are rejected rather than allowed to
bypass the safety boundary.
