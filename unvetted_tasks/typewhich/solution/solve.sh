#!/bin/bash
# No reference FO-poly implementation. Oracle only confirms the stock tree builds.
set -euo pipefail
cd /app/TypeWhich
cargo build
