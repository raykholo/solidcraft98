#!/usr/bin/env python3
"""Exercise the real demo in a PTY, including raw-mode restoration (Unix only).

Usage: python3 rust/tools/terminal_smoke.py /path/to/sc98-term-demo
No compilation is performed here; build the binary first.
"""
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time


def read_until(master, predicate, timeout=5):
    end = time.monotonic() + timeout
    data = bytearray()
    while time.monotonic() < end:
        if select.select([master], [], [], 0.05)[0]:
            data.extend(os.read(master, 65536))
            if predicate(data):
                return bytes(data)
    raise AssertionError(f"timed out; last output: {data[-200:]!r}")


def drain(master):
    while select.select([master], [], [], 0.05)[0]:
        os.read(master, 65536)


def run(binary, args):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    before = termios.tcgetattr(slave)
    process = subprocess.Popen([binary, *args], stdin=slave, stdout=slave, stderr=slave)
    try:
        wire = "--wireframe" in args
        glyph = b"\xe2\xa0" if wire else "▀".encode()
        initial = read_until(master, lambda data: glyph in data)
        assert b"\x1b[?1006h" in initial and b"\x1b[6n" in initial
        assert not termios.tcgetattr(slave)[3] & termios.ICANON
        # Pause animation so that subsequent output is attributable to input.
        os.write(master, b" ")
        time.sleep(0.15)
        drain(master)
        # A cursor-position reply delivered across reads must cause a full redraw.
        os.write(master, b"\x1b[20;")
        time.sleep(0.1)
        os.write(master, b"70R")
        read_until(master, lambda data: b"\x1b[0m\x1b[2J" in data)
        time.sleep(0.1)
        drain(master)
        os.write(master, b"\x0c")
        read_until(master, lambda data: b"\x1b[0m\x1b[2J" in data)
        # The native terminal-size path must react to a resize as well.
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 40, 0, 0))
        read_until(master, lambda data: b"\x1b[12;1H" in data)
        # Switching shaded/wireframe must produce the other glyph family.
        os.write(master, b"s")
        other = "▀".encode() if wire else b"\xe2\xa0"
        read_until(master, lambda data: other in data)
        os.write(master, b"\x1b[<0;10;10M\x1b[<32;12;11M\x1b[<0;12;11m\x1b[<64;12;11M")
        os.write(master, b"\x11")
        final = read_until(master, lambda data: b"\x1b[?1049l" in data)
        process.wait(timeout=5)
        assert process.returncode == 0, process.returncode
        assert b"\x1b[?1006l" in final and b"\x1b[?25h" in final
        assert termios.tcgetattr(slave) == before, "terminal attributes were not restored"
        print(f"PASS: {' '.join(args) or 'shaded true colour'}; probe, redraw, resize, mode, mouse, Ctrl-Q, termios")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        termios.tcsetattr(slave, termios.TCSANOW, before)
        os.close(master)
        os.close(slave)


if __name__ == "__main__":
    for arguments in [[], ["--wireframe"], ["--256"], ["--16"], ["--box"], ["--pattern"]]:
        run(sys.argv[1], arguments)
