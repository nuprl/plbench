#!/usr/bin/env python3
"""Verify the submitted semantics development and its observable behavior."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess


APP = Path("/app")
EXAMPLE = Path("/example")
TESTS = Path("/tests")
REWARD = Path("/logs/verifier/deterministic-reward.txt")
WORK = Path("/tmp/scheme-semantics-verifier")
LEAN_WORK = WORK / "lean"
REFERENCE_ORIGINAL = WORK / "reference-original"
CASES = TESTS / "cases"

TRUSTED_MD5 = {
    APP / "SemanticsTemplate.lean": "611ea96f18d8366d2f77611f3a82e289",
    APP / "TestRunner.lean": "4b8c962ccd44176c86a8ae33ff7145a0",
    APP / "test.sh": "b5c004145a96ff8cf028caa525ea65d7",
    APP / "example-test" / "01-arithmetic.scm": "b77da2e154a137fd1b7d30b8ab698bd0",
    APP / "example-test" / "expected.txt": "acd2a756b9298664cd5ce319cf3bcf98",
    APP / "MiniScheme.md": "9ec7d92524c84a531b4fc9e895ee1a66",
    APP / "minischeme-reference" / "README.md": "1e3fa3d42ef9dbda51a93c1396814b44",
    APP / "minischeme-reference" / "ast.ml": "be4aa2a79d0129e15e4a46920e1a06bf",
    APP / "minischeme-reference" / "checker.ml": "5a653398349d00017975c36a991d2cba",
    APP / "minischeme-reference" / "dune": "8ee812fd0b2df2346f2d901c2ba9c551",
    APP / "minischeme-reference" / "dune-project": "fbb8fb0b9ec3f3896ab71677719b87a4",
    APP / "minischeme-reference" / "interp.ml": "ed54d6c2d79b185afee9ff24341a4655",
    APP / "minischeme-reference" / "lexer.mll": "a7967deb838dfc653a3b91dfa3ccf937",
    APP / "minischeme-reference" / "main.ml": "748ae13778a8e05d4d39b05edb93562a",
    APP / "minischeme-reference" / "parser.mly": "7d2bbdcd07cfa113e9f6ba13d14591fa",
    EXAMPLE / "README.md": "df97d8ae53deeacfffd7559e9bff75a1",
    EXAMPLE / "Semantics.lean": "9ef21dd4a4d5b44ba3b7ffc608c670e4",
    EXAMPLE / "examples" / "arithmetic.miniml": "41aab5e3713003ee43ea17c58f0aa264",
    EXAMPLE / "examples" / "closure.miniml": "faaafe4cafad5cb27c7e97e524a1c3ec",
    EXAMPLE / "examples" / "conditional.miniml": "8aede26cc79ec58d4d3968f7607820b3",
    EXAMPLE / "examples" / "higher-order.miniml": "ec8d6549bd165177ea0268c56a019da0",
    EXAMPLE / "examples" / "type-error.miniml": "43646ca40f9c447951940d4ce93bd163",
    EXAMPLE / "impl" / "README.md": "17c2ef9c7e490ded0fd554cb447fa82c",
    EXAMPLE / "impl" / "dune": "5570f3cce694be8c1dc4c378c894a4a0",
    EXAMPLE / "impl" / "dune-project": "73d2c29c29e8b7616580e4c165195498",
    EXAMPLE / "impl" / "main.ml": "f6453a54b8ee0f87ebb08703e429f090",
}

REFERENCE_FILENAMES = (
    "README.md",
    "ast.ml",
    "checker.ml",
    "dune",
    "dune-project",
    "interp.ml",
    "lexer.mll",
    "main.ml",
    "parser.mly",
)

TRUSTED_MODULES = {"SemanticsTemplate", "TestRunner"}


class SubmissionFailure(Exception):
    """A normal zero-reward failure attributable to the submission."""


def write_reward(value: int) -> None:
    """Write an integral Harbor reward."""
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{value}\n")


def md5(path: Path) -> str:
    """Compute the hexadecimal MD5 digest of a regular file."""
    if not path.is_file() or path.is_symlink():
        return ""
    return hashlib.md5(path.read_bytes()).hexdigest()


def verify_trusted_inputs() -> None:
    """Reject changes to the template, example, specification, or OCaml source."""
    for path, expected in TRUSTED_MD5.items():
        if md5(path) != expected:
            raise SubmissionFailure(f"trusted file was modified: {path}")


def reset_work_directory() -> None:
    """Create the verifier's fixed, clean work directory."""
    if WORK.exists():
        shutil.rmtree(WORK)
    LEAN_WORK.mkdir(parents=True)


