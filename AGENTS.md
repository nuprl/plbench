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


