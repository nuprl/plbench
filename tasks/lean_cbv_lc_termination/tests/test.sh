#!/bin/bash
set -euo pipefail

cd /app
exec python3 /tests/test.py
