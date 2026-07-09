#!/bin/bash
# Lame oracle: homogeneous-list typeinf + mceval + host validation of all challenges.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "${SCRIPT_DIR}/typeinf.py" /app/typeinf.py
printf '%s\n' '#!/bin/sh' 'exec python3 /app/typeinf.py "$@"' > /app/typeinf
chmod +x /app/typeinf

cp "${SCRIPT_DIR}/mceval.scm" /app/mceval.scm

# Validate every challenge against the OCaml host (sound programs run;
# unsound programs type-error), and drive the metacircular interpreter.
python3 "${SCRIPT_DIR}/oracle_validate.py"
