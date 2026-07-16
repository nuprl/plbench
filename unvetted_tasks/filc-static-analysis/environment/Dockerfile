FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ARG FILC_VERSION=0.681
ARG FILC_SHA256=84272acf017fe76bddb32bb3865f3d97ce332eb6e6a17fc1c07a8eb9ad777787

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        patchelf \
        python3 \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        "https://github.com/pizlonator/fil-c/releases/download/v${FILC_VERSION}/filc-${FILC_VERSION}-linux-x86_64.tar.xz" \
        -o /tmp/filc.tar.xz \
    && echo "${FILC_SHA256}  /tmp/filc.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/filc \
    && tar -xJf /tmp/filc.tar.xz -C /opt/filc --strip-components=1 \
    && rm /tmp/filc.tar.xz \
    && cd /opt/filc \
    && ./setup.sh

RUN git clone --depth 1 --filter=blob:none --no-checkout \
        --branch "v${FILC_VERSION}" \
        https://github.com/pizlonator/fil-c.git /app/fil-c \
    && cd /app/fil-c \
    && git sparse-checkout init --cone \
    && git sparse-checkout set filc clang/include clang/lib llvm/include llvm/lib \
    && git checkout --detach "v${FILC_VERSION}" \
    && rm -rf /app/fil-c/.git

ENV PATH="/opt/filc/build/bin:${PATH}"
WORKDIR /app

RUN filcc --version
