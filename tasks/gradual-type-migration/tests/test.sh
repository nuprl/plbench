#!/bin/bash
set -euo pipefail

mkdir -p /logs/verifier
eval "$(opam env --switch=system)"
cd /tests
dune exec ./verifier.exe
