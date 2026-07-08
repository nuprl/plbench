"""Verify a self-hosting native-code ILVM compiler.

1. Fixed point: compile compiler.ilvm → native1; native1(compiler.ilvm) → native2;
   native1 == native2 (byte-identical).
2. Correctness: use native1 to compile/run the behavioral suite from
   arjunguha/ilvm/src/main.rs.
"""

from __future__ import annotations

import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

RESULT_RE = re.compile(r"Normal termination\. Result = (-?\d+)")
# Lookbehind so we do not consume the binary's trailing newline.
TERMINATION_LINE_RE = re.compile(
    rb"(?:(?<=\n)|^)Normal termination\. Result = -?\d+\n?\Z"
)
# Harbor does not expose agent identity to the verifier. The lame oracle embeds
# this marker in emitted "native" binaries so we can skip the ELF check.
ORACLE_MAGIC = b"ILVM_ORACLE_LAME_COMPILER"
ELF_MAGIC = b"\x7fELF"
HOST_MEMORY = 4_000_000
HOST_REGISTERS = 64
ILVM = Path("/app/ilvm")
COMPILER = Path("/app/compiler.ilvm")


def find_ilvm() -> Path:
    if not ILVM.is_file():
        raise FileNotFoundError("expected executable at /app/ilvm")
    if ILVM.stat().st_mode & 0o111 == 0:
        raise FileNotFoundError("/app/ilvm exists but is not executable")
    return ILVM


def find_compiler() -> Path:
    if not COMPILER.is_file():
        raise FileNotFoundError("expected compiler at /app/compiler.ilvm")
    return COMPILER


@dataclass
class RunResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def result(self) -> int | None:
        m = RESULT_RE.search(self.stdout)
        if m is None:
            return None
        return int(m.group(1))


def strip_ilvm_termination(data: bytes) -> bytes:
    return TERMINATION_LINE_RE.sub(b"", data)


def write_executable(path: Path, data: bytes) -> None:
    path.write_bytes(data)
    path.chmod(path.stat().st_mode | 0o111)


def assert_native_or_oracle(data: bytes, label: str) -> None:
    """Reject lame shell-wrapper compilers unless they carry the oracle marker."""
    if ORACLE_MAGIC in data:
        return
    if data.startswith(ELF_MAGIC):
        return
    raise AssertionError(
        f"{label}: expected a native ELF executable, got non-ELF output "
        f"({len(data)} bytes, starts with {data[:16]!r}). "
        "Shell-script / interpreter-wrapper compilers are not accepted."
    )


def compile_compiler_under_ilvm(ilvm: Path, compiler_src: Path) -> bytes:
    cmd = [
        str(ilvm),
        "-m",
        str(HOST_MEMORY),
        "-r",
        str(HOST_REGISTERS),
        str(compiler_src),
        "-f",
        str(compiler_src),
    ]
    completed = subprocess.run(cmd, capture_output=True, timeout=600)
    assert completed.returncode == 0, (
        f"compiling compiler under ilvm failed: exit {completed.returncode}\n"
        f"stdout:\n{completed.stdout!r}\nstderr:\n{completed.stderr!r}"
    )
    body = strip_ilvm_termination(completed.stdout)
    assert body, "compiling compiler under ilvm produced empty output"
    assert_native_or_oracle(body, "compiler under /app/ilvm")
    return body


def compile_with_native(native_compiler: Path, source_path: Path) -> bytes:
    completed = subprocess.run(
        [str(native_compiler), str(source_path)],
        capture_output=True,
        timeout=600,
    )
    assert completed.returncode == 0, (
        f"native compiler failed on {source_path}: exit {completed.returncode}\n"
        f"stdout:\n{completed.stdout!r}\nstderr:\n{completed.stderr!r}"
    )
    assert completed.stdout, f"native compiler produced empty output for {source_path}"
    assert_native_or_oracle(completed.stdout, f"native compile of {source_path}")
    return completed.stdout


def run_native(path: Path, *, args: list[str] | None = None) -> RunResult:
    cmd = [str(path)]
    if args:
        cmd.extend(args)
    completed = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return RunResult(completed.returncode, completed.stdout, completed.stderr)


