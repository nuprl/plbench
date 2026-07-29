# Verifier

The verifier hash-checks the canonical `SemanticsTemplate.lean`, the worked
example, the Mini-Scheme specification, and the supplied OCaml source. It
rebuilds the reference executable from the verified source in a fixed work
directory.

The deterministic grading path in `verifier.py` copies the trusted template and
the submitted Lean dependency closure into a clean directory, compiles the
template first, and then compiles the submission. A trusted Lean inspector
dynamically loads the result and requires this top-level declaration:

```lean
development : SemanticsTemplate.Development
```

The submitted module must not define a root `main`. The hash-checked
`/app/TestRunner.lean` supplies `main`, takes a case directory, uses a fixed
fuel value of `500000`, and is the same runner exposed to the solver with one
visible test.

It rejects `sorry` and `admit` in submitted dependencies and recursively checks
that `development` relies only on `propext`, `Classical.choice`, and
`Quot.sound` as axioms. Because every required definition and theorem is a
field of `Development`, checking the type and axiom closure of this value checks
the complete formal contract without requiring language-specific declaration
names.

The trusted runner calls `development.parse`, `development.initial`, and
`development.interpret` on every `.scm` file in the held-out directory. The
verifier compares static
acceptance/rejection and exact standard-output strings with a clean rebuild of
the supplied Mini-Scheme checker/interpreter. Parse and static failures are both
rejections at the template boundary; statically accepted executions must
terminate within the verifier's fuel bound, including executions ending in a
dynamic error.

RewardKit separately inspects all submitted Lean sources for the qualitative
requirements that are not reducible to the structure's Lean type: independent
inductive static judgments, an independent inductive one-step relation,
meaningful well-formedness and metatheory, faithful language coverage, and
non-circular interpreter correspondence. A directly recursive big-step-style
interpreter is allowed and need not expose a one-transition executable helper.
