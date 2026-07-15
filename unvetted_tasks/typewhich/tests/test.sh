#!/bin/bash
set -euo pipefail

mkdir -p /logs/verifier
cd /app/TypeWhich

python3 /tests/test_suite.py
