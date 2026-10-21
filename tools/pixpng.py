#!/usr/bin/env python3
"""Render the pixel-art icons in modIcons.bas to a PNG contact sheet.

Usage: pixpng.py <modIcons.bas> <out.png> [scale]

Each icon in the module is a run of 16 string lines of 16 characters:
a hex digit is a QBColor index, "." is transparent. Stdlib only.
"""
import re
import struct
import sys
import zlib

QB = [
    (0, 0, 0), (0, 0, 128), (0, 128, 0), (0, 128, 128),
    (128, 0, 0), (128, 0, 128), (128, 128, 0), (192, 192, 192),
    (128, 128, 128), (0, 0, 255), (0, 255, 0), (0, 255, 255),
    (255, 0, 0), (255, 0, 255), (255, 255, 0), (255, 255, 255),
]
BG = (0, 128, 128)  # desktop teal, so transparency shows


def parse(path):
    icons, name, rows = [], None, []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*Case\s+\"(\w+)\"", line)
        if m:
            name, rows = m.group(1), []
            continue
        m = re.search(r"\bR\s*\"(.*)\"", line)
        if m and name:
            rows.append(m.group(1))
            if len(rows) == 16:
                icons.append((name, rows))
                name = None
    return icons


def check(icons):
    bad = 0
    for name, rows in icons:
        for i, r in enumerate(rows):
            if len(r) != 16 or set(r) - set("0123456789ABCEF."):
                print(f"{name} row {i}: {len(r)} chars: {r!r}")
                bad += 1
    return bad


def png(path, w, h, pix):
    raw = b"".join(b"\0" + bytes(c for p in pix[y * w:(y + 1) * w] for c in p) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw)))
        f.write(chunk(b"IEND", b""))


def main():
    src, out = sys.argv[1], sys.argv[2]
    s = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    icons = parse(src)
    if check(icons):
        sys.exit(1)
    cell = 16 * s + s * 2
    w, h = cell * len(icons), cell
    pix = [BG] * (w * h)
    for n, (_, rows) in enumerate(icons):
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch == ".":
                    continue
                c = QB[int(ch, 16)]
                for dy in range(s):
                    for dx in range(s):
                        pix[(s + y * s + dy) * w + n * cell + s + x * s + dx] = c
    png(out, w, h, pix)
    print(" ".join(n for n, _ in icons))


if __name__ == "__main__":
    main()
