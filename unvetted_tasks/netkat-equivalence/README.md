# History-sensitive NetKAT equivalence

This task asks for a decision procedure for equivalence of NetKAT terms with
packet histories. It is based on *A Coalgebraic Decision Procedure for
NetKAT* by Foster, Kozen, Milano, Silva, and Thompson (POPL 2015), which uses
specialized Brzozowski derivatives and bisimulation to decide the equational
theory.

The surface language retains the four fixed, naturally typed headers from the
reachability task, but restores `dup`. A program therefore denotes a function
from nonempty packet histories to sets of packet histories. Two terms are
equivalent only when those functions agree for every history; matching the
same endpoint relation is insufficient.

There is no oracle or reference implementation. Every fixture under
`tests/cases` documents the intended equation, path behavior, and expected
result. The OCaml verifier discovers all fixtures and scores their properties
independently. The suite includes NetKAT axioms and applications adapted from
the paper as well as adversarial history and iteration cases.

Paper: <https://www.cs.cornell.edu/~jnfoster/papers/netkat-coalgebra.pdf>

DOI: <https://doi.org/10.1145/2676726.2677011>
