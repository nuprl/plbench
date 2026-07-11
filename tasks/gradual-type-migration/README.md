# plbench/gradual-type-migration

Implement safe, compatible, and precise gradual type migration for a compact
gradually typed lambda calculus. The environment provides a standalone language
specification and an executable reference implementation of the language's
evaluation and syntactic migration relations.

The private verifier is a small OCaml/Dune project. It authenticates the
reference executable, uses its syntactic migration check, and compares the
original and migrated programs in documented closing contexts. One typed YAML
document contains the 22 TypeWhich adversarial and Migeed--Palsberg challenge
programs, the TypeWhich oracle outputs, and the contexts.
