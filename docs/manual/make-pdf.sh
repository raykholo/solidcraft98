#!/bin/bash
# Prints the manual to SolidCraft98-Definitive-Guide.pdf with headless Chrome
# (or Chromium). Usage: docs/manual/make-pdf.sh
set -e
cd "$(dirname "$0")"
d=$PWD
out="$d/SolidCraft98-Definitive-Guide.pdf"
if command -v chromium >/dev/null; then
  chrome=(chromium)
elif command -v google-chrome >/dev/null; then
  chrome=(google-chrome)
else
  chrome=(flatpak run --filesystem="$d" com.google.Chrome)
fi
"${chrome[@]}" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$out" "file://$d/index.html" 2>/dev/null
ls -la "$out"
