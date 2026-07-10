"""Behavioral tests extracted from arjunguha/ilvm/src/main.rs.

These exercise an `ilvm` binary that implements the Language.md CLI:
  ilvm [OPTIONS] <FILENAME> [ARGS]...
  -m/--memory-limit, -r/--num-registers
  ARGS are ordered -l literal / -f filename markers
Successful exit prints: Normal termination. Result = <n>
"""

from __future__ import annotations

import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

RESULT_RE = re.compile(r"Normal termination\. Result = (-?\d+)")


def find_ilvm() -> Path:
    path = Path("/app/ilvm")
    if not path.is_file():
        raise FileNotFoundError("expected executable at /app/ilvm")
    if path.stat().st_mode & 0o111 == 0:
        raise FileNotFoundError("/app/ilvm exists but is not executable")
    return path


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


def run_ilvm(
    ilvm: Path,
    source: str,
    *,
    memory_limit: int = 500,
    num_registers: int = 10,
    args: list[str] | None = None,
) -> RunResult:
    with tempfile.TemporaryDirectory(prefix="ilvm-test-") as tmp:
        prog = Path(tmp) / "prog.ilvm"
        prog.write_text(source)
        cmd = [
            str(ilvm),
            "-m",
            str(memory_limit),
            "-r",
            str(num_registers),
            str(prog),
        ]
        if args:
            cmd.extend(args)
        completed = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return RunResult(completed.returncode, completed.stdout, completed.stderr)


def assert_ok(r: RunResult, expected: int, name: str) -> None:
    assert r.returncode == 0, (
        f"{name}: expected exit 0, got {r.returncode}\n"
        f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}"
    )
    assert r.result == expected, (
        f"{name}: expected result {expected}, got {r.result!r}\n"
        f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}"
    )


def assert_err(r: RunResult, name: str, substrings: list[str] | None = None) -> None:
    assert r.returncode != 0, (
        f"{name}: expected non-zero exit, got 0\nstdout:\n{r.stdout}"
    )
    if substrings:
        blob = r.stdout + r.stderr
        assert any(s in blob for s in substrings), (
            f"{name}: expected one of {substrings} in output\n"
            f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}"
        )


def test_trailing_whitespace(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                exit(200);
            }  """,
    )
    assert_ok(r, 200, "test_trailing_whitespace")


def test_trailing_garbage(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                exit(200);
            }  xxx""",
    )
    assert_err(r, "test_trailing_garbage")


def test_exit(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                exit(200);
            }""",
    )
    assert_ok(r, 200, "test_exit")


def test_reg_copy(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = 200;
                r2 = r0;
                exit(r2);
            }""",
    )
    assert_ok(r, 200, "test_reg_copy")


def test_reg_add(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = 200;
                r1 = 11;
                r3 = r0 + r1;
                exit(r3);
            }""",
    )
    assert_ok(r, 211, "test_reg_add")


def test_load_store(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = 200;
                *r0 = 42;
                r1 = *r0;
                exit(r1);
            }""",
    )
    assert_ok(r, 42, "test_load_store")


def test_goto(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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


def test_indirect_goto(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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


def test_ifz(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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


def test_fac(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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


def test_malloc(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = malloc(10);
                exit(r0);
            }""",
    )
    assert_ok(r, 2, "test_malloc")


def test_cli_arg_layout_no_args(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r1 = *1;
                r2 = r0 + r1;
                exit(r2);
            }""",
    )
    assert_ok(r, 2, "test_cli_arg_layout_no_args")


def test_cli_arg_layout_with_args(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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
        args=["-l", "hi"],
    )
    assert_ok(r, 1751711752, "test_cli_arg_layout_with_args")


def test_malloc_starts_after_cli_args(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r1 = malloc(1);
                exit(r1);
            }""",
        args=["-l", "abc", "-l", "defg"],
    )
    assert_ok(r, 7, "test_malloc_starts_after_cli_args")


def test_print_str(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r1 = *2;
                print_str(r1);
                exit(0);
            }""",
        args=["-l", "hello"],
    )
    assert_ok(r, 0, "test_print_str")
    assert "hello" in r.stdout, f"test_print_str: expected 'hello' in stdout:\n{r.stdout}"


def test_bitwise_ops(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
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


def test_negative_immediates(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = -7;
                exit(r0);
            }""",
    )
    assert_ok(r, -7, "test_negative_immediates")


def test_negative_arithmetic(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = -7;
                r1 = r0 - 5;
                exit(r1);
            }""",
    )
    assert_ok(r, -12, "test_negative_arithmetic")


def test_memsize(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = memsize;
                exit(r0);
            }""",
        memory_limit=500,
    )
    assert_ok(r, 500, "test_memsize")


def test_line_comments(ilvm: Path) -> None:
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = 10; // set r0
                // full line comment
                exit(r0);
            }""",
    )
    assert_ok(r, 10, "test_line_comments")


def test_malloc_oom(ilvm: Path) -> None:
    # malloc(1) is not executed just once: goto(0) restarts the block forever.
    # Every iteration allocates a new one-word block, then overwrites r0 without
    # freeing the block whose address it previously held.  Writing through r0
    # changes that block's contents; it does not release the allocation.
    #
    # The memory limit is the total heap size in words, not a per-allocation
    # limit.  Even with no CLI arguments, the argument layout reserves words 0
    # and 1, so a 20-word heap leaves addresses 2..19 (18 words) for malloc.
    # Thus the first 18 calls succeed and the 19th must report malloc OOM.
    r = run_ilvm(
        ilvm,
        """
            block 0 {
                r0 = malloc(1);
                *r0 = 1234;
                goto(0);
            }""",
        memory_limit=20,
    )
    assert_err(r, "test_malloc_oom", substrings=["OOM", "malloc", "error", "Error"])


def test_parse_cli_args_literals_and_files(ilvm: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="ilvm-cli-") as tmp:
        path = Path(tmp) / "argfile.txt"
        path.write_text("file contents")
        r = run_ilvm(
            ilvm,
            """
            block 0 {
                r1 = *1;
                exit(r1);
            }""",
            args=["-l", "arg1", "-f", str(path), "-l", "arg2"],
        )
        assert_ok(r, 3, "test_parse_cli_args_literals_and_files")


TESTS = [
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
    test_memsize,
    test_line_comments,
    test_malloc_oom,
    test_parse_cli_args_literals_and_files,
]


def main() -> int:
    ilvm = find_ilvm()
    print(f"Using ilvm binary: {ilvm}")
    failures = 0
    for test in TESTS:
        name = test.__name__
        try:
            test(ilvm)
            print(f"PASS {name}")
        except Exception as exc:
            failures += 1
            print(f"FAIL {name}: {exc}")
    print(f"{len(TESTS) - failures}/{len(TESTS)} passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
