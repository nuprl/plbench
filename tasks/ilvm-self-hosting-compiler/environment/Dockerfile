FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        ocaml \
        opam \
        m4 \
        build-essential \
        ca-certificates \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/* \
    && opam init --bare --disable-sandboxing -y \
    && opam switch create system ocaml-system -y \
    && eval "$(opam env --switch=system)" \
    && opam install -y dune ppx_inline_test cmdliner

WORKDIR /app

COPY ILVM.md /app/ILVM.md
COPY Scheme.md /app/Scheme.md
