# Edit, delete with dependents, undo, revolve, Konami, and Y2K (run with --y2ktest).
sleep 3
key r
key Return
key e
key Return
key h
key Return
sleep 1
click 300 517
key Return
sleep 1
shot m01-edit-dlg
key Escape
click 300 517
key Delete
sleep 1
shot m02-delete-ask
key alt+y
sleep 1
shot m03-deleted
key c
key Tab
key ctrl+a
type_ 30
key Return
key v
key Return
sleep 1
shot m04-revolve
key ctrl+z
sleep 1
shot m05-undo
key Up Up Down Down Left Right Left Right b a
sleep 1
shot m06-konami
sleep 3
key alt+v
key t
sleep 1
shot m07-y2k
