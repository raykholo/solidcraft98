#!/bin/bash
# Runs SolidCraft 98 on a virtual screen and drives it with a script.
# Usage: podman run --rm -v "$PWD":/w:Z -w /w sc98-lz-x86 bash tests/x11.sh tests/ui-basic.sh [args]
# The script is sourced; it can use: key, type, click, dblclick, shot, wait, win.
set -u
STEPS=$1; shift
OUT=tests/out
mkdir -p "$OUT"
export DISPLAY=:77
Xvfb :77 -screen 0 1024x768x24 >/dev/null 2>&1 &
XPID=$!
sleep 1
./build/SolidCraft98 "$@" >"$OUT/app.log" 2>&1 &
APP=$!
sleep 6
wait_s() { sleep "$1"; }
key() { xdotool key --delay 80 "$@"; sleep 0.4; }
type_() { xdotool type --delay 60 "$1"; sleep 0.3; }
click() { xdotool mousemove "$1" "$2" click 1; sleep 0.5; }
rclick() { xdotool mousemove "$1" "$2" click 3; sleep 0.5; }
dblclick() { xdotool mousemove "$1" "$2" click --repeat 2 --delay 80 1; sleep 0.6; }
drag() { xdotool mousemove "$1" "$2" mousedown 1; sleep 0.2; xdotool mousemove "$3" "$4"; sleep 0.2; xdotool mousemove "$5" "$6"; sleep 0.3; xdotool mouseup 1; sleep 0.5; }
shot() { import -window root "$OUT/$1.png"; echo "shot $1"; }
alive() { kill -0 $APP 2>/dev/null && echo "app alive" || echo "APP GONE"; }
source "$STEPS"
alive
kill $APP 2>/dev/null
sleep 0.5
kill $XPID 2>/dev/null
echo "--- app log"; cat "$OUT/app.log" | tail -20
