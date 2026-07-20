## What Is Provided

Lean 4.

## What You Must Build

Complete the proof in `/app/termination.lean`.

You must not modify `/app/cbv_lc.lean`.

The proof may rely only on `propext`, `Classical.choice`, and `Quot.sound`.

Here is how we expect to run it:

```bash
lean -o cbv_lc.olean cbv_lc.lean
lean -o termination.olean termination.lean
```
