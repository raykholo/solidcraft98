# Cal's "Don't show me this tip again" with Turbo on: the tip is pinned,
# and the x closes it. Turbo off is the plain message box (ui-basic).
rm -f tests/out/cp-*.png
sleep 3
key alt+v
key t
key r
key Return
sleep 2
shot cp-01-cal
click 749 631
sleep 1
shot cp-02-pinned
click 885 614
sleep 1
shot cp-03-closed
