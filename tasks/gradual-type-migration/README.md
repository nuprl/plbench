# plbench/gradual-type-migration

Implement safe, compatible, and precise gradual type migration for a
gradually typed lambda calculus. The environment provides a standalone language
specification and an executable reference implementation of the language's
evaluation and syntactic migration relations.

The verifier has several challenge programs `C` to migrate, and we score each
one in several steps. If M is the candidate migration of C, we check that:

1. *M is syntactically more precise than C.* That is, it has exactly the same
   expression structure, including the presence of every ascription, and the
   only differences are in corresponding types. Those types in M must be more
   precise than those in C. In particular, M cannot insert or remove an
   ascription. The reference implementation and language specification make it
   clear exactly what we mean by more precise. If this check fails, the score
   is zero.

2. *M and C are behaviorally equivalent* which we determine with tests. We run
   both M and C in several contexts that test their behavior and expect
   identical outcomes. So if M introduces a more precise type that creates a
   cast error where one didn't occur earlier, it fails the check. If this check
   fails, the score is zero.

3. *Precision check.* We also have an expert-vetted migration E for every
   candidate. A single precision step replaces `any` with `int`, `bool`, or
   `any -> any`, or performs one such refinement inside a function type. For
   example:

   ```text
   any
   => any -> any
   => int -> any
   => int -> int
   ```

   Let `distance(X, Y)` count these pointwise steps from X to the more-precise
   Y. The candidate receives the fraction of the available expert precision
   that it achieves:

   `distance(C, M) / distance(C, E)`

   Before scoring, M must be no more precise than E at every corresponding
   type. If M is more precise than E or incomparable with it, we abort with a
   verifier error: either E is not maximal or the behavioral tests are not
   strong enough.

Each challenge gives equal weight to correctness and precision. A migration
that passes the syntactic and behavioral checks receives one half point plus
one half times its precision fraction. A failing migration receives zero:

`0.5 + 0.5 * distance(C, M) / distance(C, E)`

As a sanity check, we run (1) and (2) on the expert-vetted migrations
before checking any candidate and abort with a verifier error if they fail.
