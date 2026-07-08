FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Pin Z3 4.8.12 from GitHub release binaries (Ubuntu 26.04 ships 4.13.x;
# TypeWhich MaxSMT results are sensitive to Z3 version).
ARG Z3_VERSION=4.8.12
ARG Z3_ASSET=z3-4.8.12-x64-glibc-2.31

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        unzip \
        build-essential \
        rustc \
        cargo \
        python3 \
        python3-yaml \
    && rm -rf /var/lib/apt/lists/*

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

RUN git clone --depth 1 https://github.com/nuprl/TypeWhich.git /app/TypeWhich

COPY Language.md /app/Language.md
COPY examples /app/examples

WORKDIR /app/TypeWhich