def strip_lean_comments_and_strings(source: str, filename: str) -> str:
    """Blank Lean comments and strings while preserving token boundaries."""
    output: list[str] = []
    index = 0
    block_depth = 0
    in_string = False
    while index < len(source):
        if block_depth:
            if source.startswith("/-", index):
                block_depth += 1
                output.extend("  ")
                index += 2
            elif source.startswith("-/", index):
                block_depth -= 1
                output.extend("  ")
                index += 2
            else:
                output.append("\n" if source[index] == "\n" else " ")
                index += 1
        elif in_string:
            if source[index] == "\\" and index + 1 < len(source):
                output.extend("  ")
                index += 2
            elif source[index] == '"':
                in_string = False
                output.append(" ")
                index += 1
            else:
                output.append("\n" if source[index] == "\n" else " ")
                index += 1
        elif source.startswith("--", index):
            newline = source.find("\n", index)
            if newline == -1:
                output.extend(" " * (len(source) - index))
                break
            output.extend(" " * (newline - index))
            output.append("\n")
            index = newline + 1
        elif source.startswith("/-", index):
            block_depth = 1
            output.extend("  ")
            index += 2
        elif source[index] == '"':
            in_string = True
            output.append(" ")
            index += 1
        else:
            output.append(source[index])
            index += 1
    if block_depth or in_string:
        raise SubmissionFailure(f"unterminated comment or string in {filename}")
    return "".join(output)


def inspect_source(source: str, filename: str) -> str:
    """Strip inert text and reject explicit proof holes in submitted source."""
    stripped = strip_lean_comments_and_strings(source, filename)
    words = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", stripped))
    proof_holes = sorted(words & {"admit", "sorry"})
    if proof_holes:
        raise SubmissionFailure(
            f"proof hole(s) in {filename}: " + ", ".join(proof_holes)
        )
    return stripped


def module_name(path: Path) -> str | None:
    """Return a valid Lean module name for a source path below `/app`."""
    relative = path.relative_to(APP).with_suffix("")
    parts = relative.parts
    if not parts or any(
        re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", part) is None for part in parts
    ):
        return None
    return ".".join(parts)


def collect_submission_sources() -> dict[str, Path]:
    """Index regular submitted Lean sources by their importable module names."""
    sources: dict[str, Path] = {}
    for path in sorted(APP.rglob("*.lean")):
        name = module_name(path)
        if name is None or name in TRUSTED_MODULES:
            continue
        if not path.is_file() or path.is_symlink():
            continue
        sources[name] = path
    if "Semantics" not in sources:
        raise SubmissionFailure("Semantics.lean is required")
    return sources


def reject_library_module_shadowing(sources: dict[str, Path]) -> None:
    """Reject local source names that collide with installed Lean modules."""
    completed = subprocess.run(
        ["lean", "--print-prefix"], capture_output=True, text=True, timeout=30
    )
    if completed.returncode != 0:
        raise RuntimeError("could not determine the trusted Lean installation prefix")
    library = Path(completed.stdout.strip()) / "lib" / "lean"
    if not library.is_dir():
        raise RuntimeError(f"trusted Lean library directory is missing: {library}")
    for name, path in sources.items():
        installed = library.joinpath(*name.split(".")).with_suffix(".olean")
        if installed.is_file():
            raise SubmissionFailure(
                f"submitted module shadows installed Lean module {name}: {path}"
            )


def source_imports(source: str, filename: str) -> list[str]:
    """Extract ordinary Lean module imports from stripped source text."""
    stripped = inspect_source(source, filename)
    imports: list[str] = []
    for group in re.findall(
        r"(?m)^\s*(?:public\s+)?import\s+(.+?)\s*$", stripped
    ):
        for name in group.split():
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", name) is None:
                raise SubmissionFailure(f"unrecognized import in {filename}: {name}")
            imports.append(name)
    return imports


def local_dependency_order(
    root: str, sources: dict[str, Path]
) -> tuple[list[str], set[str]]:
    """Topologically order the submitted modules reachable from one root."""
    order: list[str] = []
    dependencies: set[str] = set()
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(name: str) -> None:
        if name in visited or name not in sources:
            return
        if name in visiting:
            raise SubmissionFailure(f"cyclic local Lean imports involving {name}")
        visiting.add(name)
        path = sources[name]
        for dependency in source_imports(path.read_text(), str(path.relative_to(APP))):
            dependencies.add(dependency)
            visit(dependency)
        visiting.remove(name)
        visited.add(name)
        order.append(name)

    visit(root)
    return order, dependencies


def lean_environment() -> dict[str, str]:
    """Return an environment that resolves the sanitized Lean build first."""
    environment = os.environ.copy()
    environment["LEAN_PATH"] = str(LEAN_WORK)
    return environment


