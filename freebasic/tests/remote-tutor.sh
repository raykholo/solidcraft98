#!/bin/bash
# The remote control's help: "how", the tutor line, "Did you mean", and "yes".
# Usage: tests/remote-tutor.sh [build/sc98]
set -e
cd "$(dirname "$0")/.."
exe=$(readlink -f "${1:-build/sc98}")
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
out=$(printf '%s\n' look "how cube" yes look "key esc" "menu Features > Round" "menu Featres > Extrude" \
    "select Turbo" "click Turbp" quit | (cd "$home" && HOME=$home timeout 60 "$exe" --remote --headless 2>/dev/null))
fail=0
want() { grep -qF -- "$1" <<<"$out" || { echo "missing: $1"; fail=1; }; }
want 'Tutor: This part is empty.'
want 'A box, cube, block or plate: menu Sketch > Rectangle...'
want 'Say "yes" to do: menu Sketch > Rectangle...'
want 'Dialog "Sketch Rectangle", on top'
want 'Tutor: This dialog wants numbers.'
want "SolidCraft 98 can't round or chamfer"
want 'but the Features menu has "Extrude...". Say "yes" to do: menu Features > Extrude...'
want 'Did you mean "click Turbo"?'
want 'Did you mean "turbo"? Say "yes" to do: click turbo'
[ $fail = 0 ] && echo "remote-tutor: ok"
exit $fail
