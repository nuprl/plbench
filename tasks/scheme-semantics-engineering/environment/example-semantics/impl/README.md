# MiniML example reference

This is the OCaml implementation corresponding to `../Semantics.lean`.

```text
miniml --check PROGRAM
miniml PROGRAM [FUEL]
```

The concrete syntax is prefix notation:

```text
e ::= integer | true | false | name
    | (+ e e) | (if e e e)
    | (fun name : type e)
    | (let name e e)
    | (e e)

type ::= Int | Bool | (-> type type)
```
