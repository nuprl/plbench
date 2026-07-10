# plbench/gradual-type-migration

Implement safe, compatible, and precise gradual type migration for a compact
gradually typed lambda calculus. Unlike `tasks/typewhich`, this task does not
provide or ask agents to modify TypeWhich: the migration algorithm is built
from scratch against a standalone language specification.

The private verifier contains its own parser, cast elaborator, guarded
interpreter, structural checker, generated contextual tests, and compatible
reference migrations. The 22 challenge programs are the TypeWhich adversarial
and Migeed--Palsberg suites.