def check_fixed_point(ilvm: Path, compiler_src: Path, native1_path: Path) -> None:
    native1 = compile_compiler_under_ilvm(ilvm, compiler_src)
    write_executable(native1_path, native1)
    native2 = compile_with_native(native1_path, compiler_src)
    assert native1 == native2, (
        "fixed-point check failed: compiling the compiler under /app/ilvm "
        "and compiling it again with the resulting native binary produced "
        f"different outputs ({len(native1)} vs {len(native2)} bytes)"
    )


def run_guest_via_native_compiler(
    native_compiler: Path,
    source: str,
    *,
    args: list[str] | None = None,
) -> RunResult:
    with tempfile.TemporaryDirectory(prefix="ilvm-sh-") as tmp:
        tmp_path = Path(tmp)
        guest_src = tmp_path / "guest.ilvm"
        guest_bin = tmp_path / "guest"
        guest_src.write_text(source)
        data = compile_with_native(native_compiler, guest_src)
        write_executable(guest_bin, data)
        return run_native(guest_bin, args=args)


def assert_ok(r: RunResult, expected: int, name: str) -> None:
    assert r.returncode == 0, (
        f"{name}: expected exit 0, got {r.returncode}\n"
        f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}"
    )
    assert r.result == expected, (
        f"{name}: expected result {expected}, got {r.result!r}\n"
        f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}"
    )


def assert_err(r: RunResult, name: str) -> None:
    assert r.returncode != 0, (
        f"{name}: expected non-zero exit, got 0\nstdout:\n{r.stdout}"
    )


def test_trivial_exit(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                exit(42);
            }""",
    )
    assert_ok(r, 42, "test_trivial_exit")


def test_trailing_whitespace(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                exit(200);
            }  """,
    )
    assert_ok(r, 200, "test_trailing_whitespace")


def test_trailing_garbage(native_compiler: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="ilvm-bad-") as tmp:
        tmp_path = Path(tmp)
        guest_src = tmp_path / "guest.ilvm"
        guest_src.write_text(
            """
            block 0 {
                exit(200);
            }  xxx"""
        )
        completed = subprocess.run(
            [str(native_compiler), str(guest_src)],
            capture_output=True,
            timeout=600,
        )
        if completed.returncode != 0 or not completed.stdout:
            return
        guest_bin = tmp_path / "guest"
        write_executable(guest_bin, completed.stdout)
        r = run_native(guest_bin)
        assert r.returncode != 0 or r.result != 200, (
            "test_trailing_garbage: garbage program should not succeed with 200"
        )


def test_exit(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                exit(200);
            }""",
    )
    assert_ok(r, 200, "test_exit")


def test_reg_copy(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = 200;
                r2 = r0;
                exit(r2);
            }""",
    )
    assert_ok(r, 200, "test_reg_copy")


def test_reg_add(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = 200;
                r1 = 11;
                r3 = r0 + r1;
                exit(r3);
            }""",
    )
    assert_ok(r, 211, "test_reg_add")


def test_load_store(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = 200;
                *r0 = 42;
                r1 = *r0;
                exit(r1);
            }""",
    )
    assert_ok(r, 42, "test_load_store")


def test_goto(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r2 = 200;
                goto(10);
            }
            block 10 {
                r2 = r2 + 1;
                exit(r2);
            }""",
    )
    assert_ok(r, 201, "test_goto")


def test_indirect_goto(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r2 = 200;
                r3 = 10;
                goto(r3);
            }
            block 10 {
                r2 = r2 + r3;
                exit(r2);
            }""",
    )
    assert_ok(r, 210, "test_indirect_goto")


def test_ifz(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r2 = 1;
                ifz r2 {
                    exit(20);
                }
                else {
                    exit(30);
                }
            }""",
    )
    assert_ok(r, 30, "test_ifz")


def test_fac(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r2 = 1;
                r1 = 5;
                goto(1);
            }
            block 1 {
                ifz r1 {
                   exit(r2);
                }
                else {
                    r2 = r2 * r1;
                    r1 = r1 - 1;
                    goto(1);
                }
            }""",
    )
    assert_ok(r, 120, "test_fac")


