FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        ocaml \
        ocaml-dune \
        rustc \
        cargo \
        build-essential \
        ca-certificates \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mscheme /app/mscheme-src

RUN cd /app/mscheme-src \
    && dune build \
    && install -m 755 _build/default/bin/main.exe /app/mscheme \
    && rm -rf /app/mscheme-src/_build
