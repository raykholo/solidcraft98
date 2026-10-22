#!/bin/bash
# Build the ARMv6 (Raspberry Pi 1) program: fbc writes C for linux-arm, then
# gcc in the ARMv6 image compiles it against FreeBASIC's ARMv6 runtime.
# Output: build/arm/sc98
set -e
cd "$(dirname "$0")"
mkdir -p build/arm
podman run --rm -v "$PWD":/w:Z -w /w sc98-fb-x86 fbc -target linux-arm -arch armv6 -gen gcc -r -m sc98 src/sc98.bas -o build/arm/sc98.c 2>&1 | grep -v "warning 38" || true
podman run --rm --platform linux/arm/v6 -v "$PWD":/w:Z -w /w sc98-fb-arm bash tools/arm-link.sh build/arm/sc98.c build/arm/sc98 /usr/local/lib/freebasic/linux-arm
