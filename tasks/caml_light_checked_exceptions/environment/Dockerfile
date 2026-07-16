FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Caml Light 0.75 assumes a 32-bit architecture. Keep the Ubuntu amd64 host
# image, but build and run Caml Light exclusively with the i386 multilib ABI.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gcc-multilib \
        libc6-dev-i386 \
        python3 \
    && rm -rf /var/lib/apt/lists/*

ARG CAML_LIGHT_URL=https://caml.inria.fr/pub/distrib/caml-light-0.75/cl75unix.tar.gz
ARG CAML_LIGHT_SHA256=ac2ad4c7b28716ec3f0e2e24b8b092b99253a573ac8de7da396e08e8bcd10fd2

RUN mkdir -p /app/caml-light \
    && curl -fsSL "${CAML_LIGHT_URL}" -o /tmp/cl75unix.tar.gz \
    && echo "${CAML_LIGHT_SHA256}  /tmp/cl75unix.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/cl75unix.tar.gz --strip-components=2 -C /app/caml-light \
    && rm /tmp/cl75unix.tar.gz

WORKDIR /app/caml-light/src

# GCC 15 defaults to a newer C dialect than this K&R-era code accepts.
# The other flags select the i386 ABI and avoid optimizations that violate
# assumptions made by this old runtime.
ENV CAML_LIGHT_CFLAGS="-m32 -std=gnu89 -O1 -fno-strict-aliasing -D__FAVOR_BSD"

RUN make configure CC=gcc OPTS="${CAML_LIGHT_CFLAGS}" \
    # The old probe does not test strerror, then falls back to glibc symbols
    # (sys_errlist/sys_nerr) that are no longer exported.
    && sed -i '/#define HAS_MEMMOVE/a #define HAS_STRERROR' ../config/s.h \
    && make world CC=gcc OPTS="${CAML_LIGHT_CFLAGS}" \
    && make bootstrap CC=gcc OPTS="${CAML_LIGHT_CFLAGS}" \
    && readelf -h camlrun | grep -q 'Class:.*ELF32' \
    && readelf -h camlrun | grep -q 'Machine:.*Intel 80386' \
    && mkdir -p /usr/local/share/man/man1 \
    && make install \
        CC=gcc \
        OPTS="${CAML_LIGHT_CFLAGS}" \
        BINDIR=/usr/local/bin \
        LIBDIR=/usr/local/lib/caml-light \
        MANDIR=/usr/local/share/man/man1 \
    && printf '1 + 2;;\nlet rec fib n = if n < 2 then 1 else fib(n-1)+fib(n-2);;\nfib 20;;\n' \
        | camllight 2>&1 | grep -q '10946'

COPY build.sh test.sh /app/
COPY public_tests /app/checked-exception-tests
RUN chmod +x /app/build.sh /app/test.sh

WORKDIR /app/caml-light
