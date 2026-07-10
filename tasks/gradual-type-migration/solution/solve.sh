#!/bin/bash
set -euo pipefail

eval "$(opam env --switch=system)"
dune build --root /solution
install -m 755 /solution/_build/default/reference.exe /app/migrate
