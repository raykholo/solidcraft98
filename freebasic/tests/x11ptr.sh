export HOME=/w/tests/home DISPLAY=:7
Xvfb :7 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1.5
./build/sc98 > tests/out/x11.log 2>&1 &
sleep 2.5
W=$(xdotool search --name "SolidCraft 98" | head -1); xdotool windowmove $W 0 0; xdotool windowfocus $W; sleep 0.5
shot() { xwd -root -silent | convert xwd:- -crop 800x600+0+0 +repage "tests/out/$1.png"; }
xdotool mousemove 300 300; sleep 0.5; shot p1
xdotool mousemove 420 360; sleep 0.5; shot p2
xdotool mousemove 600 450; sleep 0.5; shot p3
