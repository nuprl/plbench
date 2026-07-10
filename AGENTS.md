## Running Harbor

To run Harbor locally, the host either Docker or Podman. First,
run `docker --version`. If it reports Podman, you need to install
the fork of Harbor from this pull request which adds Podman support:

https://github.com/harbor-framework/harbor/pull/1432

For consistency, install it to a new virtual envrionment in .harbor-venv
so that we can run Harbor like this: 

```bash
source .harbor-venv/bin/activate
harbor run -p <task-or-dataset> -e podman ...
```

### Setup steps already performed in this repo

The PR's head branch is `iandvt/harbor@main`. It was installed like this
(both `.harbor-src` and `.harbor-venv` are gitignored):

```bash
git clone --branch main https://github.com/iandvt/harbor.git .harbor-src
uv venv --python 3.12 .harbor-venv   # harbor requires Python >= 3.12
source .harbor-venv/bin/activate
uv pip install -e .harbor-src
uv pip install podman-compose   # the podman environment shells out to podman-compose
```

Verify with `harbor run --help` — the `--env/-e` option's choices should
include `podman`. `harbor run -p <task> -e podman` will fail with
"podman-compose is required for the podman environment" if that last
install step is skipped.

## Creating Tasks

Keep `instruction.md` focused on the work the agent must perform: the artifact
contract, relevant paths, required behavior, and how the result is graded.
Large reference documents, such as language specifications, file formats, and
API descriptions, belong under `environment/` and should be copied into
`/app` by the environment Dockerfile. The instruction can point to those
documents without repeating them.

Write specifications as standalone descriptions of the current task. Do not
include the history of earlier task designs or verifier bugs. When specifying
a language, prefer a compact grammar followed by semantic rules, and describe
builtins with application-shaped metavariables that make their arity clear,
such as `(display v)` and `(+ n ...)`. Include the program-facing runtime
interface, such as command-line arguments, in the language specification
rather than inventing a separate convention in the task prompt.

Minimize the artifacts an agent must install. If the verifier can derive a
bootstrap artifact from submitted source, derive it rather than requiring the
agent to submit both. Make output, error, and command-line behavior explicit,
but avoid imposing incidental implementation constraints.

Treat each test directory as the source of truth for test discovery. Do not
repeat its filenames in a verifier-side list. Prefer a trusted reference
implementation to hardcoded expected outputs when the reference semantics are
substantial enough to justify one. Keep private reference implementations
under `tests/`; do not copy them into the agent environment. Build them from
`tests/test.sh` when necessary.

Structure the verifier so that the main grading path reads linearly. Put any
oracle exception in one small helper, validate oracle-only files once during
setup, and otherwise run the oracle through the same grading loop as ordinary
submissions. An oracle that implements only part of the task should receive
honest partial credit rather than bypassing the missing requirement.

Keep scoring components independent and proportional when partial credit is
useful. For a self-hosting task, for example, one component can run the source
compiler under a trusted interpreter and another can run the compiler produced
by compiling that source. Compare both against the same reference behavior.
Require compilation itself to succeed so that an expected runtime failure
cannot pass vacuously.

Run the oracle end to end with Harbor after changing the environment,
verifier, task contract, or reference implementations. Check both the final
reward and the per-test verifier output; a plausible aggregate score can still
hide a broken fixture or oracle bug.

After a model earns a passing score, have a sub-agent independently audit the
generated solution before treating the evaluation as successful. Give the
sub-agent the task specification, the model's downloaded artifact and source,
its trajectory, and the verifier results. Ask it to determine whether the
solution implements a sound, general procedure for the specified problem or
merely obtains the reward through shortcuts such as recognizing fixtures,
hardcoding expected answers, bounded exploration where unbounded behavior is
required, unsound abstractions, or exploitation of verifier gaps. The audit
should explain the algorithm actually implemented, compare it with the task's
semantics, and cite concrete evidence for its conclusion. Add adversarial
tests when the inspection exposes an important case not already covered, then
rerun Harbor and repeat the audit on the revised task.

For example, this runs Codex on one task under Podman and downloads `/app` as
an artifact:

```bash
source .harbor-venv/bin/activate

harbor run -p tasks/scheme-typeinf -e podman -a codex -m openai/gpt-5.5 \
  --ak reasoning_effort=medium \
  --ae CODEX_FORCE_AUTH_JSON=true \
  --artifact /app
```
