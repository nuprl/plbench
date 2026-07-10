# Finite NetKAT reachability language

## Command line

Your program must be executable as:

```text
/app/netkat-reach INPUT.nk
```

For a valid input, print one line for every `check`, in source order:

```text
CHECK_NAME: reachable
CHECK_NAME: unreachable
```

Print no other text to standard output and exit with status 0. Diagnostics may
go to standard error. For an invalid input, exit nonzero. The grading inputs
are valid.

## Headers and lexical syntax

Every packet has exactly these four headers:

```text
src_ip    source IPv4 address
dst_ip    destination IPv4 address
src_port  source transport port
dst_port  destination transport port
```

Inputs do not declare headers or their domains. An IPv4 value is written in
canonical dotted-decimal notation, with four decimal octets from 0 through
255, for example `192.0.2.17`. An octet has no leading zero unless it is zero.
A port value is a decimal integer from 0 through 65535, also without leading
zeros unless it is zero.

Whitespace is insignificant. A `#` begins a comment extending to the end of
the line. Check names match `[A-Za-z_][A-Za-z0-9_-]*`. The words and header
names appearing in the grammar are reserved.

## Grammar

The notation `{ x }` means zero or more repetitions of `x`. Alternatives are
separated by `|`. Operators are listed from low to high precedence.

```text
program     ::= policy_decl topology_decl check { check }
policy_decl ::= "policy" "=" policy ";"
topology_decl
            ::= "topology" "=" policy ";"
check       ::= "check" IDENT ":" predicate "=>" predicate ";"

policy      ::= sequence { "+" sequence }
sequence    ::= repetition { "." repetition }
repetition  ::= policy_atom { "*" }
policy_atom ::= "drop"
              | "id"
              | "filter" "(" predicate ")"
              | header "<-" value
              | "(" policy ")"

predicate   ::= conjunction { "|" conjunction }
conjunction ::= negation { "&" negation }
negation    ::= "!" negation | predicate_atom
predicate_atom
            ::= "true"
              | "false"
              | header "=" value
              | "(" predicate ")"
header      ::= "src_ip" | "dst_ip" | "src_port" | "dst_port"
value       ::= IPV4 | PORT
```

Thus `*` binds tightest in policies, then `.`, then `+`. In predicates, `!`
binds tightest, then `&`, then `|`. All binary operators associate to the left,
although their denotations are associative. Parentheses may be used freely.

An IP header may only be compared with or assigned an IPv4 value. A port header
may only be compared with or assigned a port value. There is exactly one
`policy` declaration, one `topology` declaration, at least one `check`, and
check names are distinct.

## Packet space and predicates

A packet is a tuple in the fixed packet space:

```text
IPv4 × IPv4 × Port16 × Port16
```

where `IPv4 = {0, ..., 2^32-1}` and `Port16 = {0, ..., 65535}`. Thus the
packet space contains exactly `2^96` packets. Predicates denote subsets of this
entire space:

- `true` accepts every packet and `false` accepts none.
- `h = v` accepts a packet exactly when its value for header `h` is `v`.
- `!a`, `a & b`, and `a | b` denote complement, intersection, and union,
  respectively, relative to the full `2^96` packet space.

## Policies

A policy denotes a relation from input packets to output packets, or
equivalently a function from a packet to a set of packets:

- `drop` produces no output packet.
- `id` produces its input packet unchanged.
- `filter(a)` produces its input unchanged if predicate `a` accepts it, and no
  packet otherwise.
- `h <- v` produces one packet, obtained by changing header `h` to `v` and
  leaving all other headers unchanged.
- `p + q` is nondeterministic union: it produces every output of either branch.
- `p . q` is relational composition: run `p`, then run `q` on every packet
  produced by `p`.
- `p*` is reflexive-transitive closure: run `p` zero or more times. It produces
  every packet reachable from the input through any finite number of `p`
  steps, including the unchanged input packet.

Outputs are sets. Duplicate ways to produce the same packet have no observable
effect. `policy` and `topology` have exactly the same policy language and
semantics; their separate declarations expose the two components used by the
reachability definition.

## Reachability checks

For a declaration:

```text
check name: a => b;
```

print `name: reachable` if and only if there exist packets `pk_start` and
`pk_end` such that:

1. `a` accepts `pk_start`;
2. `pk_end` can be produced from `pk_start` by zero or more repetitions of
   `policy . topology`; and
3. `b` accepts `pk_end`.

Otherwise print `name: unreachable`.

This is the finite, dup-free instance of the NetKAT paper's condition

```text
a · dup · (p · t · dup)* · b != 0
```

where `p` is `policy` and `t` is `topology`. `dup` records the current packet
in its history but does not change it, so it does not appear as a surface
operator here. The outer repetition is reflexive: if one packet satisfies both
`a` and `b`, the check is reachable even when `policy . topology` is `drop`.
