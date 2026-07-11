#!/bin/bash
set -euo pipefail

cargo build --locked --release --manifest-path /solution/typewhich/Cargo.toml
ln -sfn /solution/migrate /app/migrate
