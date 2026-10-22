SolidCraft 98 for Linux and the Raspberry Pi  1.1.1
=================================================

sc98-pi       Raspberry Pi 1 and up (ARMv6, 32-bit Raspberry Pi OS)
sc98-x86_64   64-bit PC Linux

On a Raspberry Pi with the desktop:
    ./sc98-pi
    ./sc98-pi "Samples/Mounting Plate.sc98"

Raspberry Pi OS Lite (no desktop) needs a few small X libraries first,
even to run on the console:
    sudo apt install libx11-6 libxext6 libxpm4 libxrandr2
Then run it from the console (not over ssh); it takes the whole screen.
The mouse needs read access to /dev/input/mice (sudo, or the input group).

How fast is this machine?
    ./sc98-pi --headless --bench "Samples/Mounting Plate.sc98"

Parts (.sc98) open in the Windows version and back, byte for byte.
