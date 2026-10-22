#!/bin/bash
# Inside the ARMv6 image: compile the C that fbc wrote for linux-arm and
# link it with FreeBASIC's ARMv6 runtime. Usage: arm-link.sh <c file> <out> <libdir>
set -e
c=$1; out=$2; L=$3
gcc -c -O2 -march=armv6 -mfpu=vfp -mfloat-abi=hard -fno-strict-aliasing -frounding-math -fno-math-errno -fwrapv \
    -fno-exceptions -fno-asynchronous-unwind-tables -funwind-tables -Wno-format -w "$c" -o "${out}.o"
gcc -o "$out" "$L/fbrt0.o" "${out}.o" -Wl,-T,"$L/fbextra.x" -L"$L" -lfbgfx -lfb \
    -lX11 -lXext -lXpm -lXrandr -lXrender -lpthread -lncurses -lm -ldl -s
rm -f "${out}.o"
readelf -A "$out" | grep -E "CPU_name|CPU_arch:"
ls -la "$out"
