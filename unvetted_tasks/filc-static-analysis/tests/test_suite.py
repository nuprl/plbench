#!/usr/bin/env python3
"""Verifier for the Fil-C panic static-analysis task.

The verifier first validates its own corpus with Fil-C. Corpus failures are
verifier errors and must not produce a reward. Once the corpus is validated,
the does_panic cases form a hard soundness gate and the safe cases measure
precision.
"""

from __future__ import annotations

import os
import re
import resource
import shutil
import subprocess
import tempfile
from pathlib import Path


ANALYZER = Path(os.environ.get("ANALYZER", "/app/analyze"))
FILCC = os.environ.get("FILCC", "filcc")
ROOT = Path(os.environ.get("TEST_ROOT", "/tests"))
REWARD_PATH = Path("/logs/verifier/reward.txt")
PANIC_DIAGNOSTIC = re.compile(r"filc safety error:|filc panic:")

# These cases panic on a particular command-line witness. All other cases run
# without arguments.
RUN_ARGUMENTS = {
    "11_argument_dependent.c": ["argument"] * 36,
    "18_conditional_null_puts.c": ["argument"],
}


class VerifierError(RuntimeError):
    """The trusted corpus or Fil-C installation is inconsistent."""


def compile_with_filc(source: Path, output: Path) -> None:
    try:
        completed = subprocess.run(
            [FILCC, "-std=c99", "-pedantic-errors", str(source), "-o", str(output)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise VerifierError(
            f"verifier error: could not compile {source.name} with Fil-C: {error}"
        ) from error
    if completed.returncode != 0:
        raise VerifierError(
            f"verifier error: {source.name} is not accepted as C99 by Fil-C\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )


def disable_core_dumps() -> None:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_with_filc(source: Path, executable: Path) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            [str(executable), *RUN_ARGUMENTS.get(source.name, [])],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            cwd=executable.parent,
            env={"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"},
            preexec_fn=disable_core_dumps,
        )
    except subprocess.TimeoutExpired as error:
        raise VerifierError(
            f"verifier error: {source.name} timed out during corpus validation"
        ) from error
    except OSError as error:
        raise VerifierError(
            f"verifier error: could not run {source.name}: {error}"
        ) from error


def validate_corpus(safe_sources: list[Path], panic_sources: list[Path]) -> None:
    """Establish the trusted ground truth before invoking the submission."""
    with tempfile.TemporaryDirectory(prefix="filc-corpus-") as td:
        work = Path(td)
        for index, source in enumerate(safe_sources + panic_sources):
            executable = work / f"program-{index}"
            compile_with_filc(source, executable)
            completed = run_with_filc(source, executable)
            diagnostic = PANIC_DIAGNOSTIC.search(completed.stderr)

            if source in safe_sources:
                if completed.returncode < 0 or diagnostic:
                    raise VerifierError(
                        f"verifier error: safe/{source.name} panicked or crashed\n"
                        f"exit: {completed.returncode}\nstdout:\n{completed.stdout}\n"
                        f"stderr:\n{completed.stderr}"
                    )
                print(f"VALIDATED safe/{source.name}")
            else:
                if completed.returncode == 0 or not diagnostic:
                    raise VerifierError(
                        f"verifier error: does_panic/{source.name} did not produce "
                        f"a Fil-C panic\nexit: {completed.returncode}\n"
                        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
                    )
                print(f"VALIDATED does_panic/{source.name}")


def analyze(source: Path) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            [str(ANALYZER), str(source)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            cwd=source.parent,
            env={"PATH": os.environ.get("PATH", "")},
        )
    except subprocess.TimeoutExpired:
        return False, "analyzer timed out"
    except OSError as error:
        return False, f"could not run analyzer: {error}"

    if completed.returncode != 0:
        return False, (
            f"analyzer exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    if completed.stdout not in {"SAFE\n", "MAY PANIC\n"}:
        return False, (
            f"invalid output {completed.stdout!r}; stderr:\n{completed.stderr}"
        )
    return True, completed.stdout.strip()


def analyze_neutral_copy(source: Path, work: Path) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(dir=work) as case_td:
        neutral = Path(case_td) / "input.c"
        shutil.copyfile(source, neutral)
        return analyze(neutral)


def write_zero_and_fail(messages: list[str]) -> None:
    REWARD_PATH.write_text("0.000000\n")
    raise AssertionError("\n\n".join(messages))


def main() -> int:
    REWARD_PATH.unlink(missing_ok=True)
    if not ANALYZER.is_file() or not os.access(ANALYZER, os.X_OK):
        raise AssertionError("expected executable analyzer at /app/analyze")

    safe_sources = sorted((ROOT / "cases" / "safe").glob("*.c"))
    panic_sources = sorted((ROOT / "cases" / "does_panic").glob("*.c"))
    if not safe_sources:
        raise VerifierError("verifier error: no cases in safe")
    if not panic_sources:
        raise VerifierError("verifier error: no cases in does_panic")

    # Do not catch VerifierError here: corpus inconsistency must terminate the
    # verifier without creating reward.txt.
    validate_corpus(safe_sources, panic_sources)

    with tempfile.TemporaryDirectory(prefix="filc-analysis-") as td:
        work = Path(td)

        soundness_failures: list[str] = []
        for source in panic_sources:
            valid, result = analyze_neutral_copy(source, work)
            if not valid:
                soundness_failures.append(
                    f"does_panic/{source.name}: invalid analysis: {result}"
                )
                print(f"FAIL does_panic/{source.name}: invalid analysis")
            elif result == "SAFE":
                soundness_failures.append(
                    f"does_panic/{source.name}: unsoundly reported SAFE"
                )
                print(f"FAIL does_panic/{source.name}: reported SAFE")
            else:
                print(f"PASS does_panic/{source.name}")

        if soundness_failures:
            print("soundness gate failed; score=0.000000")
            write_zero_and_fail(soundness_failures)

        certified_safe = 0
        interface_failures: list[str] = []
        for source in safe_sources:
            valid, result = analyze_neutral_copy(source, work)
            if not valid:
                interface_failures.append(
                    f"safe/{source.name}: invalid analysis: {result}"
                )
                print(f"FAIL safe/{source.name}: invalid analysis")
            elif result == "SAFE":
                certified_safe += 1
                print(f"PASS safe/{source.name}: reported SAFE")
            else:
                print(f"MISS safe/{source.name}: reported MAY PANIC")

        if interface_failures:
            print("analyzer interface failed; score=0.000000")
            write_zero_and_fail(interface_failures)

    score = certified_safe / len(safe_sources)
    REWARD_PATH.write_text(f"{score:.6f}\n")
    print(
        f"precision_score={score:.6f} "
        f"({certified_safe}/{len(safe_sources)} safe programs certified)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
