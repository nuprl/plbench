FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# TypeWhich's MaxSMT results are sensitive to the Z3 version.
ARG Z3_VERSION=4.8.12
ARG Z3_ASSET=z3-4.8.12-x64-glibc-2.31

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
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && opam init --bare --disable-sandboxing -y \
    && opam switch create system ocaml-system -y \
    && eval "$(opam env --switch=system)" \
    && opam install -y dune menhir ocamlformat ppx_deriving_yaml yaml

RUN curl -fsSL -o /tmp/z3.zip \
      "https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/${Z3_ASSET}.zip" \
    && unzip -q /tmp/z3.zip -d /tmp \
    && cp "/tmp/${Z3_ASSET}/bin/libz3.so" /usr/local/lib/ \
    && cp "/tmp/${Z3_ASSET}/bin/z3" /usr/local/bin/ \
    && cp -r "/tmp/${Z3_ASSET}/include/." /usr/local/include/ \
    && ldconfig \
    && z3 --version \
    && rm -rf /tmp/z3.zip "/tmp/${Z3_ASSET}"

WORKDIR /app
COPY Language.md /app/Language.md
