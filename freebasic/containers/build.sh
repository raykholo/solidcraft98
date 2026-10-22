#!/bin/bash
# Builds the two images the scripts use: sc98-fb-x86 and sc98-fb-arm.
# Usage: containers/build.sh [x86|arm]   (both if not given)
set -e
cd "$(dirname "$0")/.."
want=${1:-all}
if [ "$want" = all ] || [ "$want" = x86 ]; then podman build -t sc98-fb-x86 -f containers/x86/Containerfile containers/x86; fi
if [ "$want" = all ] || [ "$want" = arm ]; then podman build --platform linux/arm/v6 -t sc98-fb-arm -f containers/arm/Containerfile .; fi
