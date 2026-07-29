## Objective

The goal of this task is "semantics engineering". You will examine a
programming language implementation, and from it deduce how to write:
a reference interpreter, a small-step operational semantics, and its static
semantics (i.e., type system and/or well-formedness criterion). You will prove
that the reference interpreter is a faithful implementation of the semantics
and that the static semantics is sound with respect to the small-step semantics.
I have a held-out test suite that I will use to determine if your reference
interpreter is faithful to the provided implementation, but you will have to
determine faithfulness yourself (i.e., by writing your own tests).

You will be writing code and proofs in Lean 4. We'll describe what is expected
in more detail below, and provide a worked example.

## What Is Provided

**You must not edit any provided files or install any packages.**

We have installed Lean 4. The programming language implementation that you will
target is a mini-Scheme. It is described in /app/MiniScheme.md, its source code
(in OCaml) is in /app/minischeme-reference, a prebuilt executable is in
/app/minischeme-reference/_build/default/main.exe. In case of any ambiguity in
the description, the implementation is authoritative. Use the command
`/app/minischeme-reference/_build/default/main.exe PROGRAM` to run a
program. It first performs static checks to ensure the program is well-formed.
Add the `--check` flag to perform static checks without running the program.

The directory /example has a complete worked example of semantics engineering.
In that directory, you will find:

- /example/impl: the implementation of a programming language (a mini-ML)
- /example/examples: a few example programs
- /example/Semantics.lean: the small-step semantics, reference interpreter, and
  required proofs. This is the kind of work you will do for the target language.

The file /app/SemanticsTemplate.lean defines the theorems you need to prove
and the format in which you must prove them. /example/Semantics.lean imports
this file, and you will too.

The file /app/TestRunner.lean is the exact runner that we will use to test your
code. You can run it with `/app/test.sh`. The verifier will run test runner
using a similar script.

## What You Must Build

Create a file called /app/Semantics.lean to do the semantics engineering
task for the target language. Your solution must have this form:

```lean
import SemanticsTemplate

  ...

def development : SemanticsTemplate.Development where
  ...
```

`TestRunner.lean` supplies the executable `main`, so `/app/Semantics.lean` must
not define a root `main`. You must test that your interpreter is faithful to
the provided target implementation. You are permitted to deviate from the
implementation in only these ways:

1. You do not need to support language-level input facilities such as standard
   input or file reads.
2. The only output that you need to support is standard output, as described
   in SemanticsTemplate.lean.

I will run several held-out tests to determine if your reference interpreter
is faithful to the provided implementation (with the exceptions listed above).
In addition, I will judge your work with the following criteria:

1. Your Lean code can only rely on `propext`, `Classical.choice`, and
   `Quot.sound` as axioms. Using sorry, admit, etc. is unacceptable.
2. Any change to SemanticsTemplate.lean or the reference implementation is
   unacceptable.
3. `Step` must be an independently defined inductive one-step relation over
   `State`. `WellFormed` must be an independent Prop-valued static judgment,
   defined either inductively itself or directly from independently inductive
   typing or well-formedness judgments. These relations must not refer to the
   reference implementations. For example, it is unacceptable for `Step` to
   refer to the `interpret` function.
