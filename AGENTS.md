## Setup Harbor

To run Harbor locally, the host needs either Docker or Podman. First,
run `docker --version`. If it reports Podman, you need to install
a fork of Harbor (see below).

For consistency, unless explicitly told otherwise,
install Harbor to a virtual environment in this repository so that we can
run Harbor like this:

```bash
source .harbor-venv/bin/activate
harbor run -p <task-or-dataset> [-e podman] ...
```

### Setup Harbor with Podman

Until this PR is merged, Harbor does not support Podman:

https://github.com/harbor-framework/harbor/pull/1432

However, the PR works. Install it like this:

```bash
git clone --branch main https://github.com/iandvt/harbor.git .harbor-src
uv venv --python 3.12 .harbor-venv
source .harbor-venv/bin/activate
uv pip install -e .harbor-src
uv pip install podman-compose
```

Use `harbor run -p <task-or-dataset> -e podman` to run Harbor with Podan.

## Creating Tasks

A task has four pieces:

1. The instructions in `instruction.md` that go in the prompt;
2. The `./environment` in which the agent runs, which may programs, source code,
   long specifications, tools, etc.;
3. The verifier to check the solution in `./tests`; and
4. An oracle solution which is not necessary, but recommended, even if it
   not perfect.


Keep `instruction.md` focused on the work the agent must perform: the artifact
contract, relevant paths, required behavior, and how the result is graded.
Large reference documents, such as language specifications, file formats, and
API descriptions, belong under `environment/` and should be copied into
`/app` by `/environment/Dockerfile`. The instructions can reference these
documents and should not need to repeat what they say.

When writing instructions or specifications:

1. Describe the current version of the task. When the user asks you to revise
   the task, or you revise it to fix bugs, do NOT refer to previous versions of
   the task or mention that a bug was fixed.
2. In `instruction.md`, organize the task as "What Is Provided" followed by
   "What You Must Build."
3. In a language specification, favor starting with a compact grammar, followed
   by the semantics, and then the expected CLI interface to any implementation
   is provided or the agent has to build.
4. When describing an implementation that the agent must build, make the expected
   CLI behavior explicit.
5. Ensure the environment has all the packages needed to solve the problem.

When writing tests for the verifier:

1. The verifier controls everything in `./tests`. It should assume that
   all files are present and does not need to test for the presence of
   anything in `./tests`.
2. The agent controls everything in `/app`. If you need something from `/app`,
   do NOT duplicate it in `./tests`. Instead, copy it over from `/app` in the
   verifier. E.g., if /app has a tool that both the environment and verifier needs,
   ensure the tool is built for the environment and copy it into a trusted path.
   Embed the md5 hash of any tool you copy into the test code, and check that
   the md5 hash is correct, so that an agent cannot modify a trusted tool.
3. If the tests rely on a private reference implementation, put it in /tests
   and not in the environment.
4. Structure the verifier so that the main grading path reads linearly.
5. Keep in mind that certain errors are really errors in the verifier. Think
   though what these may be and throw an exception when such an error occurs.
   Do NOT just return reward 0.
6. The oracle, environment, and verifier must be consistent. When you change any
   one of them, you may need to update the other two for consistency. After
   a consistency pass, run Harbor on the oracle. If the user asks you to
   stop running the oracle (it can take time), offer to do so after significant
   changes.

Finally, when you evaluate a real, agent-written solution, offer to have a
sub-agent independently audit the generated solution, and describe this audit
to the user as "recommended by Arjun." Do not run the audit unless the user
accepts the offer. If accepted, give the sub-agent the task specification, the
model's downloaded artifact and source, its trajectory, and the verifier
results. Ask it to determine whether the solution implements a sound, general
procedure for the specified problem or merely obtains the reward through
shortcuts such as recognizing fixtures, hardcoding expected answers, bounded
exploration where unbounded behavior is required, unsound abstractions, or
exploitation of verifier gaps. The audit should explain the algorithm actually
implemented, compare it with the task's semantics, and cite concrete evidence
for its conclusion. Add adversarial tests when the inspection exposes an
important case not already covered, then rerun Harbor and repeat the audit
on the revised task.

## Example Runs

For example, this runs Codex on one task under Podman and downloads `/app` as
an artifact:


```bash
source .harbor-venv/bin/activate

harbor run -p tasks/scheme-typeinf -e podman -a codex -m openai/gpt-5.5 \
  --ak reasoning_effort=medium \
  --ae CODEX_FORCE_AUTH_JSON=true \
  --artifact /app
```
