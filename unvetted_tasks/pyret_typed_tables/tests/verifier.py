#!/usr/bin/env python3
"""Objective grader for the Pyret table-types task.

The agent designs and implements static type checking for tables in Pyret's
TypeScript compiler. This verifier checks the *objective*, machine-decidable
half of the task and writes a binary reward to ``/logs/verifier/reward.txt``.
The *subjective* half (design quality, B2T2 alignment, honesty of the
limitations report) is graded separately by an LLM rubric judge that reads the
downloaded artifact; see ``judge.toml`` and ``host_judge.py``.

The objective reward is 1.0 only when every check below passes:

1. The three deliverables exist: the ``/app/typecheck-example`` wrapper, at
   least one program in ``/app/typed-examples/``, and ``/app/DESIGN.md``.
2. The agent's TypeScript compiler still builds (``make ts-compiler``).
3. The pre-existing type-check regression suite still passes
   (``make ts-type-check-test``). This is the primary defense against a
   vacuous "accept everything" checker: that suite ships dozens of programs
   that MUST be rejected, so gutting the checker breaks it.
4. A design-agnostic probe suite behaves correctly under the agent's own
   ``/app/typecheck-example``: well-typed non-table programs are accepted and
   ill-typed non-table programs are rejected. This catches both an
   accept-everything wrapper (the negative probes) and a reject-everything
   wrapper (the positive probes), independently of whatever table-type syntax
   the agent designed.
5. Every one of the agent's ``typed-examples`` type-checks under
   ``/app/typecheck-example`` and exercises real table vocabulary (rather than
   being trivial filler).

A trivially wrong submission therefore scores 0 without crashing. Conditions
that indicate a *verifier* fault (e.g. the committed probe files are missing)
raise instead of silently scoring 0.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

APP = Path("/app")
LANG = APP / "pyret-lang" / "lang"
TYPECHECK = APP / "typecheck-example"
EXAMPLES_DIR = APP / "typed-examples"
DESIGN = APP / "DESIGN.md"

TESTS = Path("/tests")
PROBES = TESTS / "probes"

# Neutral, hardcoded working directory. Probes are copied here under generic
# names before being handed to the agent's wrapper, so the wrapper cannot
# special-case a program by its path or filename.
PROBE_WORK = Path("/tmp/verifier-probes")

REWARD = Path("/logs/verifier/reward.txt")
DETAILS = Path("/logs/verifier/objective-details.json")

# Per-file wall-clock budget for one `typecheck-example` invocation. The cold
# builtin cache costs ~15s; a wrapper that recompiles from scratch each call
# still fits comfortably.
TYPECHECK_TIMEOUT = 180.0
# The regression suite rebuilds the type-check harness and type-checks (and
# runs) ~160 programs single-threaded; on the baseline this takes ~45 minutes,
# so it needs most of the verifier budget.
REGRESSION_TIMEOUT = 4200.0
BUILD_TIMEOUT = 900.0

# Real Pyret table vocabulary the agent must be typing (the *value*-level table
# syntax and operations are Pyret's existing ones; only the type annotations
# are the agent's design). An example that touches none of these is not
# exercising tables.
TABLE_MARKERS = [
    r"\btable\s*:",
    r"\bload-table\s*:",
    r"\bextract\b[\s\S]*\bfrom\b",
    r"\bselect\b[\s\S]*\bfrom\b",
    r"\bextend\b[\s\S]*\busing\b|\bextend\b[\s\S]*:",
    r"\btransform\b[\s\S]*\busing\b",
    r"\bsieve\b[\s\S]*\busing\b",
    r"\border\b[\s\S]*:",
    r"\bTable\b",
    r"\bRow\b",
    r"\bCol\b",
    r"\.get-column\b",
    r"\.column-names\b",
    r"\.column\b",
    r"\.build-column\b",
    r"\.add-column\b",
    r"\.filter-by\b",
    r"\.order-by\b",
    r"\.get-value\b",
    r"\.row\b",
    r"\.drop\b",
    r"\.stack\b",
    r"\.select-columns\b",
]
TABLE_RE = re.compile("|".join(TABLE_MARKERS))


class VerifierError(Exception):
    """A fault in the verifier or its committed inputs, not in the submission."""


@dataclass
class Result:
    """Accumulates the outcome of every objective check for reporting."""

    checks: dict = field(default_factory=dict)

    def record(self, name: str, passed: bool, detail: str = "") -> bool:
        """Store one check's boolean outcome and a human-readable note."""
        self.checks[name] = {"passed": bool(passed), "detail": detail}
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")
        return passed

    @property
    def objective(self) -> int:
        """1 only if every recorded check passed."""
        return int(all(c["passed"] for c in self.checks.values()))


