FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ocaml \
        opam \
        ocaml-dune \
        menhir \
        python3 \
        rustc \
        cargo \
        build-essential \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY NetKAT-Equivalence.md /app/NetKAT-Equivalence.md
