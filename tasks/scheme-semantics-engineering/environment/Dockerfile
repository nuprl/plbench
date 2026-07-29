FROM ubuntu:24.04

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.elan/bin:${PATH}
ENV LEAN_PATH=/app

# The reference implementations use OCaml and Dune; Mini-Scheme also uses ocamllex,
# ocamlyacc, and Cmdliner. Ubuntu's ocaml package supplies both lexer/parser
# generators; libcmdliner-ocaml-dev supplies the findlib package used by Dune.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libcmdliner-ocaml-dev \
        nodejs \
        npm \
        ocaml \
        ocaml-dune \
        ocaml-findlib \
        python3 \
        ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
       | sh -s -- -y --default-toolchain leanprover/lean4:v4.32.1 \
    && npm install -g @openai/codex@latest

WORKDIR /app

COPY MiniScheme.md SemanticsTemplate.lean TestRunner.lean ./
COPY --chmod=0755 test.sh ./
COPY example-test ./example-test
COPY minischeme-reference ./minischeme-reference
COPY example-semantics /example

# Build the supplied reference checker/interpreter and shared Lean template.
RUN cd /app/minischeme-reference \
    && dune build --profile release main.exe \
    && cp _build/default/main.exe minischeme \
    && cd /app \
    && lean -o SemanticsTemplate.olean SemanticsTemplate.lean \
    && cd /example \
    && LEAN_PATH=/app lean -o Semantics.olean Semantics.lean \
    && cd /example/impl \
    && dune build --profile release main.exe \
    && cp _build/default/main.exe miniml \
    && lean --version \
    && ocamlc -version \
    && dune --version \
    && ocamlfind query cmdliner