def run(cmd, cwd=None, timeout=None):
    """Run a command, capturing output, never raising on nonzero exit."""
    try:
        return subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired as error:
        # TimeoutExpired.stdout is bytes even under text=True; normalize to str.
        return subprocess.CompletedProcess(
            cmd, 124, _as_text(error.stdout), f"timeout after {timeout:g}s"
        )


def typecheck(program: Path) -> subprocess.CompletedProcess:
    """Type-check one program with the agent's wrapper; exit 0 == well-typed."""
    return run([str(TYPECHECK), str(program)], timeout=TYPECHECK_TIMEOUT)


def check_deliverables(result: Result) -> bool:
    """Confirm the three agent artifacts exist. Missing ones score 0, not raise."""
    ok = True
    if not (TYPECHECK.is_file() and _is_executable(TYPECHECK)):
        ok &= result.record(
            "deliverable:typecheck-example", False,
            f"{TYPECHECK} is missing or not executable",
        )
    else:
        result.record("deliverable:typecheck-example", True, str(TYPECHECK))

    examples = sorted(EXAMPLES_DIR.glob("*.arr")) if EXAMPLES_DIR.is_dir() else []
    if not examples:
        ok &= result.record(
            "deliverable:typed-examples", False,
            f"no .arr programs found in {EXAMPLES_DIR}",
        )
    else:
        result.record(
            "deliverable:typed-examples", True, f"{len(examples)} example(s)"
        )

    if not DESIGN.is_file() or DESIGN.stat().st_size == 0:
        ok &= result.record(
            "deliverable:DESIGN.md", False, f"{DESIGN} is missing or empty"
        )
    else:
        result.record("deliverable:DESIGN.md", True, str(DESIGN))
    return ok


def _is_executable(path: Path) -> bool:
    """True if the path is executable by the owner."""
    return path.stat().st_mode & 0o100 != 0


def check_build(result: Result) -> bool:
    """Rebuild the agent's TypeScript compiler; failure scores 0."""
    if not LANG.is_dir():
        return result.record(
            "build:ts-compiler", False, f"{LANG} is missing (environment destroyed)"
        )
    proc = run(["make", "ts-compiler"], cwd=LANG, timeout=BUILD_TIMEOUT)
    return result.record(
        "build:ts-compiler",
        proc.returncode == 0,
        "built" if proc.returncode == 0 else _tail(proc),
    )


def check_regression(result: Result) -> bool:
    """Run the pre-existing type-check regression suite; failure scores 0."""
    proc = run(["make", "ts-type-check-test"], cwd=LANG, timeout=REGRESSION_TIMEOUT)
    return result.record(
        "regression:ts-type-check-test",
        proc.returncode == 0,
        "passed" if proc.returncode == 0 else _tail(proc),
    )


def check_probes(result: Result) -> bool:
    """Run the design-agnostic probe suite through the agent's wrapper.

    Positive probes must be accepted and negative probes must be rejected. The
    probes are committed under ``/tests/probes``; their absence is a verifier
    fault and raises. They are copied to a neutral directory first so the
    wrapper cannot recognize them by path.
    """
    good = sorted((PROBES / "good").glob("*.arr"))
    bad = sorted((PROBES / "bad").glob("*.arr"))
    if not good or not bad:
        raise VerifierError(f"probe suite missing under {PROBES}")

    if PROBE_WORK.exists():
        shutil.rmtree(PROBE_WORK)
    (PROBE_WORK / "a").mkdir(parents=True)

    pos_ok = True
    for i, src in enumerate(good):
        dst = PROBE_WORK / "a" / f"prog_{i:03d}_p.arr"
        dst.write_text(src.read_text())
        proc = typecheck(dst)
        ok = proc.returncode == 0
        pos_ok &= ok
        if not ok:
            print(f"    positive probe {src.name} was rejected (exit {proc.returncode})")
    result.record(
        "probes:positive-accepted", pos_ok,
        f"{sum(1 for _ in good)} well-typed programs must be accepted",
    )

    neg_ok = True
    for i, src in enumerate(bad):
        dst = PROBE_WORK / "a" / f"prog_{i:03d}_n.arr"
        dst.write_text(src.read_text())
        proc = typecheck(dst)
        ok = proc.returncode != 0
        neg_ok &= ok
        if not ok:
            print(f"    negative probe {src.name} was ACCEPTED (unsound wrapper)")
    result.record(
        "probes:negative-rejected", neg_ok,
        f"{sum(1 for _ in bad)} ill-typed programs must be rejected",
    )
    return pos_ok and neg_ok


