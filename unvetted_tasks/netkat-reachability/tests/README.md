# Reachability fixture audit guide

The verifier discovers every `.nk` file in this directory's `cases`
subdirectory. Each fixture is paired with a same-stem `.expected` file. The
fixture comments are part of the audit record: they describe the network,
policy, topology, and every named property. The OCaml verifier refuses to grade
a fixture when one of those descriptions is missing.

The 17 networks and 89 properties cover:

| Case | Main semantic obligation |
| --- | --- |
| `01-zero-hop` | Reflexivity over the full `2^96` universe, even when both components drop |
| `02-two-switch` | Web filtering and public-to-private destination delivery |
| `03-disconnected` | Disconnected address realms and existential source predicates |
| `04-ecmp` | Nondeterministic forwarding union |
| `05-firewall` | Source- and port-sensitive filtering |
| `06-header-rewrite` | Source NAT and preservation of unrelated headers |
| `07-multihop-line` | Transitive address reachability over several outer iterations |
| `08-cycle-and-exit` | Cycles, termination, and an optional exit |
| `09-boolean-predicates` | Negation, conjunction, disjunction, and empty predicates |
| `10-sequence-order` | Left-to-right relational composition |
| `11-policy-internal-star` | Reflexive-transitive closure nested inside policy |
| `12-directed-topology` | Directed physical links |
| `13-nondeterministic-rewrite` | Nondeterministic port-address translation and `drop` |
| `14-tenant-isolation` | Source-based backend isolation |
| `15-load-balancer` | Nondeterministic destinations with header rewriting |
| `16-policy-topology-alternation` | Atomic outer `policy . topology` boundaries |
| `17-topology-internal-star` | Reflexive-transitive closure nested inside topology |

Expected results are literal audit data, not outputs produced by a reference
checker. Positive and negative properties are intentionally interleaved so a
constant-answer submission earns little credit.
