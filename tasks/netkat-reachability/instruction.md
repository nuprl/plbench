Implement the finite NetKAT reachability checker specified in
`/app/NetKAT.md` and install it as an executable at:

```text
/app/netkat-reach
```

The small textual input format is fully described in the specification. Every
packet has four fixed headers with their natural domains: two IPv4 addresses
and two unsigned 16-bit ports. The checker must implement its predicate and
policy semantics over that full packet space. In particular, a check from
predicate `a` to predicate `b` succeeds exactly when `b` is reachable from `a`
through zero or more repetitions of `policy . topology`.

The verifier runs the executable on many valid input files and compares each
reported property with an independently documented expected result. Properties
are scored individually, so partial implementations can receive partial
credit. There is no reference checker available in the environment.

OCaml, Python, and Rust are installed. You may implement the checker in any
language. The final `/app/netkat-reach` may be a native executable or an
executable launcher.
