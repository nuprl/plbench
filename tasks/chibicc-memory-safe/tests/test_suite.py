"""End-to-end verifier for the capability-safe chibicc task.

The runner treats ``tests/safe`` and ``tests/unsafe`` as the canonical test
corpus.  For every ``safe/NAME.c`` there must be a sibling ``safe/NAME.out``.
Before grading, every source is checked with GCC in strict C99 mode. A source
that is not C99 is a verifier defect, not a candidate-solution failure.
The program must compile, terminate normally within eight seconds, print
exactly the bytes in that expectation file, and emit no recognized
memory-safety diagnostic. Exact output checking prevents an implementation that merely
lets every program exit successfully from passing the positive half.

Every ``unsafe/NAME.c`` is also ordinary, compilable C; its undefined behavior
occurs only when the resulting executable runs.  It must terminate nonzero
within eight seconds and place ``BCHECK:`` or ``RUNTIME ERROR:`` on stderr.
Compiler rejection, signals without a checked
diagnostic, hangs, and normal termination all fail the case.

Harbor uses ``/app/safec`` and ``/tests``.  ``SAFEC`` and ``TEST_ROOT`` may
override those paths for a local oracle run.  Test processes inherit the
environment except that ``TCC_BOUNDS_NEVER_FATAL`` is removed so a developer's
shell cannot accidentally disable fatal checks.
"""

from __future__ import annotations

import os
import re
import resource
import subprocess
import tempfile
from pathlib import Path


COMPILER = Path(os.environ.get("SAFEC", "/app/safec"))
ROOT = Path(os.environ.get("TEST_ROOT", "/tests"))
DIAGNOSTIC = re.compile(r"BCHECK:|RUNTIME ERROR:")
PROGRAM_ADDRESS_SPACE_LIMIT = 1024 * 1024 * 1024


def verify_c99(sources: list[Path]) -> None:
    """Reject a malformed verifier corpus before grading the candidate."""
    for source in sources:
        try:
            checked = subprocess.run(
                [
                    "gcc",
                    "-std=c99",
                    "-pedantic-errors",
                    "-fsyntax-only",
                    str(source),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
        except FileNotFoundError as error:
            raise RuntimeError(
                "verifier error: gcc is required for the C99 preflight"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(
                f"verifier error: C99 preflight timed out for {source}"
            ) from error

        if checked.returncode != 0:
            raise RuntimeError(
                f"verifier error: {source} is not strict C99\n"
                f"{checked.stdout}{checked.stderr}"
            )


def compile_case(source: Path, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(COMPILER), str(source), "-o", str(output)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def run_case(executable: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env.pop("TCC_BOUNDS_NEVER_FATAL", None)

    def limit_address_space() -> None:
        # Apply the limit to the compiled program, not to the verifier or
        # compiler process. The GC stress case allocates 2 GiB cumulatively,
        # so it can finish under this limit only if unreachable objects are
        # reclaimed.
        resource.setrlimit(
            resource.RLIMIT_AS,
            (PROGRAM_ADDRESS_SPACE_LIMIT, PROGRAM_ADDRESS_SPACE_LIMIT),
        )

    return subprocess.run(
        [str(executable)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        env=env,
        preexec_fn=limit_address_space,
    )


def main() -> None:
    safe_sources = sorted((ROOT / "safe").glob("*.c"))
    unsafe_sources = sorted((ROOT / "unsafe").glob("*.c"))
    verify_c99(safe_sources + unsafe_sources)

    if not COMPILER.is_file() or not os.access(COMPILER, os.X_OK):
        raise AssertionError("expected executable compiler driver at /app/safec")

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="safec-verifier-") as td:
        tmp = Path(td)

        for source in safe_sources:
            expected_path = source.with_suffix(".out")
            if not expected_path.is_file():
                raise RuntimeError(
                    f"verifier error: missing expected output {expected_path}"
                )
            expected_stdout = expected_path.read_text()
            exe = tmp / ("safe-" + source.stem)
            built = compile_case(source, exe)
            if built.returncode != 0:
                failures.append(
                    f"safe/{source.stem}: compile failed\n{built.stdout}{built.stderr}"
                )
                continue
            try:
                ran = run_case(exe)
            except subprocess.TimeoutExpired:
                failures.append(f"safe/{source.stem}: timed out")
                continue
            diagnostic = DIAGNOSTIC.search(ran.stderr)
            if ran.returncode != 0 or ran.stdout != expected_stdout or diagnostic:
                failures.append(
                    f"safe/{source.stem}: expected exit 0 and exact stdout\n"
                    f"exit: {ran.returncode}\n"
                    f"expected stdout:\n{expected_stdout}"
                    f"actual stdout:\n{ran.stdout}"
                    f"stderr:\n{ran.stderr}"
                )
            else:
                print(f"PASS safe/{source.stem}")

        for source in unsafe_sources:
            exe = tmp / ("unsafe-" + source.stem)
            built = compile_case(source, exe)
            if built.returncode != 0:
                failures.append(
                    f"unsafe/{source.stem}: compiler rejected ordinary C instead "
                    f"of producing a checked executable\n{built.stdout}{built.stderr}"
                )
                continue
            try:
                ran = run_case(exe)
            except subprocess.TimeoutExpired:
                failures.append(f"unsafe/{source.stem}: timed out instead of trapping")
                continue
            if ran.returncode == 0 or not DIAGNOSTIC.search(ran.stderr):
                failures.append(
                    f"unsafe/{source.stem}: expected nonzero checked trap, got "
                    f"{ran.returncode}\nstdout:\n{ran.stdout}\nstderr:\n{ran.stderr}"
                )
            else:
                print(f"PASS unsafe/{source.stem}")

    print(f"{len(failures)} verifier failure(s)")
    if failures:
        raise AssertionError("\n\n".join(failures))


if __name__ == "__main__":
    main()
