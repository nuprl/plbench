#!/usr/bin/env python3
"""Grade safe, compatible, and precise GTLC migrations."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from gtlc import (
    Ann,
    Expr,
    ParseError,
    StaticError,
    all_lambdas_annotated,
    apply_args,
    elaborate,
    parse,
    precision_points,
    precision_score,
    run,
    structurally_equal,
    type_leq,
)


MIGRATE = Path("/app/migrate")
CHALLENGES = Path("/tests/challenges")
EXPECTED = Path("/tests/expected")
CONTEXTS = Path("/tests/contexts")
REWARD = Path("/logs/verifier/reward.txt")

ARGUMENT_SOURCES = [
    "0",
    "1",
    "true",
    "false",
    "fun x . x",
    "fun x . 0",
    "fun x . true",
    "fun x . fun y . x",
    "fun x . fun y . y",
    "fun f . fun x . f x",
    "fun x . x x",
]
ARGUMENTS = [parse(src) for src in ARGUMENT_SOURCES]


class VerifierError(RuntimeError):
    pass


def write_reward(score: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{score:.6f}\n")


def invoke_migrator(path: Path) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            [str(MIGRATE), str(path)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        return False, "migration timed out after 15 seconds"
    except OSError as exc:
        return False, f"could not execute /app/migrate: {exc}"
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        return False, f"migration exited {completed.returncode}: {detail[:500]}"
    if len(completed.stdout.encode()) > 1_000_000:
        return False, "migration output exceeds 1 MB"
    return True, completed.stdout


def extra_contexts(stem: str) -> list[list[Expr]]:
    path = CONTEXTS / f"{stem}.json"
    if not path.is_file():
        return []
    try:
        raw = json.loads(path.read_text())
        if not isinstance(raw, list):
            raise ValueError("top level is not a list")
        return [[parse(item) for item in sequence] for sequence in raw]
    except (ValueError, ParseError, TypeError) as exc:
        raise VerifierError(f"invalid context fixture {path.name}: {exc}") from exc


def generated_probes(original: Expr, extras: list[list[Expr]]) -> list[tuple[list[Expr], object]]:
    """Explore calls to function results, extending only successful prefixes."""
    probes: list[tuple[list[Expr], object]] = []
    queue: list[list[Expr]] = [[]]
    seen: set[tuple[str, ...]] = set()
    while queue:
        args = queue.pop(0)
        key = tuple(repr(a) for a in args)
        if key in seen:
            continue
        seen.add(key)
        outcome = run(apply_args(original, args))
        probes.append((args, outcome))
        if outcome.kind == "function" and len(args) < 3:  # type: ignore[attr-defined]
            queue.extend(args + [arg] for arg in ARGUMENTS)
    for args in extras:
        key = tuple(repr(a) for a in args)
        if key not in seen:
            probes.append((args, run(apply_args(original, args))))
            seen.add(key)
    return probes


def compatibility_failure(
    original: Expr,
    migrated: Expr,
    probes: list[tuple[list[Expr], object]],
) -> str | None:
    direct_original = run(original)
    direct_migrated = run(migrated)
    if direct_original != direct_migrated:
        return f"empty context changed {direct_original} to {direct_migrated}"
    for args, expected_outcome in probes:
        actual = run(apply_args(migrated, args))
        if actual != expected_outcome:
            rendered_args = ", ".join(repr(a) for a in args) or "<none>"
            return f"calling context [{rendered_args}] changed {expected_outcome} to {actual}"
    return None


def validate_candidate(original: Expr, migrated: Expr) -> tuple[bool, str, object | None]:
    if not structurally_equal(original, migrated):
        return False, "output changes program structure after annotations are erased", None
    if not all_lambdas_annotated(migrated):
        return False, "not every lambda parameter is annotated", None
    try:
        original_type, _ = elaborate(original)
        migrated_type, _ = elaborate(migrated)
    except StaticError as exc:
        return False, f"static error: {exc}", None
    if not type_leq(original_type, migrated_type):
        return False, f"result type {migrated_type} is not at least as precise as {original_type}", None
    return True, "", migrated_type


def load_fixture(path: Path) -> tuple[Expr, Expr, list[tuple[list[Expr], object]]]:
    expected_path = EXPECTED / path.name
    if not expected_path.is_file():
        raise VerifierError(f"missing oracle migration {expected_path}")
    try:
        original = parse(path.read_text())
        expected = parse(expected_path.read_text())
    except ParseError as exc:
        raise VerifierError(f"trusted fixture {path.name} does not parse: {exc}") from exc
    if any(t is not None for t in lambda_types_with_missing(original)):
        raise VerifierError(f"input fixture {path.name} contains an annotation")
    valid, reason, _ = validate_candidate(original, expected)
    if not valid:
        raise VerifierError(f"oracle migration {path.name} is invalid: {reason}")
    probes = generated_probes(original, extra_contexts(path.stem))
    failure = compatibility_failure(original, expected, probes)
    if failure:
        raise VerifierError(f"oracle migration {path.name} is unsafe: {failure}")
    return original, expected, probes


def lambda_types_with_missing(expr: Expr) -> list[object | None]:
    """Like lambda_types, but retains missing annotations for input validation."""
    from gtlc import App, Bin, Fun, If, Let, Lit, Var

    while isinstance(expr, Ann):
        expr = expr.expr
    if isinstance(expr, (Lit, Var)):
        return []
    if isinstance(expr, Fun):
        return [expr.annotation] + lambda_types_with_missing(expr.body)
    if isinstance(expr, App):
        return lambda_types_with_missing(expr.fn) + lambda_types_with_missing(expr.arg)
    if isinstance(expr, Bin):
        return lambda_types_with_missing(expr.left) + lambda_types_with_missing(expr.right)
    if isinstance(expr, If):
        return lambda_types_with_missing(expr.cond) + lambda_types_with_missing(expr.then) + lambda_types_with_missing(expr.otherwise)
    if isinstance(expr, Let):
        return lambda_types_with_missing(expr.value) + lambda_types_with_missing(expr.body)
    raise AssertionError(expr)


def main() -> int:
    if not MIGRATE.is_file() or not MIGRATE.stat().st_mode & 0o111:
        print("missing executable /app/migrate", file=sys.stderr)
        write_reward(0.0)
        return 1

    paths = sorted(CHALLENGES.glob("*.gtlc"))
    if not paths:
        print("VERIFIER ERROR: no challenge programs", file=sys.stderr)
        return 1

    try:
        fixtures = [(path, *load_fixture(path)) for path in paths]
    except VerifierError as exc:
        print(f"VERIFIER ERROR: {exc}", file=sys.stderr)
        return 1

    safe_count = 0
    precision_earned = 0
    precision_possible = 0
    for path, original, target, probes in fixtures:
        _, target_possible = precision_points(target, target)
        precision_possible += target_possible
        ok, output = invoke_migrator(path)
        if not ok:
            print(f"{path.name}: FAIL — {output}")
            continue
        try:
            migrated = parse(output)
        except ParseError as exc:
            print(f"{path.name}: FAIL — output parse error: {exc}")
            continue
        valid, reason, migrated_type = validate_candidate(original, migrated)
        if not valid:
            print(f"{path.name}: FAIL — {reason}")
            continue
        failure = compatibility_failure(original, migrated, probes)
        if failure:
            print(f"{path.name}: FAIL — incompatible: {failure}")
            continue
        safe_count += 1
        earned, possible = precision_points(migrated, target)
        precision_earned += earned
        precision = precision_score(migrated, target)
        print(
            f"{path.name}: PASS — compatible; type={migrated_type}; "
            f"precision={earned}/{possible} ({precision:.3f}); contexts={len(probes) + 1}"
        )

    safety_score = safe_count / len(fixtures)
    precision_component = (
        precision_earned / precision_possible if precision_possible else 1.0
    )
    mean = 0.5 * safety_score + 0.5 * precision_component
    print(
        f"mean_score={mean:.4f} "
        f"(safety={safe_count}/{len(fixtures)}={safety_score:.4f}; "
        f"precision={precision_earned}/{precision_possible}={precision_component:.4f})"
    )
    write_reward(mean)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
