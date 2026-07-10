Your task is to write a self-hosting compiler from MiniScheme to ILVM.

## What Is Provided

MiniScheme is specified in `/app/Scheme.md`; ILVM is specified in
`/app/ILVM.md`. No implementation of either language is available during your
work. Python, OCaml, and Rust are installed if you want to build development
tools of your own. Those tools are not graded.

## What You Must Build

Write a MiniScheme to ILVM compiler in MiniScheme and save it as
`/app/compiler.scm`. This program must receive exactly one command-line
argument: the complete source text of another MiniScheme program. It must
`display` the complete source text of an equivalent ILVM program and no other
output.

Ensure the compiler implements MiniScheme correctly. Take care to translate
errors to ILVM's `abort;` instruction, but print the appropriate error message
before aborting.

We will evaluate your program on several progressively harder test cases,
culminating in a self-hosting test. However, there is no byte-for-byte
fixed-point requirement: the compiler produced by self-compilation only needs to
compile programs correctly.
