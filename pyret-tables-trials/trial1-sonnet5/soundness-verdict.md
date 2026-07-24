# Soundness gate — Trial 1 (Sonnet 5): **NO WITNESS FOUND**

Ran the adversarial battery (type-check **and run**, observing for a wrong-typed
value at a static type). Every schema/sort error is either rejected statically
or produces a clean Pyret runtime domain exception — no type confusion. The
width×add-column/rename collision corner type-checks but raises
`column-name-exists` at runtime (tolerated, not a witness).

Full matrix, adaptations, and raw per-trial output: ../soundness-battery/
(this trial's raw run: ../soundness-battery/results-trial1.txt).

Gate result: **PASS** (soundness gate does not fire).
