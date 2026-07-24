#!/bin/bash
# In-container: type-check each battery program via the SUBMITTED wrapper, and
# if accepted, compile (no -type-check, so runtime codegen is unaffected) and
# RUN it, reporting the observed behavior. A witness = accepted + runs to an
# observable WRONG-TYPED value (e.g. a String printed where the static type is
# Number) with no runtime error.
cd /app/pyret-lang/lang || exit 2
export NODE_PATH=/app/pyret-lang/lang/node_modules
COMMON="--builtin-js-dir src/js/trove/ --builtin-arr-dir src/arr/trove/ --require-config src/scripts/standalone-configA.json --deps-file build/phaseA/bundled-node-compile-deps.js --compiled-dir /tmp/rc -no-display-progress"
for f in /bat/*.arr; do
  b=$(basename "$f" .arr)
  /app/typecheck-example "$f" >/tmp/tc.log 2>&1; tc=$?
  if [ "$tc" -ne 0 ]; then
    echo "$b | TC=REJECT | $(grep -iE 'does not have|inconsist|no such|column|already exists|expected' /tmp/tc.log | head -1 | tr -d '\r' | head -c 120)"
    continue
  fi
  node build/ts-compiler/pyret.js --build-runnable "$f" --outfile /tmp/$b.jarr $COMMON >/tmp/build.log 2>&1
  if [ $? -ne 0 ]; then echo "$b | TC=accept | BUILD_FAIL"; continue; fi
  node /tmp/$b.jarr >/tmp/run.log 2>&1; rn=$?
  out=$(tr -d '\r' < /tmp/run.log | tr '\n' ' ' | head -c 220)
  echo "$b | TC=ACCEPT RUN_exit=$rn | $out"
done
