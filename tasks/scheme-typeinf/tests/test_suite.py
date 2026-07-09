#!/usr/bin/env python3
"""Grade /app/typeinf for MiniScheme soundness.

Challenge files live in /tests/challenges/:
  ok-*.scm       — easy: must accept; must run without runtime type error
  bad-*.scm      — soundness gate: any miss → reward 0.0
  hard-ok-*.scm  — hard: optional accept; if accepted, must not type-error

Score (when all bad-* are correctly rejected and nothing unsound is accepted):
  0.5 * mean(ok-*) + 0.5 * mean(hard-ok-*)

Before grading /app/typeinf on any fixture, we first establish ground truth by
running the fixture on the host (ok-*/hard-ok-* must run cleanly; bad-* must
runtime-type-error). If a fixture doesn't match the ground truth its category
promises, that's a bug in the fixture, not the agent — we raise VerifierError
and abort without writing a reward, rather than silently scoring the agent
against a broken test.

/app/mceval.scm is a metacircular interpreter supplied by the verifier
(test.sh copies it in from /tests/mceval.scm) — agents are not expected to
write it themselves.
hard-ok-03/04 load /app/mceval.scm and type-check + host-run a client
expression that calls into it (ms-eval/ms-initial-env), i.e. they exercise
applications of mceval, not just its own definitions.
hard-ok-05 types /app/mceval.scm itself.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

MINISCHEME = Path("/app/minischeme")
TYPEINF = Path("/app/typeinf")
MCEVAL = Path("/app/mceval.scm")
CHALLENGES = Path("/tests/challenges")
REWARD = Path("/logs/verifier/reward.txt")

MCEVAL_CLIENTS = {
    "hard-ok-03-mceval-arith.scm",
    "hard-ok-04-mceval-lambda.scm",
}
MCEVAL_SELF = "hard-ok-05-mceval-self.scm"


def run(cmd: list[str], timeout: float = 30) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(
            cmd,
            124,
            e.stdout or "",
            f"timeout after {timeout:g}s",
        )


class VerifierError(Exception):
    """A fixture didn't behave as its category promises — a test-suite bug,
    not something to hold against the agent."""


def is_type_error(stderr: str, stdout: str) -> bool:
    text = ((stderr or "") + (stdout or "")).lower()
    return text.startswith("error:") or "\nerror:" in text or "error: " in text


def host_eval(path: Path, *, load_mceval: bool = False) -> tuple[int, str, str]:
    cmd = [str(MINISCHEME)]
    if load_mceval:
        cmd.extend(["-l", str(MCEVAL)])
    cmd.extend(["-l", str(path)])
    completed = run(cmd, timeout=60)
    return completed.returncode, completed.stdout, completed.stderr


def typeinf(path: Path) -> tuple[int, str, str]:
    completed = run([str(TYPEINF), str(path)], timeout=30)
    return completed.returncode, completed.stdout, completed.stderr


def typeinf_with_mceval(client: Path) -> tuple[int, str, str]:
    """Type-check mceval.scm concatenated with a client program."""
    with tempfile.NamedTemporaryFile(
        "w", suffix=".scm", delete=False, prefix="mceval-client-"
    ) as tmp:
        tmp.write(MCEVAL.read_text())
        tmp.write("\n")
        tmp.write(client.read_text())
        tmp_path = Path(tmp.name)
    try:
        return typeinf(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)


def expect_runs_clean(path: Path, *, load_mceval: bool = False) -> None:
    """Ground truth for ok-*/hard-ok-* fixtures: must run on the host without
    error. Raises VerifierError if the fixture itself is broken."""
    hrc, hout, herr = host_eval(path, load_mceval=load_mceval)
    if hrc != 0:
        raise VerifierError(
            f"fixture {path.name} is labeled ok but the host failed (rc={hrc}):\n{herr}\n{hout}"
        )


def expect_type_errors(path: Path) -> None:
    """Ground truth for bad-* fixtures: must runtime-type-error on the host.
    Raises VerifierError if the fixture itself is broken."""
    hrc, hout, herr = host_eval(path)
    if hrc == 0:
        raise VerifierError(f"fixture {path.name} is labeled bad but the host accepted it")
    if not is_type_error(herr, hout):
        raise VerifierError(
            f"fixture {path.name} is labeled bad but failed without a type error (rc={hrc}):\n{herr}\n{hout}"
        )


def grade_ok(path: Path) -> tuple[float, str]:
    expect_runs_clean(path)
    rc, out, err = typeinf(path)
    if rc != 0:
        return 0.0, f"rejected (exit {rc}): {err.strip() or out.strip()}"
    return 1.0, "accept ok"


def grade_bad(path: Path) -> tuple[bool, str]:
    """Return (passed, note). passed means correctly rejected."""
    expect_type_errors(path)
    rc, out, err = typeinf(path)
    if rc != 0:
        return True, f"correctly rejected (exit {rc})"
    return False, "UNSOUND: accepted a program that type-errors at runtime"


def grade_hard_ok(path: Path) -> tuple[float, str]:
    name = path.name
    if name == MCEVAL_SELF:
        expect_runs_clean(MCEVAL)
        rc, out, err = typeinf(MCEVAL)
        if rc != 0:
            return 0.0, f"reject mceval.scm: {err.strip() or out.strip()}"
        return 1.0, "typed /app/mceval.scm"

    load = name in MCEVAL_CLIENTS
    expect_runs_clean(path, load_mceval=load)
    if load:
        rc, out, err = typeinf_with_mceval(path)
    else:
        rc, out, err = typeinf(path)
    if rc != 0:
        return 0.0, f"reject: {err.strip() or out.strip()}"
    return 1.0, "hard-ok accepted"


def write_reward(mean: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{mean:.6f}\n")


def main() -> int:
    if not MINISCHEME.is_file():
        print("missing /app/minischeme", file=sys.stderr)
        write_reward(0.0)
        return 1
    if not TYPEINF.is_file():
        print("missing /app/typeinf", file=sys.stderr)
        write_reward(0.0)
        return 1

    oks = sorted(CHALLENGES.glob("ok-*.scm"))
    bads = sorted(CHALLENGES.glob("bad-*.scm"))
    hards = sorted(CHALLENGES.glob("hard-ok-*.scm"))

    try:
        print("=== bad (soundness gate: any miss → 0.0) ===")
        bad_ok = True
        for path in bads:
            passed, note = grade_bad(path)
            print(f"{path.name}: {'PASS' if passed else 'FAIL'} — {note}")
            if not passed:
                bad_ok = False
        if not bad_ok:
            print("bad-* miss → reward 0.0")
            write_reward(0.0)
            return 1

        ok_scores: list[float] = []
        print("=== ok (easy, 50%) ===")
        for path in oks:
            s, note = grade_ok(path)
            print(f"{path.name}: score={s:.1f} — {note}")
            ok_scores.append(s)

        hard_scores: list[float] = []
        print("=== hard-ok (hard, 50%) ===")
        for path in hards:
            s, note = grade_hard_ok(path)
            print(f"{path.name}: score={s:.1f} — {note}")
            hard_scores.append(s)
    except VerifierError as e:
        print(f"VERIFIER ERROR: {e}", file=sys.stderr)
        return 1

    easy_mean = sum(ok_scores) / len(ok_scores) if ok_scores else 0.0
    hard_mean = sum(hard_scores) / len(hard_scores) if hard_scores else 0.0
    mean = 0.5 * easy_mean + 0.5 * hard_mean

    print(f"mean_score={mean:.4f} (easy={easy_mean:.4f} hard={hard_mean:.4f})")
    write_reward(mean)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
