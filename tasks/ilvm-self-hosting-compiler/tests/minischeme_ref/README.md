# MiniScheme reference interpreter

This private verifier fixture implements `environment/Scheme.md` in OCaml. Its
evaluator is adapted from the MiniScheme implementations used by the
`scheme-tail-call-compiler` and `scheme-typeinf` tasks.

The interpreter is a Dune project. Its `lexer.mll` and `parser.mly` are
processed through Dune's standard `ocamllex` and `ocamlyacc` stanzas; no parser
generator is implemented by hand.

The resulting command is:

```text
minischeme PROGRAM [ARG ...]
```

`PROGRAM` is evaluated without automatically printing its final value. The
remaining arguments populate MiniScheme's `argv` vector starting at index 0.
