# Pyret typed-tables — validation trial records

Lightweight records of the Harbor trials run while packaging this task (design
report, typed examples, compiler diff, and scores). The full multi-GB `/app`
artifacts live under the gitignored `jobs/` tree on the run host.

- `trial1-sonnet5/` — Claude Code + Sonnet 5, high effort (pre-hardening verifier; SOUND per full audit).
- `trial2-sonnet5/` — Claude Code + Sonnet 5, high effort (hardened verifier).
- `trial3-opus48/`  — Claude Code + Opus 4.8, high effort (hardened verifier).
- `COMPARISON.md`   — comparative design analysis across the three trials.
