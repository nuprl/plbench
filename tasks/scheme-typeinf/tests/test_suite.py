#!/usr/bin/env python3
"""Grade /app/typeinf with a binary, all-or-nothing result.

The challenge directory is the source of truth:

* ``bad-*.scm`` programs must be rejected by typeinf and must produce a runtime
  type error under the trusted MiniScheme interpreter.
* ``ok-*.scm`` and ``hard-ok-*.scm`` programs must be accepted by typeinf and
  must run cleanly under MiniScheme.

Before grading, metacircular clients are assembled into ordinary standalone
MiniScheme programs by prefixing `/app/mceval.scm`. The mceval-self marker is
resolved directly to `/app/mceval.scm`. Consequently, every challenge reaches
the same grading function as a name, one program path, and one expected typeinf
decision. The reward is 1 only when every decision is correct; otherwise it is
0. Host/reference mismatches are verifier bugs and abort grading without a
reward.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

MINISCHEME = Path("/app/minischeme")
TYPEINF = Path("/app/typeinf")
MCEVAL = Path("/app/mceval.scm")
CHALLENGES = Path("/tests/challenges")
REWARD = Path("/logs/verifier/reward.txt")

# These files are supplied by the environment but live in the agent-writable
# /app tree. Verify their exact build contents before trusting either one for
# fixture validation or metacircular-program assembly.
TRUSTED_MD5 = {
    MINISCHEME: "bf2271a9d0e0eda33003c0668beaec46",
    MCEVAL: "02932a272e22722800ef9871d19b2299",
}


@dataclass(frozen=True)
class Case:
    """One fully assembled grading case.

    `program` is the exact source passed both to the trusted interpreter and to
    the submission. `should_accept` is therefore the only distinction the
    grading loop needs to make between positive and negative fixtures.
    """

    name: str
    program: Path
    should_accept: bool


class VerifierError(Exception):
    """A fixture disagrees with its declared trusted-runtime behavior."""


def run(cmd: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        return subprocess.CompletedProcess(
            cmd,
            124,
            error.stdout or "",
            f"timeout after {timeout:g}s",
        )


def is_type_error(stderr: str, stdout: str) -> bool:
    text = ((stderr or "") + (stdout or "")).lower()
    return text.startswith("error:") or "\nerror:" in text or "error: " in text


def md5(path: Path) -> str:
    """Return the hexadecimal MD5 digest of a file without loading it at once."""

    digest = hashlib.md5()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inputs_are_trusted() -> bool:
    """Check the submission exists and the two environment references are intact.

    `/app/typeinf` is intentionally agent-controlled, so only its presence is
    required. MiniScheme and mceval are verifier inputs despite residing under
    `/app`; their embedded digests ensure an agent cannot replace either one and
    then grade itself against the replacement.
    """

    if not TYPEINF.is_file():
        print(f"missing submission: {TYPEINF}", file=sys.stderr)
        return False

    trusted = True
    for path, expected in TRUSTED_MD5.items():
        if not path.is_file():
            print(f"missing trusted file: {path}", file=sys.stderr)
            trusted = False
            continue
        actual = md5(path)
        if actual != expected:
            print(
                f"trusted file hash mismatch: {path} "
                f"(expected {expected}, got {actual})",
                file=sys.stderr,
            )
            trusted = False
    return trusted


def assemble_positive(path: Path, directory: Path) -> Path:
    """Return the standalone program represented by one positive fixture.

    Ordinary fixtures already are standalone. A filename ending in
    `-mceval-self.scm` is a marker for the provided interpreter itself. Other
    filenames containing `-mceval-` are clients, so their source is appended to
    the interpreter in a temporary file. This is the verifier's only mceval
    exception; after assembly those programs are graded exactly like all other
    cases.
    """

    if path.name.endswith("-mceval-self.scm"):
        return MCEVAL
    if "-mceval-" not in path.name:
        return path

    assembled = directory / path.name
    assembled.write_text(MCEVAL.read_text() + "\n" + path.read_text())
    return assembled


def assemble_cases(directory: Path) -> list[Case]:
    """Discover every fixture and resolve it to a standalone grading case."""

    bad = [Case(path.name, path, False) for path in sorted(CHALLENGES.glob("bad-*.scm"))]
    positive_paths = sorted(CHALLENGES.glob("ok-*.scm")) + sorted(
        CHALLENGES.glob("hard-ok-*.scm")
    )
    positive = [
        Case(path.name, assemble_positive(path, directory), True)
        for path in positive_paths
    ]
    return bad + positive


def grade_case(case: Case) -> tuple[bool, str]:
    """Validate and grade one fully assembled case.

    The trusted interpreter first checks the fixture's declaration: positive
    programs must complete without error, while negative programs must fail
    specifically with a runtime type error. Only after that invariant is
    established do we run `/app/typeinf` on the identical source. A submission
    passes exactly when its zero/nonzero exit status matches `should_accept`.
    Thus crashes and timeouts reject positive programs but cannot accidentally
    accept negative ones, and fixture mistakes are never charged to an agent.
    """

    host = run([str(MINISCHEME), "-l", str(case.program)], timeout=60)
    if case.should_accept and host.returncode != 0:
        raise VerifierError(
            f"{case.name} is labeled ok but the host failed (rc={host.returncode}):\n"
            f"{host.stderr}\n{host.stdout}"
        )
    if not case.should_accept:
        if host.returncode == 0:
            raise VerifierError(f"{case.name} is labeled bad but the host accepted it")
        if not is_type_error(host.stderr, host.stdout):
            raise VerifierError(
                f"{case.name} is labeled bad but failed without a type error "
                f"(rc={host.returncode}):\n{host.stderr}\n{host.stdout}"
            )

    submission = run([str(TYPEINF), str(case.program)], timeout=30)
    accepted = submission.returncode == 0
    if accepted == case.should_accept:
        decision = "accepted" if accepted else f"rejected (exit {submission.returncode})"
        return True, f"correctly {decision}"

    if accepted:
        return False, "UNSOUND: accepted a program that type-errors at runtime"
    detail = submission.stderr.strip() or submission.stdout.strip()
    note = f"incorrectly rejected (exit {submission.returncode})"
    return False, f"{note}: {detail}" if detail else note


def write_reward(reward: int) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{reward}\n")


def main() -> int:
    if not inputs_are_trusted():
        write_reward(0)
        return 0

    try:
        with tempfile.TemporaryDirectory(prefix="scheme-typeinf-cases-") as tmp:
            cases = assemble_cases(Path(tmp))
            all_passed = True
            print("=== grading all cases (all must pass) ===")
            for case in cases:
                passed, note = grade_case(case)
                print(f"{case.name}: {'PASS' if passed else 'FAIL'} — {note}")
                all_passed &= passed
    except VerifierError as error:
        print(f"VERIFIER ERROR: {error}", file=sys.stderr)
        return 1

    reward = int(all_passed)
    print(f"reward={reward} ({'all cases passed' if reward else 'one or more cases failed'})")
    write_reward(reward)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
