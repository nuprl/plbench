FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        python3 \
        gdb \
        file \
        patchelf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG CHIBICC_COMMIT=90d1f7f199cc55b13c7fdb5839d1409806633fdb

RUN git init /app/chibicc \
    && git -C /app/chibicc remote add origin https://github.com/rui314/chibicc.git \
    && git -C /app/chibicc fetch --depth 1 origin "$CHIBICC_COMMIT" \
    && git -C /app/chibicc checkout --detach FETCH_HEAD \
    && rm -rf /app/chibicc/.git

RUN make -C /app/chibicc -j2
