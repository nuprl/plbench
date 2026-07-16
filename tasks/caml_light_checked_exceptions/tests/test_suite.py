"""Verifier for the checked-exceptions task.

The submitted Caml Light compiler is first rebuilt with ``/app/build.sh``.
Programs in ``/tests/cases/does_throw`` have an exception that escapes from
top-level evaluation, so the compiler must reject every one. Accepting any of
them fails the soundness gate and produces a reward of zero.

If the soundness gate passes, programs in ``/tests/cases/safe`` are compiled
and run. These programs use exception-raising code internally but handle every
exception before it reaches top level. The reward is the fraction of safe
programs that compile and terminate successfully.
"""

import subprocess
from pathlib import Path


def compile_source(source):
    input_file = Path("/tmp/checked-exceptions/input.ml")
    executable = Path("/tmp/checked-exceptions/program")
    input_file.write_bytes(source.read_bytes())
    result = subprocess.run(
        ["/usr/local/bin/camlc", "-o", str(executable), str(input_file)],
        capture_output=True,
        text=True,
        timeout=30,
        cwd="/tmp/checked-exceptions",
    )
    return result, executable


def main():
    Path("/logs/verifier/reward.txt").unlink(missing_ok=True)
    does_throw = sorted(Path("/tests/cases/does_throw").glob("*.ml"))
    safe = sorted(Path("/tests/cases/safe").glob("*.ml"))
    subprocess.run(["/app/build.sh"], timeout=600, check=True)
    Path("/tmp/checked-exceptions").mkdir(exist_ok=True)

    failures = []
    for source in does_throw:
        result, _ = compile_source(source)
        if result.returncode == 0:
            failures.append(source.name)
            print(f"FAIL does_throw/{source.name}: accepted")
        else:
            print(f"PASS does_throw/{source.name}: rejected")
    if failures:
        Path("/logs/verifier/reward.txt").write_text("0.0\n")
        raise AssertionError("accepted unsafe programs: " + ", ".join(failures))

    passed = 0
    for source in safe:
        result, executable = compile_source(source)
        if result.returncode != 0:
            print(f"MISS safe/{source.name}: rejected\n{result.stderr}")
            continue
        result = subprocess.run(
            [str(executable)], capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            print(f"MISS safe/{source.name}: exited {result.returncode}")
            continue
        passed += 1
        print(f"PASS safe/{source.name}")

    score = passed / len(safe)
    Path("/logs/verifier/reward.txt").write_text(f"{score:.6f}\n")
    print(f"precision_score={score:.6f} ({passed}/{len(safe)})")


main()
