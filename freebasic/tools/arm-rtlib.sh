#!/bin/bash
# Inside the ARMv6 image: build FreeBASIC's runtime (rtlib and gfxlib2) for
# ARMv6 from source, into <out>. FreeBASIC's own ARM packages are for ARMv7,
# which an original Raspberry Pi can't run. Only the runtime is needed: the
# x86-64 fbc writes the C, and gcc here compiles and links it.
# Usage: arm-rtlib.sh <out dir>
set -e
out=$1
v=1.10.1
cd /tmp
curl -sSLo src.tar.xz https://github.com/freebasic/fbc/releases/download/$v/FreeBASIC-$v-source-bootstrap.tar.xz
echo "2fae2c66b435240d4de11bb534843baa188574508a8a5bdaa5020bf729bf0a3e  src.tar.xz" | sha256sum -c -
tar xf src.tar.xz
cd FreeBASIC-$v-source-bootstrap
echo 'CFLAGS += -DDISABLE_OPENGL' > config.mk
make rtlib gfxlib2 -j"$(nproc)" > /dev/null
mkdir -p "$out"
cp lib/freebasic/linux-arm/* "$out/"
cd /tmp && rm -rf src.tar.xz FreeBASIC-$v-source-bootstrap
readelf -A "$out/libfb.a" | grep -m1 "Tag_CPU_arch: v6"
