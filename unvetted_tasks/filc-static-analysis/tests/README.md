# Verifier

Before grading the submission, the verifier compiles every fixture with Fil-C
in C99 mode and runs it. Every program under `cases/safe` must terminate without
a Fil-C panic or signal. Every program under `cases/does_panic` must terminate
nonzero with a Fil-C panic diagnostic. A corpus mismatch is a verifier error,
and the verifier records no reward.

After corpus validation, each source is copied to a neutral temporary path and
passed to `/app/analyze`:

1. Every `does_panic` case must be classified `MAY PANIC`. Any `SAFE` result
   fails the soundness gate and makes the overall reward zero.
2. The reward is the fraction of `safe` cases classified `SAFE`. Reporting
   `MAY PANIC` for a safe case is permitted but earns no precision credit.

The argument-dependent cases have fixed runtime witnesses in `test_suite.py`.