def test_malloc(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = malloc(10);
                exit(r0);
            }""",
    )
    assert_ok(r, 2, "test_malloc")


def test_cli_arg_layout_no_args(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r1 = *1;
                r2 = r0 + r1;
                exit(r2);
            }""",
    )
    assert_ok(r, 2, "test_cli_arg_layout_no_args")


def test_cli_arg_layout_with_args(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r1 = *1;
                r2 = *2;
                r3 = *r2;
                r6 = r1 + r2;
                r6 = r6 + r3;
                r6 = r6 + r0;
                exit(r6);
            }""",
        args=["hi"],
    )
    assert_ok(r, 1751711752, "test_cli_arg_layout_with_args")


def test_malloc_starts_after_cli_args(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r1 = malloc(1);
                exit(r1);
            }""",
        args=["abc", "defg"],
    )
    assert_ok(r, 7, "test_malloc_starts_after_cli_args")


def test_print_str(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r1 = *2;
                print_str(r1);
                exit(0);
            }""",
        args=["hello"],
    )
    assert_ok(r, 0, "test_print_str")
    assert "hello" in r.stdout, f"test_print_str: expected 'hello' in stdout:\n{r.stdout}"


def test_bitwise_ops(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = 12 & 10;
                r1 = 12 | 10;
                r2 = r0 ^ r1;
                r3 = ~ r2;
                r4 = -8 >> 1;
                r5 = -8 >>> 1;
                r6 = 3 << 4;
                r7 = r3 + r4;
                r7 = r7 + r6;
                r8 = r5 == 2147483644;
                r7 = r7 + r8;
                exit(r7);
            }""",
    )
    assert_ok(r, 38, "test_bitwise_ops")


def test_negative_immediates(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = -7;
                exit(r0);
            }""",
    )
    assert_ok(r, -7, "test_negative_immediates")


def test_negative_arithmetic(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = -7;
                r1 = r0 - 5;
                exit(r1);
            }""",
    )
    assert_ok(r, -12, "test_negative_arithmetic")


def test_line_comments(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = 10; // set r0
                // full line comment
                exit(r0);
            }""",
    )
    assert_ok(r, 10, "test_line_comments")


def test_malloc_oom(native_compiler: Path) -> None:
    r = run_guest_via_native_compiler(
        native_compiler,
        """
            block 0 {
                r0 = malloc(1);
                *r0 = 1234;
                goto(0);
            }""",
    )
    assert_err(r, "test_malloc_oom")


TESTS = [
    test_trivial_exit,
    test_trailing_whitespace,
    test_trailing_garbage,
    test_exit,
    test_reg_copy,
    test_reg_add,
    test_load_store,
    test_goto,
    test_indirect_goto,
    test_ifz,
    test_fac,
    test_malloc,
    test_cli_arg_layout_no_args,
    test_cli_arg_layout_with_args,
    test_malloc_starts_after_cli_args,
    test_print_str,
    test_bitwise_ops,
    test_negative_immediates,
    test_negative_arithmetic,
    test_line_comments,
    test_malloc_oom,
]


def main() -> int:
    ilvm = find_ilvm()
    compiler_src = find_compiler()
    print(f"Using /app/ilvm: {ilvm}")
    print(f"Using /app/compiler.ilvm: {compiler_src}")

    with tempfile.TemporaryDirectory(prefix="ilvm-boot-") as tmp:
        native1 = Path(tmp) / "compiler1"
        try:
            check_fixed_point(ilvm, compiler_src, native1)
            print("PASS fixed_point")
        except Exception as exc:
            print(f"FAIL fixed_point: {exc}")
            return 1

        failures = 0
        for test in TESTS:
            name = test.__name__
            try:
                test(native1)
                print(f"PASS {name}")
            except Exception as exc:
                failures += 1
                print(f"FAIL {name}: {exc}")
        print(f"{len(TESTS) - failures}/{len(TESTS)} passed")
        return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
