Implement the history-sensitive NetKAT equivalence checker specified in
`/app/NetKAT-Equivalence.md` and install it as an executable at:

```text
/app/netkat-equivalence
```

The executable receives a file containing one or more pairs of NetKAT terms.
It must determine whether each pair denotes exactly the same transformer on
packet histories. Unlike endpoint reachability, this task includes `dup` and
must distinguish programs that produce the same final packets along different
paths or with different history lengths.

The verifier uses many independently documented equations and inequations.
Properties are scored individually, so partial implementations can receive
partial credit. There is no reference checker available in the environment.

OCaml, Python, and Rust are installed. You may implement the checker in any
language. The final artifact may be a native executable or an executable
launcher.
