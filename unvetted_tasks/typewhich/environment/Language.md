# Prenex polymorphism for TypeWhich

## Syntax

- Type variables: `'a`, `'b`, `'c`, …
- Function types: `T1 -> T2`
- Let with a scheme: `let x : T = e1 in e2`
  When `T` mentions type variables, the binding is generalized (prenex).
- Lambda: `fun x:T. e` — `T` is monomorphic at that binder (use `any` when
  uses conflict).
- Coercion: `(e : any)` as in TypeWhich today.

## Precision (sound migrations only)

1. Ground types (`int`, `bool`, `int -> bool`, …)
2. Prenex schemes (`'a -> 'a`, `'a -> int`, …)
3. `any` and coercions through `any`

`'a -> 'a` is better than `any -> any`. `int -> int` is better than `'a -> 'a`
when both are sound.
