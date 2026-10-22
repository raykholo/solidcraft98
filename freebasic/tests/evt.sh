export DISPLAY=:7
Xvfb :7 -screen 0 800x600x24 >/dev/null 2>&1 &
sleep 1.5
./build/evt &
sleep 1.5
W=$(xdotool search --name evt | head -1); echo "win=$W"; xdotool getwindowgeometry $W
xdotool mousemove 100 100; sleep 0.3; xdotool click 1; sleep 0.3; xdotool key a; sleep 0.3
xdotool getmouselocation
wait
