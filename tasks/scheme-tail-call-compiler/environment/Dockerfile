FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        ocaml \
        opam \
        m4 \
        rustc \
        cargo \
        build-essential \
        ca-certificates \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Language.md /app/Language.md
COPY minischeme /app/minischeme-src

RUN opam init --bare --disable-sandboxing -y \
    && opam switch create minischeme ocaml-system -y \
    && eval "$(opam env --switch=minischeme)" \
    && opam install -y dune menhir cmdliner \
    && cd /app/minischeme-src \
    && dune build \
    && install -m 755 _build/default/bin/main.exe /app/minischeme \
    && rm -rf /app/minischeme-src/_build
