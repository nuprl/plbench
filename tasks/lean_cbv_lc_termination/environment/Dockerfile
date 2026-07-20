FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.elan/bin:${PATH}
ENV LEAN_PATH=/app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
       | sh -s -- -y --default-toolchain leanprover/lean4:v4.30.0

WORKDIR /app

COPY cbv_lc.lean termination.lean ./

RUN lean --version
