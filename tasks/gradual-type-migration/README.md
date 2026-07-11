# plbench/gradual-type-migration

Implement safe, compatible, and precise gradual type migration for a compact
gradually typed lambda calculus. The environment provides a standalone language
specification and an executable reference implementation of the language's
evaluation and syntactic migration relations.

The private verifier is an OCaml/Dune project with an ocamllex lexer, Menhir
parser, gradual semantics, and migration-precision checker. One typed YAML
document contains the challenge programs, optional TypeWhich witness contexts,
and curated maximally precise compatible migrations. A submission must
type-check and lie below at least one compatible maximum; no reference tool is
run during grading. The 22 challenge programs are the TypeWhich adversarial and
Migeed--Palsberg suites.
