"""Verify the submitted Lean termination proof."""

import hashlib
from pathlib import Path
import re
import subprocess


def main() -> None:
    """Run the verifier's grading path and award success."""
    reward = Path("/logs/verifier/reward.txt")

    # Missing or modified submission artifacts receive no reward.
    if not Path("termination.lean").is_file():
        print("Missing /app/termination.lean")
        reward.write_text("0\n")
        return
    if (
        hashlib.md5(Path("cbv_lc.lean").read_bytes()).hexdigest()
        != "7545610e8e8c7f243cc05b05502f2de5"
    ):
        print("The trusted /app/cbv_lc.lean file was modified")
        reward.write_text("0\n")
        return

    # Build the trusted module and submitted proof.
    subprocess.run(
        ["lean", "-o", "cbv_lc.olean", "cbv_lc.lean"], check=True
    )
    if subprocess.run(
        ["lean", "-o", "termination.olean", "termination.lean"]
    ).returncode != 0:
        reward.write_text("0\n")
        return

    # Check the theorem's type and inspect its axiom dependencies.
    check = subprocess.run(
        ["lean", "/tests/Check.lean"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(check.stdout)
    if check.returncode != 0:
        reward.write_text("0\n")
        return

    if "'termination' does not depend on any axioms" in check.stdout:
        axioms = set()
    elif match := re.search(
        r"'termination' depends on axioms: \[(.*?)\]", check.stdout
    ):
        axioms = {name.strip() for name in match.group(1).split(",") if name.strip()}
    else:
        raise RuntimeError("Lean did not report the axioms of termination")

    if not axioms <= {"propext", "Classical.choice", "Quot.sound"}:
        reward.write_text("0\n")
        return

    reward.write_text("1\n")


if __name__ == "__main__":
    main()
