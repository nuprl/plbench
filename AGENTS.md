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

## Creating Tasks


