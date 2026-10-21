#!/usr/bin/env python3
"""Make a Windows .ico from one icon in modIcons.bas (16x16, plus 32x32 at 2x).

Usage: mkico.py <modIcons.bas> <key> <out.ico>
Stdlib only.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixpng import QB, parse  # noqa: E402


def bmp_entry(rows, scale):
    n = 16 * scale
    px = []
    for y in range(n - 1, -1, -1):             # BMP rows go bottom-up
        r = rows[y // scale]
        for x in range(n):
            ch = r[x // scale]
            if ch == ".":
                px.append(b"\0\0\0\0")
            else:
                c = QB[int(ch, 16)]
                px.append(bytes((c[2], c[1], c[0], 255)))
    xor = b"".join(px)
    mask_row = ((n + 31) // 32) * 4
    andmask = b"\0" * (mask_row * n)            # alpha does the masking
    header = struct.pack("<IiiHHIIiiII", 40, n, n * 2, 1, 32, 0, len(xor) + len(andmask), 0, 0, 0, 0)
    return n, header + xor + andmask


def main():
    src, key, out = sys.argv[1:4]
    icons = dict(parse(src))
    if key not in icons:
        sys.exit(f"mkico: no icon {key!r} in {src}")
    entries = [bmp_entry(icons[key], s) for s in (1, 2)]
    data = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    for n, blob in entries:
        data += struct.pack("<BBBBHHII", n, n, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    for _, blob in entries:
        data += blob
    with open(out, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
