# MiniScheme reference interpreter

This private verifier fixture implements `environment/Scheme.md` in OCaml. Its
evaluator is adapted from the MiniScheme implementations used by the
`scheme-tail-call-compiler` and `scheme-typeinf` tasks.

`lexer.mll` and `parser.mly` are processed by OCaml's standard `ocamllex` and
`ocamlyacc` tools in `tests/test.sh`; no parser generator is implemented by
hand and no third-party OCaml packages are required.

The resulting command is:

```text
minischeme PROGRAM [ARG ...]
```

`PROGRAM` is evaluated without automatically printing its final value. The
remaining arguments populate MiniScheme's `argv` vector starting at index 0.
