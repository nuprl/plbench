# nuprl/scheme-typeinf

Invent a **sound** type inference algorithm for MiniScheme. The host is an
OCaml dune project built into `/app/mscheme`. The agent also writes a
metacircular interpreter; typing it (heterogeneous program-as-data) is an
optional hard challenge.

## Layout

| Path | Role |
|------|------|
| `environment/mscheme/` | OCaml MiniScheme (dune) → `/app/mscheme` |
| `instruction.md` | Agent brief |
| `tests/challenges/` | Hidden ok / bad / hard-ok programs |
| `tests/mceval.scm` | Verifier reference metacircular interpreter |
| `tests/test_suite.py` | Grades `/app/typeinf` for soundness |
| `solution/` | Lame oracle (homogeneous lists) + runtime validation |

## Verifier

- `/app/mceval.scm` must implement `(ms-eval …)` / `(ms-initial-env)` (gate).
- `bad-*`: soundness gate — **any** miss → reward **0.0**.
- Score otherwise: **50%** mean(`ok-*`) + **50%** mean(`hard-ok-*`).
- Unsound accept on an `ok-*` / `hard-ok-*` also → **0.0**.
- `hard-ok-*` (5): includes driving / typing the metacircular interpreter.
