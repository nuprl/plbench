#!/usr/bin/env python3
"""Host-side subjective grader for the Pyret table-types task.

This is the credential-light half of the rubric grading. On hosts that have a
Claude Code OAuth token but no model API key, it grades the SAME criteria that
``judge.toml`` defines (it parses that file, so the two graders cannot drift)
with a single headless ``claude -p`` call, run against a DOWNLOADED artifact
directory rather than inside the verifier container.

It never runs inside the Harbor container: the objective verifier
(``verifier.py``) produces the in-container reward; this reads the downloaded
``/app`` afterwards on the host.

Usage:

    export CLAUDE_CODE_OAUTH_TOKEN=...        # from the running session's env
    python3 host_judge.py \\
        --app /path/to/downloaded/app \\
        --parent-commit 043ceab4422ac5ad9479650ec1d47d23bd70b3d4 \\
        --out /path/to/subjective.json

The artifact directory is expected to contain ``DESIGN.md``, ``typed-examples/``,
and (optionally, for the diff) the ``pyret-lang`` checkout with its git history.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tomllib
from pathlib import Path

# Keep the prompt within a comfortable context budget.
MAX_DIFF_CHARS = 150_000
MAX_EXAMPLE_CHARS = 20_000
MAX_DESIGN_CHARS = 120_000


def load_criteria(judge_toml: Path) -> list[dict]:
    """Parse the shared rubric file into an ordered list of criteria."""
    data = tomllib.loads(judge_toml.read_text())
    criteria = data.get("criterion", [])
    if not criteria:
        raise SystemExit(f"no [[criterion]] blocks in {judge_toml}")
    return criteria


def read_capped(path: Path, cap: int) -> str:
    """Read a text file, truncating to `cap` characters with a marker."""
    text = path.read_text(errors="replace")
    if len(text) > cap:
        text = text[:cap] + f"\n...[truncated at {cap} chars]...\n"
    return text


def collect_examples(app: Path) -> str:
    """Concatenate every typed example program, each capped and labeled."""
    examples = sorted((app / "typed-examples").glob("*.arr"))
    if not examples:
        return "(no typed examples found)"
    blocks = []
    for ex in examples:
        blocks.append(f"----- {ex.name} -----\n{read_capped(ex, MAX_EXAMPLE_CHARS)}")
    return "\n\n".join(blocks)


def collect_diff(app: Path, parent_commit: str) -> str:
    """Best-effort git diff of the agent's changes against the baseline commit."""
    repo = app / "pyret-lang"
    if not (repo / ".git").exists():
        return "(diff unavailable: no git history in the downloaded artifact)"
    proc = subprocess.run(
        ["git", "-C", str(repo), "diff", parent_commit, "--", "."],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return f"(diff unavailable: git diff failed: {proc.stderr.strip()[:300]})"
    diff = proc.stdout
    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS] + f"\n...[diff truncated at {MAX_DIFF_CHARS} chars]...\n"
    return diff or "(empty diff)"


def build_prompt(criteria: list[dict], design: str, examples: str, diff: str) -> str:
    """Assemble the single grading prompt, requesting strict JSON output."""
    lines = [
        "You are grading a submission to a programming-languages design task: the",
        "author was asked to design and implement sound static type checking for",
        "tables in the Pyret language's TypeScript compiler, philosophically aligned",
        'with the B2T2 benchmark ("Types for Tables: A Language Design Benchmark",',
        "arXiv:2111.10412) and able to type realistic table operations from the",
        "Bootstrap core.arr library.",
        "",
        "Grade STRICTLY on the following criteria. For each, give a score in [0.0, 1.0]",
        "(1.0 = fully meets the criterion, 0.0 = not at all) and one to three sentences",
        "of specific justification grounded in the material below.",
        "",
        "CRITERIA:",
    ]
    for c in criteria:
        lines.append(f'- id "{c["id"]}" (weight {c.get("weight", 1.0)}): {" ".join(c["description"].split())}')
    lines += [
        "",
        "Base your judgment on the actual DESIGN REPORT, TYPED EXAMPLES, and DIFF below,",
        "not on the report's claims alone. If the diff or examples contradict the",
        "report, weight what the code actually does.",
        "",
        "Respond with ONLY a JSON object, no markdown fences, of the form:",
        '{ "<criterion id>": {"score": <float>, "reasoning": "<text>"}, ... }',
        "with exactly one entry per criterion id listed above.",
        "",
        "===== DESIGN REPORT (DESIGN.md) =====",
        design,
        "",
        "===== TYPED EXAMPLES =====",
        examples,
        "",
        "===== DIFF AGAINST BASELINE COMPILER =====",
        diff,
    ]
    return "\n".join(lines)


def run_claude(prompt: str, model: str) -> dict:
    """Run one headless `claude -p` call and return the parsed inner JSON.

    Retries once on an unparseable response; a second failure raises, because a
    judge that cannot be scored is a grader fault, not a zero.
    """
    for attempt in (1, 2):
        # Pass the (large) prompt on stdin, not as an argv entry: DESIGN.md +
        # examples + diff easily exceed the OS argument-length limit.
        proc = subprocess.run(
            ["claude", "-p", "--model", model, "--output-format", "json"],
            capture_output=True, text=True, input=prompt, timeout=300,
        )
        if proc.returncode != 0:
            last = f"claude exited {proc.returncode}: {proc.stderr.strip()[:400]}"
            continue
        try:
            envelope = json.loads(proc.stdout)
            if envelope.get("is_error"):
                last = f"claude reported is_error: {envelope.get('result', '')[:300]}"
                continue
            return json.loads(envelope["result"])
        except (json.JSONDecodeError, KeyError) as error:
            last = f"unparseable judge output ({error})"
    raise RuntimeError(f"judge failed after 2 attempts: {last}")


def score(criteria: list[dict], graded: dict) -> tuple[float, dict]:
    """Compute the weighted-mean subjective reward and a per-criterion detail map."""
    total_w = 0.0
    acc = 0.0
    detail = {}
    for c in criteria:
        cid = c["id"]
        w = float(c.get("weight", 1.0))
        entry = graded.get(cid)
        if not entry or "score" not in entry:
            raise RuntimeError(f"judge omitted criterion '{cid}'")
        s = max(0.0, min(1.0, float(entry["score"])))
        acc += w * s
        total_w += w
        detail[cid] = {"score": s, "weight": w, "reasoning": entry.get("reasoning", "")}
    return (acc / total_w if total_w else 0.0), detail


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, type=Path)
    ap.add_argument("--judge-toml", type=Path, default=Path(__file__).with_name("judge.toml"))
    ap.add_argument("--parent-commit", default="043ceab4422ac5ad9479650ec1d47d23bd70b3d4")
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    design_path = args.app / "DESIGN.md"
    if not design_path.is_file():
        raise SystemExit(f"no DESIGN.md under {args.app}")

    criteria = load_criteria(args.judge_toml)
    prompt = build_prompt(
        criteria,
        read_capped(design_path, MAX_DESIGN_CHARS),
        collect_examples(args.app),
        collect_diff(args.app, args.parent_commit),
    )
    graded = run_claude(prompt, args.model)
    subjective, detail = score(criteria, graded)

    out = {"subjective": subjective, "criteria": detail}
    args.out.write_text(json.dumps(out, indent=2))
    print(json.dumps(out, indent=2))
    print(f"\nsubjective reward = {subjective:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
