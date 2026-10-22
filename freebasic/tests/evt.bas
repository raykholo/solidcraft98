#include "fbgfx.bi"
ScreenRes 400, 300, 32
Dim e As FB.EVENT
Dim t As Double = Timer
Do While Timer - t < 6
    If ScreenEvent(@e) Then Open Cons For Output As #1: Print #1, "ev"; e.type; e.x; e.y: Close #1
    Dim As Long mx, my, mb
    Sleep 10
Loop
