#!/usr/bin/env python3
"""Oracle adapter: emit the trusted compatible migration for a challenge."""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: migrate FILE.gtlc", file=sys.stderr)
        return 2
    name = Path(sys.argv[1]).name
    expected = Path("/tests/expected") / name
    if not expected.is_file():
        print(f"no oracle migration for {name}", file=sys.stderr)
        return 1
    sys.stdout.write(expected.read_text())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
