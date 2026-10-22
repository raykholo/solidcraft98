#!/bin/bash
# Run a UI script headless with the ARMv6 build, in the emulated Pi userland.
cd "$(dirname "$0")"
mkdir -p tests/home/Documents tests/out
cp tests/*.solidcraft tests/home/Documents/
podman run --rm --platform linux/arm/v6 -v "$PWD":/w:Z -w /w -e HOME=/w/tests/home sc98-fb-arm bash -c \
  "timeout 600 ./build/arm/sc98 --headless --log tests/out/log.txt --script $1 ${@:2}; rc=\$?; for f in tests/out/*.bmp; do [ -f \"\$f\" ] && convert \"\$f\" \"\${f%.bmp}.png\" && rm \"\$f\"; done; exit \$rc"
