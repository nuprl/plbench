#!/usr/bin/env python3
"""Grade /app/typeinf for MiniScheme soundness.

Challenge files live in /tests/challenges/:
  ok-*.scm       — easy: must accept; must run without runtime type error
  bad-*.scm      — soundness gate: any miss → reward 0.0
  hard-ok-*.scm  — hard: optional accept; if accepted, must not type-error

Score (when all bad-* are correctly rejected and nothing unsound is accepted):
  0.5 * mean(ok-*) + 0.5 * mean(hard-ok-*)

hard-ok-03/04 need /app/mceval.scm loaded at runtime.
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
    if not MCEVAL.is_file():
        return 1, "", "missing /app/mceval.scm"
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


def check_mceval() -> tuple[bool, str]:
    if not MCEVAL.is_file():
        return False, "missing /app/mceval.scm"
    samples = [
        ("(ms-eval (quote (+ 1 2)) (ms-initial-env))", "3"),
        ("(ms-eval (quote (if #t 10 20)) (ms-initial-env))", "10"),
        ("(ms-eval (quote ((lambda (x) (+ x 1)) 41)) (ms-initial-env))", "42"),
        ("(ms-eval (quote (let ((x 3)) (+ x 4))) (ms-initial-env))", "7"),
        ("(ms-eval (quote (car (list 1 2 3))) (ms-initial-env))", "1"),
    ]
    for expr, expected in samples:
        completed = run(
            [str(MINISCHEME), "-l", str(MCEVAL), "-e", f"(display {expr})"],
            timeout=60,
        )
        if completed.returncode != 0:
            return False, f"mceval failed on {expr}:\n{completed.stderr}\n{completed.stdout}"
        out = completed.stdout.strip()
        if out != expected:
            return False, f"mceval {expr}: expected {expected!r}, got {out!r}"
    return True, f"mceval ok ({len(samples)} samples)"


def grade_ok(path: Path) -> tuple[float, str]:
    rc, out, err = typeinf(path)
    if rc != 0:
        return 0.0, f"rejected (exit {rc}): {err.strip() or out.strip()}"
    hrc, hout, herr = host_eval(path)
    if hrc != 0 and is_type_error(herr, hout):
        return 0.0, f"UNSOUND: accepted but runtime type error:\n{herr}"
    if hrc != 0:
        return 0.0, f"accepted but host failed:\n{herr}\n{hout}"
    return 1.0, "accept ok"


def grade_bad(path: Path) -> tuple[bool, str]:
    """Return (passed, note). passed means correctly rejected."""
    rc, out, err = typeinf(path)
    if rc != 0:
        return True, f"correctly rejected (exit {rc})"
    hrc, hout, herr = host_eval(path)
    if hrc != 0 and is_type_error(herr, hout):
        return False, f"UNSOUND: accepted program that type-errors:\n{herr}"
    return False, f"should reject; accepted and host rc={hrc}"


def grade_hard_ok(path: Path) -> tuple[float, str]:
    name = path.name
    if name == MCEVAL_SELF:
        if not MCEVAL.is_file():
            return 0.0, "missing /app/mceval.scm"
        rc, out, err = typeinf(MCEVAL)
        if rc != 0:
            return 0.0, f"reject mceval.scm: {err.strip() or out.strip()}"
        return 1.0, "typed /app/mceval.scm"

    load = name in MCEVAL_CLIENTS
    if load:
        rc, out, err = typeinf_with_mceval(path)
    else:
        rc, out, err = typeinf(path)
    if rc != 0:
        return 0.0, f"reject: {err.strip() or out.strip()}"
    hrc, hout, herr = host_eval(path, load_mceval=load)
    if hrc != 0 and is_type_error(herr, hout):
        return 0.0, f"UNSOUND on hard-ok:\n{herr}"
    if hrc != 0:
        return 0.0, f"accepted but host failed:\n{herr}"
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

    print("=== mceval API ===")
    mok, mnote = check_mceval()
    print(mnote)
    if not mok:
        print("mceval API failed → reward 0.0")
        write_reward(0.0)
        return 1

    oks = sorted(CHALLENGES.glob("ok-*.scm"))
    bads = sorted(CHALLENGES.glob("bad-*.scm"))
    hards = sorted(CHALLENGES.glob("hard-ok-*.scm"))

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
        if s == 0.0 and "UNSOUND" in note:
            print(f"UNSOUND on {path.name} → reward 0.0")
            write_reward(0.0)
            return 1
        ok_scores.append(s)

    hard_scores: list[float] = []
    print("=== hard-ok (hard, 50%) ===")
    for path in hards:
        s, note = grade_hard_ok(path)
        print(f"{path.name}: score={s:.1f} — {note}")
        if s == 0.0 and "UNSOUND" in note:
            print(f"UNSOUND on {path.name} → reward 0.0")
            write_reward(0.0)
            return 1
        hard_scores.append(s)

    easy_mean = sum(ok_scores) / len(ok_scores) if ok_scores else 0.0
    hard_mean = sum(hard_scores) / len(hard_scores) if hard_scores else 0.0
    mean = 0.5 * easy_mean + 0.5 * hard_mean

    print(f"mean_score={mean:.4f} (easy={easy_mean:.4f} hard={hard_mean:.4f})")
    write_reward(mean)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
