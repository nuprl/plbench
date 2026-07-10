#!/bin/bash
set -euo pipefail

mkdir -p /logs/verifier
eval "$(opam env --switch=system)"

# Build our own reference ILVM implementation. This never runs (and never gets
# built) during the agent's own working time — it only exists for grading, and
# the agent is never shown it.
cd /tests/ilvm_ref
dune runtest
dune build --profile release src/main.exe
cp _build/default/src/main.exe ilvm
cd -

# Build the trusted MiniScheme interpreter from its Dune project. Its lexer and
# parser remain generated from the checked-in ocamllex/ocamlyacc sources.
cd /tests/minischeme_ref
dune build --profile release main.exe
cp _build/default/main.exe minischeme
cd -

# test_suite.py writes /logs/verifier/reward.txt itself on every normal
# scoring outcome, and deliberately does NOT write it (raising instead) if
# a fixture/reference-implementation problem is detected — that should
# surface as a verifier error, not a silent 0 score against the agent.
python3 /tests/test_suite.py
