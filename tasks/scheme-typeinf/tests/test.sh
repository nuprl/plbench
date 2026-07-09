#!/bin/bash
set -euo pipefail

mkdir -p /logs/verifier

# The verifier supplies its own metacircular interpreter to drive the
# hard-ok mceval challenges and hard-ok-05 (typing mceval.scm itself) —
# agents are not expected to write one.
cp /tests/mceval.scm /app/mceval.scm

python3 /tests/test_suite.py
