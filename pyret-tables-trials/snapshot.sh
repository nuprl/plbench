#!/bin/bash
# Snapshot a completed Harbor trial's design artifacts + scores into a tracked
# record (the full multi-GB /app artifact stays under the gitignored jobs/).
#   usage: snapshot.sh <trial-label> <path-to-downloaded/app>
set -euo pipefail
LABEL="$1"; APP="$2"
DEST="$(cd "$(dirname "$0")" && pwd)/$LABEL"
PARENT=043ceab4422ac5ad9479650ec1d47d23bd70b3d4
mkdir -p "$DEST/typed-examples"
cp "$APP/DESIGN.md" "$DEST/DESIGN.md"
cp "$APP"/typed-examples/*.arr "$DEST/typed-examples/"
cp "$APP/typecheck-example" "$DEST/typecheck-example"
git -C "$APP/pyret-lang" diff "$PARENT" > "$DEST/changes.diff" 2>/dev/null || echo "(no diff)" > "$DEST/changes.diff"
git -C "$APP/pyret-lang" diff --stat "$PARENT" > "$DEST/changes.stat" 2>/dev/null || true
echo "snapshotted $LABEL -> $DEST"
