"""
Grade a data race detector using DataRaceBench. Results for prior tools:

https://github.com/LLNL/dataracebench/wiki/Tool-Evaluation-Dashboard
"""

from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


CORPUS = Path("/tests/dataracebench/micro-benchmarks")
CASE_TIMEOUT_SECONDS = 30


@dataclass(frozen=True)
class Case:
    """Associate a C benchmark with its expected ``RACE`` or ``SAFE`` result."""

    source: Path
    expected: str


def discover_cases() -> list[Case]:
    """Find the C benchmarks and derive their expected results from filenames."""
    return [
        Case(source, "RACE" if source.stem.endswith("-yes") else "SAFE")
        for source in sorted(CORPUS.glob("DRB*.c"))
    ]


def strip_comments(source: str) -> str:
    """Remove C comments while preserving literals and line breaks."""
    out: list[str] = []
    i = 0
    state = "code"
    while i < len(source):
        char = source[i]
        following = source[i + 1] if i + 1 < len(source) else ""

        if state == "code":
            if char == "/" and following == "*":
                out.extend("  ")
                i += 2
                state = "block"
                continue
            if char == "/" and following == "/":
                out.extend("  ")
                i += 2
                state = "line"
                continue
            out.append(char)
            if char == '"':
                state = "string"
            elif char == "'":
                state = "char"
            i += 1
            continue

        if state == "block":
            if char == "*" and following == "/":
                out.extend("  ")
                i += 2
                state = "code"
            else:
                out.append("\n" if char == "\n" else " ")
                i += 1
            continue

        if state == "line":
            if char == "\n":
                out.append(char)
                state = "code"
            else:
                out.append(" ")
            i += 1
            continue

        out.append(char)
        if char == "\\" and following:
            out.append(following)
            i += 2
        else:
            if (state == "string" and char == '"') or (
                state == "char" and char == "'"
            ):
                state = "code"
            i += 1

    return "".join(out)


STAGING_DIR = Path("/race-detector-inputs")


def evaluate(path: Path) -> tuple[str | None, str]:
    """Run the detector and return its result or an invalid-result diagnostic."""
    try:
        completed = subprocess.run(
            ["/app/race-detector", str(path)],
            cwd=path.parent,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=CASE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return None, "timed out"
    except OSError as exception:
        return None, f"could not execute detector: {exception}"

    if completed.returncode != 0:
        return None, f"exit {completed.returncode}; stderr: {completed.stderr[:400]}"
    if not re.fullmatch(r"(?:RACE|SAFE)\n?\Z", completed.stdout):
        return None, f"invalid stdout: {completed.stdout[:200]!r}"
    return completed.stdout.strip(), ""


def main() -> None:
    if not Path("/app/race-detector").is_file():
        raise AssertionError("/app/race-detector is missing")

    cases = discover_cases()
    STAGING_DIR.mkdir()
    shutil.copytree(CORPUS / "polybench", STAGING_DIR / "polybench")
    shutil.copy2(CORPUS / "signaling.h", STAGING_DIR / "signaling.h")

    true_positive = 0
    false_positive = 0
    true_negative = 0
    false_negative = 0
    for case in cases:
        path = STAGING_DIR / "input.c"
        path.write_text(strip_comments(case.source.read_text()))
        actual, invalid_result = evaluate(path)
        if actual is None:
            print(f"{case.source.name}: {invalid_result}")
            if case.expected == "RACE":
                false_negative += 1
            else:
                false_positive += 1
            continue

        match case.expected, actual:
            case "RACE", "RACE":
                true_positive += 1
            case "RACE", "SAFE":
                false_negative += 1
            case "SAFE", "RACE":
                false_positive += 1
            case "SAFE", "SAFE":
                true_negative += 1
            case _:
                raise AssertionError(f"unexpected result: {actual}")

            

    racy_total = sum(case.expected == "RACE" for case in cases)
    safe_total = len(cases) - racy_total
    score = 2 * true_positive / (2 * true_positive + false_positive + false_negative)

    print(f"racy correctly classified: {true_positive}/{racy_total}")
    print(f"safe correctly classified: {true_negative}/{safe_total}")
    print(f"score: {score}")

    Path("/logs/verifier/reward.txt").write_text(f"{score}\n")


if __name__ == "__main__":
    main()
