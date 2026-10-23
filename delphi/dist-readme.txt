SolidCraft 98 Delphi Edition  1.2
=================================

SolidCraft98.exe   Windows (and ReactOS)
sc98-x86_64        64-bit PC Linux
sc98-pi            Raspberry Pi 1 and up (ARMv6, 32-bit Raspberry Pi OS)

The Linux versions need a desktop and GTK 2:
    sudo apt install libgtk2.0-0
Then:
    ./sc98-pi
    ./sc98-pi "Samples/Mounting Plate.sc98"

Parts (.sc98) open in the other editions of SolidCraft 98 and back, byte
for byte. SolidCraft designs (.solidcraft) open too.

To see the Y2K bug without touching the clock:
    ./sc98-pi --y2ktest       (Windows: SolidCraft98.exe /Y2KTEST)
then switch Turbo on and wait a minute.
