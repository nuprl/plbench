#!/usr/bin/env python3
"""Grade a MiniScheme-to-MiniScheme proper-tail-call compiler."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MINISCHEME = Path("/app/minischeme")
COMPILER = Path("/app/compiler")
PROGRAMS = Path("/tests/programs")
REWARD = Path("/logs/verifier/reward.txt")
STACK_LIMIT = "50"


@dataclass
class Run:
    returncode: int
    stdout: str
    stderr: str


class VerifierError(Exception):
    pass


def run(command: list[str], timeout: float) -> Run:
    try:
        completed = subprocess.run(
            command,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        return Run(completed.returncode, completed.stdout, completed.stderr)
    except subprocess.TimeoutExpired as error:
        return Run(124, error.stdout or "", error.stderr or f"timeout after {timeout:g}s")
    except OSError as error:
        return Run(126, "", str(error))


def write_reward(score: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{score:.6f}\n")


def establish_reference(program: Path) -> Run:
    result = run([str(MINISCHEME), "-l", str(program)], timeout=30)
    if result.returncode == 124:
        raise VerifierError(f"unlimited reference timed out on {program.name}")
    return result


def check_depth_instrumentation(program: Path) -> None:
    result = run(
        [str(MINISCHEME), "--max-stack-depth", STACK_LIMIT, "-l", str(program)],
        timeout=10,
    )
    if result.returncode == 0 or "maximum stack depth exceeded" not in result.stderr:
        raise VerifierError(
            "reference depth-limit preflight did not reject the uncompiled "
            f"tail-recursive program {program.name}: rc={result.returncode}, "
            f"stderr={result.stderr!r}"
        )


def grade_program(program: Path, expected: Run, directory: Path) -> tuple[float, str]:
    output = directory / f"{program.stem}.compiled.scm"
    compiled = run([str(COMPILER), str(program), str(output)], timeout=30)
    if compiled.returncode != 0:
        return 0.0, f"compiler exited {compiled.returncode}: {compiled.stderr.strip()}"
    if not output.is_file():
        return 0.0, "compiler reported success but did not create OUTPUT.scm"
    if output.stat().st_size > 2_000_000:
        return 0.0, "compiled output exceeds 2 MB"

    actual = run(
        [str(MINISCHEME), "--max-stack-depth", STACK_LIMIT, "-l", str(output)],
        timeout=30,
    )
    expected_success = expected.returncode == 0
    actual_success = actual.returncode == 0
    if expected_success != actual_success:
        return (
            0.0,
            f"outcome mismatch: source rc={expected.returncode}, compiled rc={actual.returncode}; "
            f"compiled stderr={actual.stderr.strip()!r}",
        )
    if expected.stdout != actual.stdout:
        return 0.0, f"stdout mismatch: expected {expected.stdout!r}, got {actual.stdout!r}"
    if not expected_success and expected.stderr != actual.stderr:
        return 0.0, f"runtime-error mismatch: expected {expected.stderr!r}, got {actual.stderr!r}"
    return 1.0, "behavior matches at depth 50"


def main() -> int:
    if not MINISCHEME.is_file():
        print("VERIFIER ERROR: missing /app/minischeme", file=sys.stderr)
        return 1
    if not COMPILER.is_file():
        print("missing /app/compiler", file=sys.stderr)
        write_reward(0.0)
        return 1

    programs = sorted(PROGRAMS.glob("*.scm"))
    if not programs:
        print("VERIFIER ERROR: no test programs", file=sys.stderr)
        return 1

    try:
        references = {program: establish_reference(program) for program in programs}
        if references[programs[0]].returncode != 0:
            raise VerifierError("the depth-limit preflight program fails without a limit")
        check_depth_instrumentation(programs[0])
    except VerifierError as error:
        print(f"VERIFIER ERROR: {error}", file=sys.stderr)
        return 1

    scores: list[float] = []
    with tempfile.TemporaryDirectory(prefix="tail-call-compiler-") as tmp:
        directory = Path(tmp)
        for program in programs:
            score, note = grade_program(program, references[program], directory)
            scores.append(score)
            print(f"{program.name}: {'PASS' if score else 'FAIL'} — {note}")

    mean = sum(scores) / len(scores)
    print(f"score={mean:.4f} ({int(sum(scores))}/{len(scores)} programs)")
    write_reward(mean)
    return 0 if mean == 1.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
