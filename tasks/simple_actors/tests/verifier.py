#!/usr/bin/env python3
"""Run the simple-actors behavioral suite and emit a binary reward."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SUBMISSION = Path("/app/actor.py")
TEST_SUITE = Path("/tests/test_actor.py")
REWARD = Path("/logs/verifier/reward.txt")


def run_tests() -> subprocess.CompletedProcess[str]:
    """Run pytest with the submission directory first on Python's import path."""

    environment = os.environ.copy()
    existing_path = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = (
        f"/app:{existing_path}" if existing_path else "/app"
    )
    return subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "-q",
            "-p",
            "no:cacheprovider",
            str(TEST_SUITE),
        ],
        cwd="/app",
        env=environment,
        capture_output=True,
        text=True,
        timeout=150,
    )


def main() -> None:
    """Validate the artifact, run the tests, and write an all-or-nothing score."""

    if not SUBMISSION.is_file():
        raise FileNotFoundError("the agent must create /app/actor.py")

    try:
        result = run_tests()
    except subprocess.TimeoutExpired as error:
        print(error.stdout or "", end="")
        print(error.stderr or "", end="", file=sys.stderr)
        print("pytest timed out after 150 seconds", file=sys.stderr)
        REWARD.write_text("0\n", encoding="utf-8")
        return

    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    REWARD.write_text("1\n" if result.returncode == 0 else "0\n", encoding="utf-8")


if __name__ == "__main__":
    main()
