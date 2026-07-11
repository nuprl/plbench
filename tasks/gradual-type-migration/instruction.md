Implement a gradual type-migration tool for the language documented in
`/app/Language.md`.

Your submission must install an executable at `/app/migrate` with this
interface:

```text
/app/migrate FILE.gtlc
```

`FILE.gtlc` is a closed, well-scoped program whose lambda parameters have no
type annotations. On success, print exactly one migrated program to standard
output and exit with status 0. Diagnostic text may be printed to standard
error.

Z3 4.8.12 is installed in the environment and available as `z3`.

The migrated program must:

1. parse in the language from `/app/Language.md`;
2. annotate every lambda parameter;
3. be alpha-equivalent to the input after all parameter annotations and
   expression ascriptions are erased;
4. be well typed and have a result type at least as precise as the input's;
5. be a compatible migration in the strict sense described in
   `/app/Language.md`: it must preserve values, coercion failures, and
   divergence in every well-typed context that receives the program at type
   `any`; and
6. subject to compatibility, make the annotations as precise as possible.

Compatibility takes priority over precision: produce a maximally precise
compatible migration, or any maximal one if several are incomparable.
