#!/usr/bin/env python3
"""Grade a MiniScheme-to-ILVM compiler in two passes.

The submission is one MiniScheme program, /app/compiler.scm. For each example:

1. Run compiler.scm with the trusted MiniScheme interpreter, then run the ILVM
   it emits. This measures compiler correctness without requiring bootstrap.
2. Ask compiler.scm to compile itself, run that generated ILVM compiler on the
   same example, and run its output. This measures self-hosting.

Both results must match the trusted MiniScheme interpreter's behavior on the
example. Each pass contributes half of the reward.

The bundled oracle is deliberately written in Python rather than MiniScheme.
Its marker selects the fallback compiler in run_source_compiler, the only
oracle-specific execution path. It passes the first stage; compiling its
MiniScheme stub produces an aborting compiler, so it earns no self-hosting
credit.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ILVM_REF = Path("/tests/ilvm_ref/target/release/ilvm")
MINISCHEME_REF = Path("/tests/minischeme_ref/minischeme")
COMPILER_SCM = Path("/app/compiler.scm")
FALLBACK_COMPILER = Path("/app/.oracle_fallback_compiler.py")
EXAMPLES = Path("/tests/examples")
REWARD = Path("/logs/verifier/reward.txt")

ORACLE_MARKER = "ORACLE-NOT-SELF-HOSTING-7f3ac9e1d4b8407e9c2a1f6e5d0b8c33"
STATUS_RE = re.compile(r"^Normal termination\. Result = -?\d+$")


class VerifierError(Exception):
    """The verifier or one of its private fixtures is broken."""


@dataclass(frozen=True)
class Result:
    ok: bool
    output: str = ""


FAILED = Result(False)


def strip_ilvm_status(stdout: str) -> str:
    """Remove the reference ILVM interpreter's termination-status line."""
    body = stdout[:-1] if stdout.endswith("\n") else stdout
    output, _, status = body.rpartition("\n")
    if STATUS_RE.match(status):
        return output + "\n" if output else ""
    return stdout


def run_process(command: list[str], timeout: int, stdin: str | None = None) -> Result:
    try:
        completed = subprocess.run(
            command,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return FAILED
    return Result(completed.returncode == 0, completed.stdout)


def run_minischeme(program: Path, args: list[str]) -> Result:
    return run_process([str(MINISCHEME_REF), str(program), *args], timeout=60)


def run_ilvm(program_text: str, args: list[str]) -> Result:
    with tempfile.NamedTemporaryFile("w", suffix=".ilvm", delete=False) as file:
        file.write(program_text)
        program = Path(file.name)
    try:
        command = [str(ILVM_REF), "-m", "4000000", "-r", "64", str(program)]
        for arg in args:
            command.extend(["-l", arg])
        result = run_process(command, timeout=60)
    finally:
        program.unlink(missing_ok=True)
    return Result(result.ok, strip_ilvm_status(result.output))


def run_source_compiler(source_text: str, is_oracle: bool) -> Result:
    """Compile source_text with compiler.scm, or with the admitted oracle."""
    if is_oracle:
        return run_process(
            [sys.executable, str(FALLBACK_COMPILER)],
            timeout=30,
            stdin=source_text,
        )
    return run_minischeme(COMPILER_SCM, [source_text])


def run_ilvm_compiler(compiler: Result, source_text: str) -> Result:
    if not compiler.ok:
        return FAILED
    return run_ilvm(compiler.output, [source_text])


def run_compiled_program(compiled: Result) -> Result:
    if not compiled.ok:
        return FAILED
    return run_ilvm(compiled.output, [])


def same_behavior(expected: Result, actual: Result) -> bool:
    return expected.ok == actual.ok and expected.output == actual.output


def write_reward(reward: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{reward:.6f}\n")


def main() -> int:
    if not ILVM_REF.is_file():
        raise VerifierError(f"missing reference ILVM interpreter: {ILVM_REF}")
    if not MINISCHEME_REF.is_file():
        raise VerifierError(f"missing reference MiniScheme interpreter: {MINISCHEME_REF}")
    if not COMPILER_SCM.is_file():
        print("missing /app/compiler.scm", file=sys.stderr)
        write_reward(0.0)
        return 1

    examples = sorted(EXAMPLES.glob("*.scm"))
    if not examples:
        raise VerifierError(f"no MiniScheme examples in {EXAMPLES}")

    compiler_source = COMPILER_SCM.read_text()
    is_oracle = ORACLE_MARKER in compiler_source
    if is_oracle and not FALLBACK_COMPILER.is_file():
        raise VerifierError(f"oracle fallback is missing: {FALLBACK_COMPILER}")

    self_hosted_compiler = run_source_compiler(compiler_source, is_oracle)
    if not self_hosted_compiler.ok:
        print("compiler.scm failed to compile itself; self-hosting cases will fail")

    direct_passes = 0
    self_hosted_passes = 0
    print("=== per-example results ===")

    for example in examples:
        source = example.read_text()
        expected = run_minischeme(example, [])

        direct_program = run_source_compiler(source, is_oracle)
        direct_result = run_compiled_program(direct_program)
        direct_ok = direct_program.ok and same_behavior(expected, direct_result)
        direct_passes += int(direct_ok)

        self_hosted_program = run_ilvm_compiler(self_hosted_compiler, source)
        self_hosted_result = run_compiled_program(self_hosted_program)
        self_hosted_ok = (
            self_hosted_compiler.ok
            and self_hosted_program.ok
            and same_behavior(expected, self_hosted_result)
        )
        self_hosted_passes += int(self_hosted_ok)

        print(
            f"{example.name}: "
            f"direct={'PASS' if direct_ok else 'FAIL'} "
            f"self-hosted={'PASS' if self_hosted_ok else 'FAIL'}"
        )
        if not direct_ok:
            print(f"  expected={expected} direct={direct_result}")
        if not self_hosted_ok:
            print(f"  expected={expected} self-hosted={self_hosted_result}")

    count = len(examples)
    direct_score = direct_passes / count
    self_hosted_score = self_hosted_passes / count
    reward = 0.5 * direct_score + 0.5 * self_hosted_score

    print(
        f"direct={direct_score:.4f} "
        f"self_hosted={self_hosted_score:.4f} "
        f"reward={reward:.4f}"
    )
    write_reward(reward)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
