#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR=${APP_DIR:-/app}

if [[ ! -f "$APP_DIR/chibicc/Makefile" ]]; then
  echo "missing base chibicc source tree at $APP_DIR/chibicc" >&2
  exit 1
fi

git -C "$APP_DIR/chibicc" apply --check "$SCRIPT_DIR/chibicc.patch"
git -C "$APP_DIR/chibicc" apply "$SCRIPT_DIR/chibicc.patch"
make -C "$APP_DIR/chibicc" clean >/dev/null 2>&1 || true
make -C "$APP_DIR/chibicc" -j"$(nproc)"

install -m 0644 "$SCRIPT_DIR/runtime.c" "$APP_DIR/runtime.c"
gcc -std=gnu11 -O2 -g -fno-omit-frame-pointer -c \
  "$APP_DIR/runtime.c" -o "$APP_DIR/runtime.o"
install -m 0755 "$SCRIPT_DIR/safec" "$APP_DIR/safec"
