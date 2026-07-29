#!/usr/bin/env python3
"""Bundle submitted Lean sources for the semantic-quality judge."""

from pathlib import Path

from verifier import collect_submission_sources, local_dependency_order

APP = Path("/app")
OUTPUT = Path("/tmp/scheme-semantics-submission.txt")
TRUSTED_SOURCES = {APP / "SemanticsTemplate.lean", APP / "TestRunner.lean"}


def submitted_sources() -> list[Path]:
    """Return the submitted dependency closure, with a safe audit fallback."""
    try:
        sources = collect_submission_sources()
        order, _ = local_dependency_order("Semantics", sources)
        return [sources[name] for name in order]
    except Exception:
        return [
            path
            for path in sorted(APP.rglob("*.lean"))
            if path not in TRUSTED_SOURCES and path.is_file() and not path.is_symlink()
        ]


def main() -> None:
    """Write a labeled UTF-8 bundle of all potentially relevant source files."""
    with OUTPUT.open("w", encoding="utf-8") as bundle:
        for path in submitted_sources():
            bundle.write(f"\n===== {path} =====\n")
            bundle.write(path.read_text(encoding="utf-8"))
            bundle.write("\n")


if __name__ == "__main__":
    main()
