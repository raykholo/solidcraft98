#!/bin/bash
# Builds build/arm/SolidCraft98 (Raspberry Pi 1 and up, ARMv6) in the
# emulated sc98-lz-arm image. It builds from a copy inside the container,
# so the x86-64 build's files are left alone.
set -e
cd "$(dirname "$0")"
mkdir -p build/arm
podman run --rm --platform linux/arm/v6 -v "$PWD":/src:ro,Z -v "$PWD/build/arm":/out:Z sc98-lz-arm bash -c \
  'mkdir /w && cd /src && tar cf - --exclude=./build --exclude=./lib --exclude=./tests/out --exclude=./dist . | (cd /w && tar xf -) && cd /w && lazbuild -q SolidCraft98.lpi && cp build/SolidCraft98 /out/ && file /out/SolidCraft98'
