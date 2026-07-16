#!/bin/sh
set -eu

src=/app/caml-light/src
flags=${CAML_LIGHT_CFLAGS:--m32 -std=gnu89 -O1 -fno-strict-aliasing -D__FAVOR_BSD}

cd "$src"

# Build the first modified compiler with the existing bootstrap compiler.
make -C compiler all
make promote

# Rebuild the library and compiler with the modified compiler twice. This is
# the usual Caml Light bootstrap procedure and reaches a compiler fixpoint.
make again
make promote
make again

# Refresh launch artifacts and install the compiler used by the test driver.
make -C launch all CC=gcc OPTS="$flags"
mkdir -p /usr/local/share/man/man1
make install \
  CC=gcc \
  OPTS="$flags" \
  BINDIR=/usr/local/bin \
  LIBDIR=/usr/local/lib/caml-light \
  MANDIR=/usr/local/share/man/man1

