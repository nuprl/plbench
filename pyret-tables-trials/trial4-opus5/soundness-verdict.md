# Soundness gate — Trial 4 (Opus 5): **NO WITNESS FOUND**

Ran the adversarial battery (type-check **and run**, observing for a wrong-typed
value at a static type). **All 15 probes are rejected statically** — no program
type-checks under `/app/typecheck-example`, so nothing reaches runtime and no
wrong-typed value can be observed. A witness is impossible where nothing is
accepted.

This is the most statically precise result of the cohort. The three probes the
prior trials could only catch at **runtime** — the width×freshness collision
corner (`W2` add-column onto a hidden column, `W3` rename onto a hidden column)
and `stack` across mismatched schemas (`F4`) — are all rejected **at
type-check time** here. The reason is architectural: this design uses **exact
schemas with names and column order invariant** (subtyping only widens cell
*sorts*, never the column set) plus a `NewColumn<S,C>` freshness constraint,
rather than the width subtyping the other three chose. Because
`Table<{a :: Number, b :: String}>` is *not* a subtype of `Table<{a :: Number}>`,
`W2`/`W3` — which smuggle a colliding `b` column past a one-column parameter via
width subtyping — never type-check in the first place, so the collision cannot
even reach the tolerated runtime `column-name-exists` path it took in Trials 1–3.

`F1`/`F2` (select/drop existence recovery) also reject statically, where Trials
2/3 accepted them and deferred to a runtime "no such column" error.

Full matrix, adaptations, and raw per-trial output: ../soundness-battery/
(this trial's raw run: ../soundness-battery/results-trial4.txt).

Gate result: **PASS** (soundness gate does not fire).
