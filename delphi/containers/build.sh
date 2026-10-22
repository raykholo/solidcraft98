#!/bin/bash
# Builds the two images the scripts use: sc98-lz-x86 and sc98-lz-arm.
# Usage: containers/build.sh [x86|arm]   (both if not given)
set -e
cd "$(dirname "$0")"
want=${1:-all}
if [ "$want" = all ] || [ "$want" = x86 ]; then podman build -t sc98-lz-x86 x86; fi
if [ "$want" = all ] || [ "$want" = arm ]; then podman build --platform linux/arm/v6 -t sc98-lz-arm arm; fi
