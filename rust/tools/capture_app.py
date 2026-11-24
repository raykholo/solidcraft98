#!/usr/bin/env python3
"""Render sc98-term-app --capture output with a minimal true-colour terminal.

Only the encoder's cursor, SGR, clear, space and upper-half-block vocabulary
is accepted. This captures actual ANSI output, not the app framebuffer.
"""
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path


def render(text, width=320, rows=120, scale=2):
    pixels = bytearray(width * rows * 2 * 3)
    x = y = 0
    fg = (255, 255, 255)
    bg = (0, 0, 0)
    tokens = re.compile(r"\x1b\[([0-9;]*)([A-Za-z])|([^\x1b])")
    position = 0
    for match in tokens.finditer(text):
        assert match.start() == position, repr(text[position:match.start()])
        position = match.end()
        params, final, char = match.groups()
        if final:
            args = [int(p or 0) for p in params.split(';')]
            if final == 'H':
                y, x = args[0] - 1, args[1] - 1
            elif final == 'J':
                assert args == [2]
                pixels[:] = bytes(len(pixels))
            elif final == 'm':
                if args == [0]:
                    fg, bg = (255, 255, 255), (0, 0, 0)
                else:
                    assert len(args) == 5 and args[0] in (38, 48) and args[1] == 2, args
                    if args[0] == 38:
                        fg = tuple(args[2:])
                    else:
                        bg = tuple(args[2:])
            else:
                raise ValueError(final)
        else:
            assert char in (' ', '▀'), repr(char)
            assert 0 <= x < width and 0 <= y < rows, (x, y)
            for dy, colour in enumerate((fg if char == '▀' else bg, bg)):
                offset = ((y * 2 + dy) * width + x) * 3
                pixels[offset:offset + 3] = bytes(colour)
            x += 1
    assert position == len(text)
    image = bytearray()
    for y in range(rows * 2):
        line = pixels[y * width * 3:(y + 1) * width * 3]
        expanded = b''.join(line[i:i + 3] * scale for i in range(0, len(line), 3))
        image.extend((b'\0' + expanded) * scale)
    def chunk(tag, body):
        return struct.pack('!I', len(body)) + tag + body + struct.pack('!I', zlib.crc32(tag + body))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', width * scale, rows * 2 * scale, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(image, 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    ansi = subprocess.check_output([sys.argv[1], '--capture'])
    Path(sys.argv[2]).write_bytes(render(ansi.decode('utf-8')))
