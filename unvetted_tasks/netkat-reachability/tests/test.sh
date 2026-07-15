#!/bin/bash
set -euo pipefail

mkdir -p /logs/verifier
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

cp /tests/verifier.ml "$build_dir/verifier.ml"
(
  cd "$build_dir"
  ocamlc -I +unix -I +str -o verifier unix.cma str.cma verifier.ml
)
"$build_dir/verifier"
