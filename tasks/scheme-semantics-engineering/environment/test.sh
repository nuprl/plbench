#!/bin/bash
set -euo pipefail

cd /app
lean -o Semantics.olean Semantics.lean
lean --run TestRunner.lean "${1:-/app/example-test}" \
  > /tmp/scheme-semantics-example-output.txt
diff -u "${1:-/app/example-test}/expected.txt" \
  /tmp/scheme-semantics-example-output.txt
echo "example test passed"
