#!/usr/bin/env python3
"""Oracle validation: every challenge must match host crash/no-crash expectations.

Also drives /app/mceval.scm (or the solution copy) on sample programs via
/app/minischeme. Exits non-zero if any expectation fails.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

MINISCHEME = Path("/app/minischeme")
MCEVAL = Path("/app/mceval.scm")
CHALLENGES = Path("/tests/challenges")

MCEVAL_CLIENTS = {
    "hard-ok-03-mceval-arith.scm",
    "hard-ok-04-mceval-lambda.scm",
}
# Marker file — validated by typing/loading mceval, not by running the marker.
MCEVAL_SELF = "hard-ok-05-mceval-self.scm"


def run(cmd: list[str], timeout: float = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def is_type_error(stderr: str, stdout: str) -> bool:
    text = ((stderr or "") + (stdout or "")).lower()
    return "error:" in text


def host_eval(path: Path, *, load_mceval: bool = False) -> tuple[int, str, str]:
    cmd = [str(MINISCHEME)]
    if load_mceval:
        cmd.extend(["-l", str(MCEVAL)])
    cmd.extend(["-l", str(path)])
    c = run(cmd)
    return c.returncode, c.stdout, c.stderr


def main() -> int:
    if not MINISCHEME.is_file():
        print("oracle-validate: missing /app/minischeme", file=sys.stderr)
        return 1
    if not MCEVAL.is_file():
        print("oracle-validate: missing /app/mceval.scm", file=sys.stderr)
        return 1

    failures = 0

    print("=== validate ok-* (must run clean) ===")
    for path in sorted(CHALLENGES.glob("ok-*.scm")):
        rc, out, err = host_eval(path)
        if rc != 0:
            print(f"FAIL {path.name}: expected success, got rc={rc}\n{err}")
            failures += 1
        else:
            print(f"OK   {path.name} -> {out.strip()}")

    print("=== validate bad-* (must type-error) ===")
    for path in sorted(CHALLENGES.glob("bad-*.scm")):
        rc, out, err = host_eval(path)
        if rc == 0 or not is_type_error(err, out):
            print(
                f"FAIL {path.name}: expected runtime type error, "
                f"rc={rc} err={err!r} out={out!r}"
            )
            failures += 1
        else:
            print(f"OK   {path.name} type-errors: {err.strip()}")

    print("=== validate hard-ok-* (must run clean when applicable) ===")
    for path in sorted(CHALLENGES.glob("hard-ok-*.scm")):
        if path.name == MCEVAL_SELF:
            # Ensure mceval source itself loads under the host.
            c = run([str(MINISCHEME), "-l", str(MCEVAL), "-e", "#t"])
            if c.returncode != 0:
                print(f"FAIL {path.name}: mceval.scm failed to load\n{c.stderr}")
                failures += 1
            else:
                print(f"OK   {path.name} (mceval.scm loads)")
            continue
        load = path.name in MCEVAL_CLIENTS
        rc, out, err = host_eval(path, load_mceval=load)
        if rc != 0:
            print(f"FAIL {path.name}: expected success, got rc={rc}\n{err}")
            failures += 1
        else:
            print(f"OK   {path.name} -> {out.strip()}")

    print("=== drive metacircular interpreter samples ===")
    samples = [
        ("(ms-eval (quote (+ 1 2)) (ms-initial-env))", "3"),
        ("(ms-eval (quote (if #t 10 20)) (ms-initial-env))", "10"),
        ("(ms-eval (quote ((lambda (x) (+ x 1)) 41)) (ms-initial-env))", "42"),
        ("(ms-eval (quote (let ((x 3)) (+ x 4))) (ms-initial-env))", "7"),
        ("(ms-eval (quote (car (list 1 2 3))) (ms-initial-env))", "1"),
        ("(ms-eval (quote (cond ((< 1 0) 1) (else 99))) (ms-initial-env))", "99"),
        ("(ms-eval (quote (and #t (< 1 2))) (ms-initial-env))", "#t"),
    ]
    for expr, expected in samples:
        c = run([str(MINISCHEME), "-l", str(MCEVAL), "-e", f"(display {expr})"])
        got = c.stdout.strip()
        if c.returncode != 0 or got != expected:
            print(f"FAIL mceval {expr}: expected {expected!r}, got {got!r}\n{c.stderr}")
            failures += 1
        else:
            print(f"OK   mceval {expr} -> {got}")

    if failures:
        print(f"oracle-validate: {failures} failure(s)", file=sys.stderr)
        return 1
    print("oracle-validate: all expectations held")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
