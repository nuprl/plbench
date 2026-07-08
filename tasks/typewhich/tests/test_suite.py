#!/usr/bin/env python3
"""Grade TypeWhich FO-poly migrations on /app/examples point programs.

For each example:
  1. Run `cargo run -- migrate --precise <example>` (must exit 0 — soundness).
  2. Score precision against /tests/expected/<name>.gtlc.

Reward is the mean per-example score in [0, 1].
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

EXAMPLES = Path("/app/examples")
EXPECTED = Path("/tests/expected")
TYPEWHICH = Path("/app/TypeWhich")
BIN = TYPEWHICH / "target" / "debug" / "typeinf-playground"


def normalize(src: str) -> str:
    s = src.strip()
    s = re.sub(r"\s+", " ", s)
    s = s.replace(" -> ", "->")
    s = s.replace(" : ", ":")
    return s


def migrate(path: Path) -> tuple[bool, str]:
    if BIN.is_file():
        cmd = [str(BIN), "migrate", "--precise", str(path)]
    else:
        cmd = ["cargo", "run", "--quiet", "--", "migrate", "--precise", str(path)]
    completed = subprocess.run(
        cmd,
        cwd=TYPEWHICH,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if completed.returncode != 0:
        return False, (completed.stdout or "") + (completed.stderr or "")
    return True, completed.stdout


def precision_score(got: str, expected: str) -> float:
    """Heuristic precision score in [0, 1].

    Exact normalize-match → 1.0.
    Else: reward poly schemes and fewer `any` relative to the target.
    """
    g = normalize(got)
    e = normalize(expected)
    if g == e:
        return 1.0

    # Must look like a migration of the same program shape (has let / fun).
    if "let" not in g or "fun" not in g:
        return 0.0

    score = 0.0
    # Poly on lets that the target uses
    target_poly = len(re.findall(r"'[a-z]\b", e))
    got_poly = len(re.findall(r"'[a-z]\b", g))
    if target_poly > 0:
        score += 0.5 * min(1.0, got_poly / target_poly)
    else:
        score += 0.25  # no poly required

    # Fewer anys is better when target has few
    target_any = e.count("any")
    got_any = g.count("any")
    if got_any <= target_any:
        score += 0.5
    elif target_any == 0:
        score += max(0.0, 0.5 - 0.1 * got_any)
    else:
        score += 0.5 * (target_any / got_any)

    return min(1.0, score)


def main() -> int:
    examples = sorted(EXAMPLES.glob("*.gtlc"))
    if not examples:
        print("no examples in /app/examples", file=sys.stderr)
        return 1

    # Ensure binary exists
    if not BIN.is_file():
        build = subprocess.run(
            ["cargo", "build", "--quiet"],
            cwd=TYPEWHICH,
            capture_output=True,
            text=True,
            timeout=600,
        )
        if build.returncode != 0:
            print(build.stderr, file=sys.stderr)
            print("cargo build failed", file=sys.stderr)
            return 1

    scores: list[float] = []
    for path in examples:
        name = path.name
        exp_path = EXPECTED / name
        print(f"=== {name} ===")
        ok, out = migrate(path)
        if not ok:
            print(f"FAIL migrate (unsound or crash):\n{out}")
            scores.append(0.0)
            continue
        if not exp_path.is_file():
            print(f"missing expected {exp_path}")
            scores.append(0.0)
            continue
        expected = exp_path.read_text()
        p = precision_score(out, expected)
        print(f"migration:\n{out.strip()}")
        print(f"precision={p:.3f}")
        scores.append(p)

    mean = sum(scores) / len(scores)
    print(f"mean_score={mean:.4f} over {len(scores)} examples")
    reward_path = Path("/logs/verifier/reward.txt")
    reward_path.parent.mkdir(parents=True, exist_ok=True)
    reward_path.write_text(f"{mean:.6f}\n")
    # Pass bar: all examples migrate soundly with decent precision
    return 0 if mean >= 0.99 else 1


if __name__ == "__main__":
    raise SystemExit(main())
