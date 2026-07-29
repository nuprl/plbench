# MiniScheme reference interpreter

This supplied implementation implements `/app/MiniScheme.md` in OCaml. Its
evaluator is adapted from the MiniScheme implementations used by the
`scheme-tail-call-compiler` and `scheme-typeinf` tasks.

The interpreter is a Dune project. Its `lexer.mll` and `parser.mly` are
processed through Dune's standard `ocamllex` and `ocamlyacc` stanzas; no parser
generator is implemented by hand.

The resulting commands are:

```text
minischeme --check PROGRAM
minischeme PROGRAM
```

`--check` parses and statically validates `PROGRAM` without executing it.
Normal execution performs the same check first, then evaluates the checked
program without automatically printing its final value.

Diagnostics begin with `parse error:`, `static error:`, or `runtime error:`.
