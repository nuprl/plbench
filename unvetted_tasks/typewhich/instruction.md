# Extend TypeWhich with prenex polymorphism

The TypeWhich source is at `/app/TypeWhich`. Extend it so type migration
supports **prenex (let-generalized) polymorphism**.

## Language extension

- Type variables use OCaml-style names: `'a`, `'b`, `'c`, …
- Universal schemes appear only on **`let`** bindings, e.g.
  `let id : 'a -> 'a = fun x. x in …`
  Each use of `id` may instantiate `'a` differently.
- Precision order for sound migrations: ground types ≻ polymorphic schemes ≻
  `any` / coercions through `any`. Polymorphic types are more precise than
  `any`. Migrations must remain sound.

## What to produce

After your changes, this must work from `/app/TypeWhich`:

```
cargo build
cargo run -- migrate --precise /app/examples/<name>.gtlc
```

Migrate the programs in `/app/examples/`. Prefer the most precise sound
migration (use `'a` on lets where that is sound and more precise than `any`).
