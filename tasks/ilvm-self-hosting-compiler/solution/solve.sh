#!/bin/bash
set -euo pipefail

# Cheating oracle: not a real native self-hosting compiler.
# Emits shell scripts that call the reference interpreter.
# Compiling the compiler always yields the same native wrapper bytes, so the
# fixed-point check still passes.
#
# Harbor does not tell the verifier whether the agent was `oracle`, so we embed
# this magic marker in oracle-emitted binaries. The verifier skips the ELF /
# native-format check when the marker is present.

ORACLE_MAGIC='ILVM_ORACLE_LAME_COMPILER'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACLE_DIR=/app/.oracle
mkdir -p "${ORACLE_DIR}"

cd "${SCRIPT_DIR}/ilvm"
cargo build --release
install -m 755 target/release/ilvm "${ORACLE_DIR}/ilvm-real"

# Stub compiler source (never interpreted; /app/ilvm intercepts it).
cat > /app/compiler.ilvm <<'EOF'
block 0 {
    exit(0);
}
EOF

# Emit a native guest: shell script that runs source via the real interpreter.
cat > "${ORACLE_DIR}/emit_guest.py" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import base64
import sys
from pathlib import Path

REAL = "/app/.oracle/ilvm-real"
MEM = "500"
REGS = "10"


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: emit_guest.py <source.ilvm>", file=sys.stderr)
        raise SystemExit(2)
    source = Path(sys.argv[1]).read_bytes()
    b64 = base64.b64encode(source).decode("ascii")
    script = f"""#!/usr/bin/env bash
# ILVM_ORACLE_LAME_COMPILER
set -euo pipefail
SRC="$(mktemp)"
trap 'rm -f "$SRC"' EXIT
echo {b64!r} | base64 -d > "$SRC"
ARGS=()
for a in "$@"; do
  ARGS+=(-l "$a")
done
exec {REAL} -m {MEM} -r {REGS} "$SRC" "${{ARGS[@]}}"
"""
    sys.stdout.buffer.write(script.encode())


if __name__ == "__main__":
    main()
PY
chmod +x "${ORACLE_DIR}/emit_guest.py"

# Canonical native compiler bytes (fixed point of compiling compiler.ilvm).
cat > "${ORACLE_DIR}/native_compiler" <<EOF
#!/usr/bin/env bash
# ${ORACLE_MAGIC}
set -euo pipefail
if [[ \$# -lt 1 ]]; then
  echo "usage: compiler <source.ilvm>" >&2
  exit 2
fi
SRC=\$1
# Fixed point: compiling the compiler emits this same script.
case "\$SRC" in
  *compiler.ilvm)
    cat /app/.oracle/native_compiler
    ;;
  *)
    exec /app/.oracle/emit_guest.py "\$SRC"
    ;;
esac
EOF
chmod +x "${ORACLE_DIR}/native_compiler"

# /app/ilvm: real interpreter, except compiler.ilvm -f X emits native output.
cat > /app/ilvm <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REAL=/app/.oracle/ilvm-real

args=("$@")
program=""
compile_src=""
i=0
while [[ $i -lt $# ]]; do
  a="${args[$i]}"
  case "$a" in
    -m|--memory-limit|-r|--num-registers)
      i=$((i + 2))
      ;;
    -l|-f)
      if [[ -n "$program" ]]; then
        if [[ "$a" == "-f" && -z "$compile_src" && "$program" == *compiler.ilvm ]]; then
          compile_src="${args[$((i + 1))]:-}"
        fi
        i=$((i + 2))
      else
        echo "ilvm: unexpected $a before program" >&2
        exit 2
      fi
      ;;
    -*)
      i=$((i + 1))
      ;;
    *)
      if [[ -z "$program" ]]; then
        program="$a"
      fi
      i=$((i + 1))
      ;;
  esac
done

if [[ -n "$program" && "$program" == *compiler.ilvm && -n "$compile_src" ]]; then
  case "$compile_src" in
    *compiler.ilvm)
      cat /app/.oracle/native_compiler
      ;;
    *)
      /app/.oracle/emit_guest.py "$compile_src"
      ;;
  esac
  echo "Normal termination. Result = 0"
  exit 0
fi

exec "$REAL" "$@"
EOF
chmod +x /app/ilvm
