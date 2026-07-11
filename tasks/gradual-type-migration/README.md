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
   candidate. We count the type decorations whose complete type is `any` in M
   and E. Thus an annotation of `any` counts once, while the `any` inside an
   annotation such as `any -> int` does not count. We score the candidate as
   `any_count(E) / any_count(M)`. The score is one when the candidate migration
   has exactly as many `any` decorations as E, and lower than one when it has
   more.

   This assumes that E has the minimal number of `any` decorations. If
   `any_count(M) < any_count(E)`, either E is not minimal or the behavioral
   checks are not strong enough. We abort with a verifier error and refuse to
   grade the solution.

As a sanity check, we run (1) and (2) on the expert-vetted migrations
before checking any candidate and abort with a verifier error if they fail.
