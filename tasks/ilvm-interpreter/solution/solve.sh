#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/ilvm"

cd "${SRC}"
cargo build --release
install -m 755 target/release/ilvm /app/ilvm
