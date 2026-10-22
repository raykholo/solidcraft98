#!/bin/bash
# Real X11 run: the app in Xvfb, driven by xdotool, screenshots with xwd.
# Usage: podman run --rm -v "$PWD":/w:Z -w /w sc98-fb-x86 bash tests/x11.sh
export HOME=/w/tests/home DISPLAY=:7
mkdir -p $HOME/Documents tests/out
Xvfb :7 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1.5
./build/sc98 "tests/Mounting Plate.sc98" > tests/out/x11.log 2>&1 &
APP=$!
sleep 2
shot() { xwd -root -silent | convert xwd:- -crop 800x600+0+0 +repage "tests/out/$1.png"; }
W=$(xdotool search --name "SolidCraft 98" | head -1)
xdotool windowmove $W 0 0; xdotool windowfocus $W; sleep 0.5
OX=$(xdotool getwindowgeometry $W | sed -n 's/.*Position: \([0-9]*\),\([0-9]*\).*/\1/p'); OY=$(xdotool getwindowgeometry $W | sed -n 's/.*Position: [0-9]*,\([0-9]*\).*/\1/p')
echo "window $W at $OX,$OY"
shot y01_open
xdotool mousemove $((OX+260)) $((OY+37)) click 1; sleep 2.2      # Shaded
shot y02_shaded
xdotool mousemove $((OX+500)) $((OY+250)) mousedown 1; for i in 1 2 3 4 5 6 7 8; do xdotool mousemove_relative 12 3; sleep 0.05; done; shot y03_orbiting; xdotool mouseup 1; sleep 2
shot y04_reshaded
for i in 1 2 3 4 5 6; do xdotool mousemove_relative 40 25; sleep 0.1; done; sleep 0.3; shot y045_moved
xdotool key r; sleep 0.5; shot y05_dialog; xdotool key Escape; sleep 0.3
xdotool mousemove $((OX+90)) $((OY+489)); xdotool click --repeat 2 --delay 120 1; sleep 0.6
shot y06_edit
xdotool type 12; xdotool key Return; sleep 2.2
shot y07_edited
kill $APP 2>/dev/null; sleep 0.3
