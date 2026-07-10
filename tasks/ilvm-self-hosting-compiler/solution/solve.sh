#!/bin/bash
set -euo pipefail

# Oracle: a real MiniScheme-to-ILVM compiler, but written in Python, not in
# MiniScheme -- i.e. not self-hosting. See README.md for why, and
# tests/test_suite.py for how the verifier grades this honestly (the
# ORACLE_MARKER in compiler.scm routes correctness grading through the
# fallback compiler below. Compiling the aborting stub still fails the
# self-hosted pass, so the oracle receives no self-hosting credit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "${SCRIPT_DIR}/compiler.scm" /app/compiler.scm
cp "${SCRIPT_DIR}/compile_scheme_to_ilvm.py" /app/.oracle_fallback_compiler.py
