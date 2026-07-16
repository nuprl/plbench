#!/bin/sh
set -eu

/app/build.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

for source in /app/checked-exception-tests/safe/*.ml; do
  name=$(basename "$source" .ml)
  /usr/local/bin/camlc -o "$tmp/$name" "$source"
  "$tmp/$name"
  echo "PASS safe/$name.ml"
done

for source in /app/checked-exception-tests/does_throw/*.ml; do
  name=$(basename "$source" .ml)
  if /usr/local/bin/camlc -o "$tmp/$name" "$source" >"$tmp/$name.out" 2>&1; then
    echo "FAIL does_throw/$name.ml: compiler accepted an escaping exception" >&2
    exit 1
  fi
  echo "PASS does_throw/$name.ml"
done

