#!/bin/bash
# Build in the x86-64 FreeBASIC container. Usage: build.sh <file.bas> [out]
set -e
cd "$(dirname "$0")"
src=$1; out=${2:-${1%.bas}}
mkdir -p "$(dirname "$out")"
podman run --rm -v "$PWD":/w:Z -w /w sc98-fb-x86 fbc -w all -exx "$src" -x "$out"
