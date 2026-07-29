#!/bin/bash
set -euo pipefail

export PYTHONPATH="/tests${PYTHONPATH:+:$PYTHONPATH}"
python3 /tests/prepare_audit.py

if [[ -n "${CODEX_AUTH_JSON:-}" ]]; then
    REWARDKIT_CODEX_DIR=/tmp/rewardkit-codex-home
    install -d -m 700 "$REWARDKIT_CODEX_DIR"
    printf '%s' "$CODEX_AUTH_JSON" > "$REWARDKIT_CODEX_DIR/auth.json"
    chmod 600 "$REWARDKIT_CODEX_DIR/auth.json"
    unset CODEX_ACCESS_TOKEN
    CODEX_HOME="$REWARDKIT_CODEX_DIR" exec uvx --from 'harbor-rewardkit==0.1.*' rewardkit /tests
fi

exec uvx --from 'harbor-rewardkit==0.1.*' rewardkit /tests