def run_checked(
    command: list[str], cwd: Path, timeout: int
) -> subprocess.CompletedProcess[bytes]:
    """Run trusted infrastructure and raise on any failure."""
    completed = subprocess.run(command, cwd=cwd, capture_output=True, timeout=timeout)
    if completed.returncode != 0:
        raise RuntimeError(
            f"trusted command failed: {' '.join(command)}\n"
            + completed.stdout.decode(errors="replace")
            + completed.stderr.decode(errors="replace")
        )
    return completed


def run_lean_compile(filename: str, timeout: int, trusted: bool) -> None:
    """Compile one Lean module, classifying trusted and submission failures."""
    completed = subprocess.run(
        ["lean", "-o", str(Path(filename).with_suffix(".olean")), filename],
        cwd=LEAN_WORK,
        capture_output=True,
        env=lean_environment(),
        timeout=timeout,
    )
    print(completed.stdout.decode(errors="replace"), end="")
    print(completed.stderr.decode(errors="replace"), end="")
    if completed.returncode == 0:
        return
    if trusted:
        raise RuntimeError(f"trusted {filename} failed to compile")
    raise SubmissionFailure(f"{filename} did not compile")


def compile_development(order: list[str], sources: dict[str, Path]) -> None:
    """Compile the trusted template and submitted dependency closure cleanly."""
    shutil.copyfile(APP / "SemanticsTemplate.lean", LEAN_WORK / "SemanticsTemplate.lean")
    run_lean_compile("SemanticsTemplate.lean", 30, trusted=True)
    for name in order:
        source = sources[name]
        relative = source.relative_to(APP)
        destination = LEAN_WORK / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        run_lean_compile(str(relative), 480, trusted=False)


def run_inspector() -> None:
    """Check the required top-level declarations and recursive axiom set."""
    completed = subprocess.run(
        ["lean", "--run", str(TESTS / "InspectSemantics.lean")],
        cwd=LEAN_WORK,
        capture_output=True,
        env=lean_environment(),
        timeout=60,
    )
    print(completed.stdout.decode(errors="replace"), end="")
    print(completed.stderr.decode(errors="replace"), end="")
    if completed.returncode != 0:
        raise SubmissionFailure("Lean declaration and axiom inspection failed")


def compile_trusted_runner() -> None:
    """Compile the trusted development runner after the submitted module."""
    shutil.copyfile(APP / "TestRunner.lean", LEAN_WORK / "TestRunner.lean")
    run_lean_compile("TestRunner.lean", 60, trusted=True)


def prepare_reference_implementation() -> Path:
    """Build the preserved Mini-Scheme CLI from verified source files only."""
    source = APP / "minischeme-reference"
    REFERENCE_ORIGINAL.mkdir()
    for filename in REFERENCE_FILENAMES:
        shutil.copyfile(source / filename, REFERENCE_ORIGINAL / filename)
    run_checked(
        ["dune", "build", "--profile", "release", "main.exe"],
        REFERENCE_ORIGINAL,
        120,
    )
    return REFERENCE_ORIGINAL / "_build" / "default" / "main.exe"


def reference_failure_status(
    completed: subprocess.CompletedProcess[bytes], program: Path
) -> str:
    """Classify one reference failure by its trusted diagnostic prefix."""
    try:
        diagnostic = completed.stderr.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(
            f"reference emitted invalid UTF-8 diagnostic for {program.name}"
        ) from error
    for prefix, status in (
        ("parse error:", "PARSE"),
        ("static error:", "STATIC"),
        ("runtime error:", "RUNTIME"),
    ):
        if diagnostic.startswith(prefix):
            return status
    raise RuntimeError(
        f"reference produced an unclassified failure for {program.name}: "
        + diagnostic
    )


def run_reference_case(original: Path, program: Path) -> tuple[str, str]:
    """Record static acceptance and the observable output of execution."""
    try:
        checked = subprocess.run(
            [str(original), "--check", str(program)],
            cwd=REFERENCE_ORIGINAL,
            capture_output=True,
            timeout=30,
        )
        completed = subprocess.run(
            [str(original), str(program)],
            cwd=REFERENCE_ORIGINAL,
            capture_output=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"reference timed out on {program.name}") from error

    if checked.stdout:
        raise RuntimeError(f"reference --check wrote stdout for {program.name}")
    if checked.returncode != 0:
        check_status = reference_failure_status(checked, program)
        if check_status not in {"PARSE", "STATIC"}:
            raise RuntimeError(
                f"reference --check reported {check_status} for {program.name}"
            )
        run_status = reference_failure_status(completed, program)
        if run_status != check_status or completed.stdout:
            raise RuntimeError(
                f"normal execution did not reproduce {check_status} for {program.name}"
            )
        return "REJECT", ""

    if checked.stderr:
        raise RuntimeError(f"successful reference --check wrote stderr for {program.name}")
    try:
        output = completed.stdout.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"reference emitted invalid UTF-8 for {program.name}") from error
    if completed.returncode != 0:
        status = reference_failure_status(completed, program)
        if status != "RUNTIME":
            raise RuntimeError(
                f"a check-accepted program produced {status} for {program.name}"
            )
    elif completed.stderr:
        raise RuntimeError(
            f"successful reference execution wrote stderr for {program.name}"
        )
    return "TERMINATED", output


