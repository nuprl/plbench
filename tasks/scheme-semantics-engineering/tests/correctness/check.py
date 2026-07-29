"""Run the trusted formal and differential verifier as a RewardKit criterion."""

from pathlib import Path
import subprocess

from rewardkit import criterion


@criterion
def formal_and_differential_checks_pass(workspace: Path) -> bool:
    """Require all Lean integrity checks and Mini-Scheme comparisons to pass."""
    reward = Path("/logs/verifier/deterministic-reward.txt")
    reward.unlink(missing_ok=True)
    try:
        completed = subprocess.run(
            ["python3", "/tests/verifier.py"],
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=900,
        )
    except subprocess.TimeoutExpired:
        print("deterministic verifier timed out")
        return False
    print(completed.stdout, end="")
    print(completed.stderr, end="")
    return (
        completed.returncode == 0
        and reward.is_file()
        and reward.read_text().strip() == "1"
    )
