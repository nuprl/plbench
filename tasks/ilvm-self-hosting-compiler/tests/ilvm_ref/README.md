# ILVM reference interpreter

This private verifier fixture implements `environment/ILVM.md` in OCaml. It is
a Dune project whose lexer and parser are generated with `ocamllex` and
`ocamlyacc`.

The parser stores each straight-line instruction sequence in an array rather
than a recursively nested syntax tree. The evaluator is iterative as well, so
large generated ILVM programs do not consume host stack space per instruction.

The regression suite uses `ppx_inline_test` and is run with:

```text
dune runtest
```

The command-line interface is:

```text
ilvm [-m WORDS] [-r REGISTERS] PROGRAM [-l TEXT | -f FILE] ...
```
