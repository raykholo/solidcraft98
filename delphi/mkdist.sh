#!/bin/bash
# Packs the three builds with the samples into dist/.
# Needs build/SolidCraft98 (./build.sh), build/arm/SolidCraft98
# (./build-arm.sh) and build/win/SolidCraft98.exe (Lazarus on Windows).
set -e
cd "$(dirname "$0")"
V=1.2
D=dist/SolidCraft98-Delphi-$V
rm -rf dist && mkdir -p "$D/Samples"
cp build/SolidCraft98 "$D/sc98-x86_64"
cp build/arm/SolidCraft98 "$D/sc98-pi"
cp build/win/SolidCraft98.exe "$D/SolidCraft98.exe"
sed 's/$/\r/' dist-readme.txt > "$D/README.TXT"
cp "tests/Mounting Plate.sc98" tests/*.solidcraft "$D/Samples/"
cp ../LICENSE ../NOTICE "$D/"
(cd dist && zip -qr "SolidCraft98-Delphi-$V.zip" "SolidCraft98-Delphi-$V")
ls -la dist/*.zip "$D"
