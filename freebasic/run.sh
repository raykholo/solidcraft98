#!/bin/bash
# Run a UI script headless in the x86-64 image; screenshots become PNGs.
# Usage: run.sh <script> [extra args]
cd "$(dirname "$0")"
mkdir -p tests/home/Documents tests/out
cp tests/*.solidcraft tests/home/Documents/
podman run --rm -v "$PWD":/w:Z -w /w -e HOME=/w/tests/home sc98-fb-x86 bash -c \
  "timeout 120 ./build/sc98 --headless --log tests/out/log.txt --script $1 ${@:2}; rc=\$?; for f in tests/out/*.bmp; do [ -f \"\$f\" ] && convert \"\$f\" \"\${f%.bmp}.png\" && rm \"\$f\"; done; exit \$rc"
