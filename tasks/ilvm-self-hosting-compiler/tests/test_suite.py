#!/usr/bin/env python3
"""Grade /app/compiler.scm + /app/compiler.ilvm: a self-hosting MiniScheme-to-
ILVM compiler.

We grade against our OWN reference ILVM implementation (tests/ilvm_ref,
built by test.sh before this runs), never the agent's own ILVM tooling — the
agent is never shown this implementation. This decouples "is the compiler
correct" from "is the agent's own ILVM interpreter correct."

Two independent sub-scores, each averaged over tests/examples/*.scm:

  correctness:   compiling with compiler.ilvm and running the result
                 produces the expected output (EXPECTED below — a ground
                 truth computed independently of any agent artifact).
  self_hosting:  compiler.ilvm recompiles compiler.scm into compiler2.ilvm;
                 compiling+running each example with compiler.ilvm and with
                 compiler2.ilvm must produce identical, successful results.

reward = 0.5 * correctness + 0.5 * self_hosting. No hard gate zeroes the
whole score on one failure — the example battery mixes easy and hard
programs so partial credit is informative.

--- The one, clearly-documented oracle escape hatch ---

Our own bundled oracle (solution/) is NOT self-hosting: it's a real
compiler, but written in Python, not in MiniScheme (see README.md for why).
To grade honestly instead of faking a fake compiler.ilvm, compiler.scm
carries a long, non-guessable marker string (ORACLE_MARKER below). If a
submission's compiler.scm contains that exact marker:
  - self_hosting is scored 0.0 outright (not skipped, not free credit —
    this submission has admitted it isn't self-hosting).
  - correctness is graded by invoking FALLBACK_COMPILER (a real compiler
    dropped next to it by solve.sh, at a fixed path under /app) instead of
    running compiler.ilvm.
This is the ONLY special-cased branch in this file; there is no other path
by which compiler.ilvm is bypassed. See README.md for the associated risk
(a real agent that discovers this exact string gets the oracle's
correctness score for free) and why we accepted it anyway.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ILVM_REF = Path("/tests/ilvm_ref/target/release/ilvm")
COMPILER_SCM = Path("/app/compiler.scm")
COMPILER_ILVM = Path("/app/compiler.ilvm")
FALLBACK_COMPILER = Path("/app/.oracle_fallback_compiler.py")
EXAMPLES = Path("/tests/examples")
REWARD = Path("/logs/verifier/reward.txt")

MEM = "4000000"
REGS = "64"

STATUS_RE = re.compile(r"^Normal termination\. Result = -?\d+$")

ORACLE_MARKER = "ORACLE-NOT-SELF-HOSTING-7f3ac9e1d4b8407e9c2a1f6e5d0b8c33"

# Hand-verified against environment/Scheme.md's semantics — independent of
# anything the agent produced. Each display call terminates its output with a
# newline.
EXPECTED = {
    "01-arith.scm": "12\n",
    "02-factorial.scm": "120\n",
    "03-fibonacci.scm": "55\n",
    "04-list-sum.scm": "15\n",
    "05-strings.scm": "hello, world\n",
    "06-classify.scm": "negative\nzero\npositive\n",
    "07-closures-map.scm": "30\n",
    "08-let.scm": "31\n",
    "09-letrec-mutual.scm": "t\n",
    "10-vector.scm": "20\n",
}


class VerifierError(Exception):
    """A verifier-side problem (missing reference implementation, broken
    fixture) — not something to hold against the agent."""


def strip_status(stdout: str) -> str:
    """Remove the reference implementation's own trailing status line
    ("Normal termination. Result = N"), recovering the program's own
    print/print_str output."""
    body = stdout[:-1] if stdout.endswith("\n") else stdout
    head, _, last = body.rpartition("\n")
    if STATUS_RE.match(last):
        return head + "\n" if head else ""
    return stdout


def run_ilvm(program_text: str, arg: str | None, timeout: float) -> tuple[bool, str]:
    """Run program_text under the reference ILVM implementation, optionally
    with one command-line argument. Returns (succeeded, own_stdout)."""
    with tempfile.NamedTemporaryFile("w", suffix=".ilvm", delete=False) as f:
        f.write(program_text)
        prog_path = f.name
    try:
        cmd = [str(ILVM_REF), "-m", MEM, "-r", REGS, prog_path]
        if arg is not None:
            cmd += ["-l", arg]
        try:
            completed = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return False, ""
    finally:
        Path(prog_path).unlink(missing_ok=True)
    if completed.returncode != 0:
        return False, ""
    return True, strip_status(completed.stdout)


def compile_with(compiler_ilvm_text: str, source_text: str) -> tuple[bool, str]:
    """Run a compiler (as ILVM source text) on source_text; returns
    (succeeded, compiled_ilvm_text)."""
    return run_ilvm(compiler_ilvm_text, source_text, timeout=60)


def compile_with_fallback(source_text: str) -> tuple[bool, str]:
    """Compile source_text using the oracle's real (non-self-hosting)
    Python compiler, invoked as an external process."""
    try:
        completed = subprocess.run(
            [sys.executable, str(FALLBACK_COMPILER)],
            input=source_text,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return False, ""
    if completed.returncode != 0:
        return False, ""
    return True, completed.stdout


def write_reward(reward: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{reward:.6f}\n")


def main() -> int:
    if not ILVM_REF.is_file():
        raise VerifierError(f"reference ILVM implementation not built at {ILVM_REF}")

    if not COMPILER_SCM.is_file():
        print("missing /app/compiler.scm", file=sys.stderr)
        write_reward(0.0)
        return 1
    if not COMPILER_ILVM.is_file():
        print("missing /app/compiler.ilvm", file=sys.stderr)
        write_reward(0.0)
        return 1

    examples = sorted(EXAMPLES.glob("*.scm"))
    if not examples:
        raise VerifierError("no example programs found under /tests/examples")
    missing_expected = [p.name for p in examples if p.name not in EXPECTED]
    if missing_expected:
        raise VerifierError(f"no EXPECTED entry for: {missing_expected}")

    compiler_scm_text = COMPILER_SCM.read_text()
    is_oracle = ORACLE_MARKER in compiler_scm_text

    if is_oracle:
        print("=== ORACLE_MARKER found in compiler.scm ===")
        print("This submission admits it is not self-hosting.")
        print("self_hosting is scored 0.0; correctness is graded via the")
        print(f"fallback compiler at {FALLBACK_COMPILER}, not compiler.ilvm.")
        if not FALLBACK_COMPILER.is_file():
            raise VerifierError(
                f"ORACLE_MARKER present but {FALLBACK_COMPILER} is missing"
            )

        correctness_scores: list[float] = []
        print("=== per-example results (fallback compiler) ===")
        for path in examples:
            name = path.name
            source = path.read_text()
            expected = EXPECTED[name]
            ok1, out1_ilvm = compile_with_fallback(source)
            ran1, actual1 = run_ilvm(out1_ilvm, None, timeout=30) if ok1 else (False, "")
            correct = ran1 and actual1 == expected
            correctness_scores.append(1.0 if correct else 0.0)
            print(f"{name}: correctness={'PASS' if correct else 'FAIL'}")
            if not correct:
                print(f"  compiled ok={ok1} ran ok={ran1} expected={expected!r} actual={actual1!r}")

        correctness = sum(correctness_scores) / len(correctness_scores)
        self_hosting = 0.0
        reward = 0.5 * correctness + 0.5 * self_hosting
        print(f"correctness={correctness:.4f} self_hosting={self_hosting:.4f} reward={reward:.4f}")
        write_reward(reward)
        return 0

    compiler_ilvm_text = COMPILER_ILVM.read_text()

    print("=== self-hosting fixed point: compiling compiler.scm with compiler.ilvm ===")
    ok2, compiler2_ilvm_text = compile_with(compiler_ilvm_text, compiler_scm_text)
    if ok2:
        print("compiler.ilvm compiled compiler.scm successfully -> compiler2.ilvm")
    else:
        print("compiler.ilvm FAILED to compile compiler.scm -- every self-hosting case below will fail")

    correctness_scores = []
    self_hosting_scores: list[float] = []

    print("=== per-example results ===")
    for path in examples:
        name = path.name
        source = path.read_text()
        expected = EXPECTED[name]

        ok1, out1_ilvm = compile_with(compiler_ilvm_text, source)
        ran1, actual1 = run_ilvm(out1_ilvm, None, timeout=30) if ok1 else (False, "")

        correct = ran1 and actual1 == expected
        correctness_scores.append(1.0 if correct else 0.0)

        if ok2:
            ok2b, out2_ilvm = compile_with(compiler2_ilvm_text, source)
            ran2, actual2 = run_ilvm(out2_ilvm, None, timeout=30) if ok2b else (False, "")
        else:
            ran2, actual2 = False, ""
        self_hosts = ran1 and ran2 and actual1 == actual2
        self_hosting_scores.append(1.0 if self_hosts else 0.0)

        print(
            f"{name}: correctness={'PASS' if correct else 'FAIL'} "
            f"self-hosting={'PASS' if self_hosts else 'FAIL'}"
        )
        if not correct:
            print(f"  compiled ok={ok1} ran ok={ran1} expected={expected!r} actual={actual1!r}")
        if not self_hosts:
            print(f"  compiler.ilvm run={ran1} actual={actual1!r} vs compiler2.ilvm run={ran2} actual={actual2!r}")

    correctness = sum(correctness_scores) / len(correctness_scores)
    self_hosting = sum(self_hosting_scores) / len(self_hosting_scores)
    reward = 0.5 * correctness + 0.5 * self_hosting

    print(f"correctness={correctness:.4f} self_hosting={self_hosting:.4f} reward={reward:.4f}")
    write_reward(reward)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