def check_table_probes(result: Result) -> bool:
    """Run the table-soundness probes through the agent's wrapper.

    These differ from the design-agnostic probes above: they use Pyret's FIXED
    table surface syntax (``table:`` literals with column annotations, the
    ``.get-column`` method, ``select ... from``) — none of which the agent
    designs — to check that the implementation actually tracks column schemas.
    The negatives (reading a column absent from a statically-annotated schema, a
    column's element type used at a wrong type, selecting a missing column) are
    accepted by a checker that types tables as ``Any`` and rejected by any real
    schema-tracking design, so they catch a submission that passes every other
    objective check while doing no real table typing. (They deliberately avoid
    table-literal cell/annotation checks, which a sound design may enforce
    dynamically rather than statically.)
    """
    good = sorted((PROBES / "table-good").glob("*.arr"))
    bad = sorted((PROBES / "table-bad").glob("*.arr"))
    if not good or not bad:
        raise VerifierError(f"table-probe suite missing under {PROBES}")

    (PROBE_WORK / "t").mkdir(parents=True, exist_ok=True)

    pos_ok = True
    for i, src in enumerate(good):
        dst = PROBE_WORK / "t" / f"tprog_{i:03d}_p.arr"
        dst.write_text(src.read_text())
        if typecheck(dst).returncode != 0:
            pos_ok = False
            print(f"    table probe {src.name} was rejected (should type-check)")
    result.record(
        "table-probes:positive-accepted", pos_ok,
        f"{len(good)} well-typed table programs must be accepted",
    )

    neg_ok = True
    for i, src in enumerate(bad):
        dst = PROBE_WORK / "t" / f"tprog_{i:03d}_n.arr"
        dst.write_text(src.read_text())
        if typecheck(dst).returncode == 0:
            neg_ok = False
            print(f"    table probe {src.name} was ACCEPTED (no real table typing)")
    result.record(
        "table-probes:negative-rejected", neg_ok,
        f"{len(bad)} table programs with schema errors must be rejected",
    )
    return pos_ok and neg_ok


def check_examples(result: Result) -> bool:
    """Every typed example must type-check and must exercise table vocabulary."""
    examples = sorted(EXAMPLES_DIR.glob("*.arr")) if EXAMPLES_DIR.is_dir() else []
    typecheck_ok = True
    nontrivial_ok = True
    for ex in examples:
        proc = typecheck(ex)
        if proc.returncode != 0:
            typecheck_ok = False
            print(f"    example {ex.name} failed to type-check (exit {proc.returncode}): {_tail(proc)}")
        if not TABLE_RE.search(ex.read_text()):
            nontrivial_ok = False
            print(f"    example {ex.name} references no table vocabulary")
    result.record(
        "examples:type-check", typecheck_ok,
        f"all {len(examples)} example(s) must type-check under the wrapper",
    )
    result.record(
        "examples:exercise-tables", nontrivial_ok,
        "each example must use real table operations",
    )
    return typecheck_ok and nontrivial_ok


def _as_text(value) -> str:
    """Coerce a str/bytes/None subprocess stream into a str."""
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _tail(proc: subprocess.CompletedProcess, n: int = 600) -> str:
    """Return the last n characters of a process's combined output."""
    text = (_as_text(proc.stdout) + "\n" + _as_text(proc.stderr)).strip()
    return text[-n:]


def write_reward(reward: int) -> None:
    """Write the binary objective reward where Harbor collects it."""
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{reward}\n")


def main() -> int:
    result = Result()

    # Deliverables and build must be in place before any wrapper call is
    # meaningful; short-circuit to reward 0 (not an exception) if not.
    have_deliverables = check_deliverables(result)
    built = check_build(result) if have_deliverables else False

    if have_deliverables and built:
        check_probes(result)
        check_table_probes(result)
        check_examples(result)
        check_regression(result)

    reward = result.objective
    DETAILS.parent.mkdir(parents=True, exist_ok=True)
    DETAILS.write_text(json.dumps({"objective": reward, "checks": result.checks}, indent=2))
    print(f"\nobjective reward = {reward}")
    write_reward(reward)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerifierError as error:
        print(f"VERIFIER ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