def parse_header(data: bytes, cursor: int, label: bytes) -> tuple[int, int]:
    """Parse one ASCII length header and return its length and next cursor."""
    newline = data.find(b"\n", cursor)
    if newline == -1:
        raise SubmissionFailure("truncated Lean runner output header")
    line = data[cursor:newline]
    prefix = label + b" "
    if not line.startswith(prefix):
        raise SubmissionFailure(f"expected {label.decode()} output header")
    try:
        length = int(line[len(prefix) :])
    except ValueError as error:
        raise SubmissionFailure("invalid Lean runner output length") from error
    if length < 0:
        raise SubmissionFailure("negative Lean runner output length")
    return length, newline + 1


def parse_lean_output(data: bytes, count: int) -> list[tuple[str, str]]:
    """Decode the trusted runner's status and byte-length-framed outputs."""
    cursor = 0
    observations: list[tuple[str, str]] = []
    for index in range(count):
        expected_case = f"CASE {index}\n".encode()
        if data[cursor : cursor + len(expected_case)] != expected_case:
            raise SubmissionFailure(f"missing Lean runner record {index}")
        cursor += len(expected_case)
        newline = data.find(b"\n", cursor)
        if newline == -1 or not data[cursor:newline].startswith(b"STATUS "):
            raise SubmissionFailure("missing Lean runner status")
        try:
            status = data[cursor + len(b"STATUS ") : newline].decode("ascii")
        except UnicodeDecodeError as error:
            raise SubmissionFailure("invalid Lean runner status") from error
        if status not in {"REJECT", "TERMINATED", "FUEL"}:
            raise SubmissionFailure("unknown Lean runner status")
        cursor = newline + 1
        output_length, cursor = parse_header(data, cursor, b"OUTPUT")
        output_bytes = data[cursor : cursor + output_length]
        cursor += output_length
        try:
            observations.append((status, output_bytes.decode("utf-8")))
        except UnicodeDecodeError as error:
            raise SubmissionFailure("Lean runner emitted invalid UTF-8") from error
    if cursor != len(data):
        raise SubmissionFailure("unexpected extra Lean runner output")
    return observations


def run_lean_runner(programs: list[Path]) -> list[tuple[str, str]]:
    """Run the public trusted runner on the held-out case directory."""
    completed = subprocess.run(
        ["lean", "--run", "TestRunner.lean", str(CASES)],
        cwd=LEAN_WORK,
        capture_output=True,
        env=lean_environment(),
        timeout=300,
    )
    print(completed.stderr.decode(errors="replace"), end="")
    if completed.returncode != 0:
        raise SubmissionFailure("trusted runner failed on the terminating corpus")
    return parse_lean_output(completed.stdout, len(programs))


def compare_observations(
    programs: list[Path],
    expected: list[tuple[str, str]],
    actual: list[tuple[str, str]],
) -> None:
    """Require static acceptance and observable output to match exactly."""
    failed = False
    for program, reference, submitted in zip(programs, expected, actual, strict=True):
        passed = reference == submitted
        print(f"{program.name}: {'PASS' if passed else 'FAIL'}")
        if not passed:
            failed = True
            print(f"  reference status={reference[0]} output={reference[1]!r}")
            print(f"  submitted status={submitted[0]} output={submitted[1]!r}")
    if failed:
        raise SubmissionFailure("one or more differential comparisons failed")


def main() -> None:
    """Run the verifier's main grading path linearly."""
    semantics = APP / "Semantics.lean"
    if not semantics.is_file() or semantics.is_symlink():
        raise FileNotFoundError("required agent artifact /app/Semantics.lean is missing")

    try:
        verify_trusted_inputs()
        sources = collect_submission_sources()
        reject_library_module_shadowing(sources)
        order, dependencies = local_dependency_order("Semantics", sources)
        if "SemanticsTemplate" not in dependencies:
            raise SubmissionFailure("Semantics must import SemanticsTemplate")
        reset_work_directory()
        compile_development(order, sources)
        run_inspector()
        compile_trusted_runner()
        original = prepare_reference_implementation()
        programs = sorted(CASES.glob("*.scm"))
        expected = [run_reference_case(original, program) for program in programs]
        actual = run_lean_runner(programs)
        compare_observations(programs, expected, actual)
    except SubmissionFailure as failure:
        print(f"FAIL: {failure}")
        write_reward(0)
        return

    write_reward(1)


if __name__ == "__main__":
    main()
