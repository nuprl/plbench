# Finite NetKAT reachability

This task asks for a reachability checker for a finite, dup-free fragment of
NetKAT. It is based on Definition 2 and Theorem 4 of *NetKAT:
Semantic Foundations for Networks* by Anderson, Foster, Guha, Jeannin, Kozen,
Schlesinger, and Walker (POPL 2014): reachability is non-emptiness of
`a · dup · (p · t · dup)* · b`.

Packets have four fixed headers: source and destination IPv4 addresses and
source and destination 16-bit ports. Their full Cartesian product contains
`2^96` packets; an implementation cannot enumerate it explicitly. The task
presents `p`, `t`, `a`, and `b` in a small textual language. Because `dup`
records history but does not alter the current packet, reachability is the
reflexive-transitive closure of the packet relation denoted by `p . t`. The
zero-hop behavior is intentional and tested.

There is no oracle or reference implementation. Every fixture under
`tests/cases` contains prose describing the intended network, forwarding
policy, topology, and each property. Its adjacent `.expected` file records the
manually audited results. The OCaml verifier discovers all `.nk` fixtures and
scores their properties independently.

Paper: <https://www.cs.princeton.edu/~dpw/papers/frenetic-netkat.pdf>
