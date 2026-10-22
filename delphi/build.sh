#!/bin/bash
# Builds build/SolidCraft98 (x86-64 Linux) in the sc98-lz-x86 image.
# Usage: build.sh [Debug]   (Debug: range checks and line numbers)
set -e
cd "$(dirname "$0")"
mode=${1:+--build-mode=$1}
podman run --rm -v "$PWD":/w:Z -w /w sc98-lz-x86 lazbuild -q $mode SolidCraft98.lpi
ls -la build/SolidCraft98
