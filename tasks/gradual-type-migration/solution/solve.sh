#!/bin/bash
set -euo pipefail

cargo build --locked --release --manifest-path /solution/typewhich/Cargo.toml
install -m 755 /solution/typewhich/target/release/typeinf-playground /app/typewhich
install -m 755 /solution/migrate /app/migrate
