# nuprl/typewhich

Extend [TypeWhich](https://github.com/nuprl/TypeWhich) with **prenex
let-polymorphism** (`'a`, schemes on `let` only; λ binders stay monomorphic /
`any`). See `instruction.md` and `environment/Language.md`.

## Environment

- Ubuntu 26.04, system `rustc`/`cargo`
- Z3 **4.8.12** from GitHub release binary
- Clones TypeWhich into `/app/TypeWhich` (not vendored)
- Point programs: `/app/examples/*.gtlc`

## Verifier

Runs migrate on each example; requires exit 0 (soundness via the extended
typechecker) and scores precision against hidden targets in `tests/expected/`.

## Layout

| Path | Role |
|------|------|
| `environment/Dockerfile` | Image + Z3 pin + clone |
| `environment/Language.md` | Extension spec |
| `environment/examples/` | Untyped inputs to migrate |
| `tests/expected/` | Target migrations (verifier only) |
