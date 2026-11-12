#!/usr/bin/env python3
"""Exercise SolidCraft 98 in a real PTY, including files and termios cleanup."""
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


def drain(master, seconds=0.3):
    output = bytearray()
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if select.select([master], [], [], 0.05)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError:
                break
    return bytes(output)


def main(binary):
    binary = str(Path(binary).resolve())
    with tempfile.TemporaryDirectory(prefix="sc98-app-") as root:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 160, 0, 0))
        before = termios.tcgetattr(slave)
        process = subprocess.Popen([binary, "--new"], cwd=root, stdin=slave,
                                   stdout=slave, stderr=slave, close_fds=True)
        try:
            output = drain(master, 1.0)
            # Complete probe, create a box, save, export via File menu, quit.
            for sequence in [b"\x1b[60;160R", b"r\r", b"e\r", b"\x13\r",
                             b"\x1bf" + b"\x1b[B" * 6 + b"\r\r", b"\x11"]:
                os.write(master, sequence)
                output += drain(master, 0.5)
            process.wait(timeout=10)
            output += drain(master)
            assert process.returncode == 0, output[-2000:]
            assert (Path(root) / "Part1.sc98").stat().st_size == 8648
            assert (Path(root) / "Part1.stl").stat().st_size == 684
            assert termios.tcgetattr(slave) == before, "termios not restored"
            assert b"\x1b[?1049h" in output and b"\x1b[?1049l" in output
            print("PASS: raw terminal, probe, rectangle, extrude, save, STL, quit, termios restoration")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    main(sys.argv[1])
