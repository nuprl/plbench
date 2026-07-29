# Scheme Semantics Engineering

Formalize the supplied Mini-Scheme in Lean using the shared
`SemanticsTemplate.Development` interface. The artifact supplies independent
inductive static and small-step semantics, a pure fuel-bounded interpreter,
and proofs of progress, preservation, and interpreter correspondence.

`environment/example-semantics` is a complete worked MiniML example of the
same architecture. The deterministic verifier compiles the submitted
development against the immutable template and compares static acceptance and
observable standard output with the supplied Mini-Scheme implementation. The
environment exposes the verifier's hash-checked `TestRunner.lean`, its exact
build script, and one example case; the verifier runs that same Lean program on
the held-out case directory.
RewardKit separately inspects the declarative semantics and proofs for the
required semantic independence and quality.

This task intentionally has no oracle solution.
