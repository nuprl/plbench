FROM node:22-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Pyret's build is driven by make and needs a C/C++ toolchain (native npm
# deps), git (to fetch the source), and python3 (used by the in-container
# verifier and available to the agent).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        make \
        g++ \
        build-essential \
        python3 \
        python3-venv \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Check out the Pyret language implementation at a fixed parent commit. This is
# the working baseline the task builds on: the commit predates any table type
# checking. Pinning the exact SHA keeps the environment reproducible.
ARG PYRET_COMMIT=043ceab4422ac5ad9479650ec1d47d23bd70b3d4
RUN git clone https://github.com/jpolitz/pyret-lang.git /app/pyret-lang \
    && cd /app/pyret-lang \
    && git checkout "$PYRET_COMMIT" \
    && git rev-parse HEAD

# Vendored reference material the task refers to (no network fetch at runtime).
COPY b2t2-paper.txt /app/b2t2-paper.txt
COPY core.arr /app/core.arr

# Build both compiler backends so the agent starts from a working tree:
#   - the TypeScript compiler (the target of this task), and
#   - phaseA of the Pyret-hosted compiler (needed by the full `make ts-test`
#     parity suite and by `make all-pyret-test`).
WORKDIR /app/pyret-lang/lang
RUN npm install \
    && make ts-compiler \
    && make phaseA

WORKDIR /app
