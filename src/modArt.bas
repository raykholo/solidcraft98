Attribute VB_Name = "modArt"
' modArt - the logo and the splash backdrop, drawn with Line and Circle
' so there's no bitmap to ship. Our own art: a wireframe block with a hole.
Option Explicit

Public Const APP_NAME As String = "SolidCraft 98"
Public Const APP_EDITION As String = "Professional Edition"
Public Const APP_BUILD As String = "Build 1998.1021"

Public Function AppVersion() As String
    AppVersion = "Version " & App.Major & "." & App.Minor & "." & App.Revision
End Function

' Vertical gradient, the setup-program look. c1 at the top, c2 at the bottom.
Public Sub Gradient(ByVal pic As PictureBox, ByVal c1 As Long, ByVal c2 As Long)
    Dim y As Long, h As Long, t As Double
    Dim r1 As Long, g1 As Long, b1 As Long, r2 As Long, g2 As Long, b2 As Long
    r1 = c1 And &HFF&: g1 = (c1 \ &H100&) And &HFF&: b1 = (c1 \ &H10000) And &HFF&
    r2 = c2 And &HFF&: g2 = (c2 \ &H100&) And &HFF&: b2 = (c2 \ &H10000) And &HFF&
    h = pic.ScaleHeight
    For y = 0 To h Step 2
        t = y / h
        pic.Line (0, y)-(pic.ScaleWidth, y + 2), RGB(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t), BF
    Next y
End Sub

' The logo: an isometric block with a hole in the top, s pixels per unit.
Public Sub DrawLogo(ByVal pic As PictureBox, ByVal ox As Single, ByVal oy As Single, ByVal s As Single, ByVal c As Long)
    Dim i As Integer
    Dim px(0 To 7) As Single, py(0 To 7) As Single
    ' block corners, 4 x 3 x 1.5 units, in screen space
    IsoPt 0, 0, 0, s, ox, oy, px(0), py(0)
    IsoPt 4, 0, 0, s, ox, oy, px(1), py(1)
    IsoPt 4, 3, 0, s, ox, oy, px(2), py(2)
    IsoPt 0, 3, 0, s, ox, oy, px(3), py(3)
    IsoPt 0, 0, 1.5, s, ox, oy, px(4), py(4)
    IsoPt 4, 0, 1.5, s, ox, oy, px(5), py(5)
    IsoPt 4, 3, 1.5, s, ox, oy, px(6), py(6)
    IsoPt 0, 3, 1.5, s, ox, oy, px(7), py(7)
    pic.DrawWidth = 2
    For i = 0 To 3
        pic.Line (px(i), py(i))-(px((i + 1) Mod 4), py((i + 1) Mod 4)), c
        pic.Line (px(i + 4), py(i + 4))-(px((i + 1) Mod 4 + 4), py((i + 1) Mod 4 + 4)), c
        pic.Line (px(i), py(i))-(px(i + 4), py(i + 4)), c
    Next i
    ' the hole: an ellipse on the top face
    Dim hx As Single, hy As Single
    IsoPt 2, 1.5, 1.5, s, ox, oy, hx, hy
    pic.Circle (hx, hy), s * 0.75, c, , , 0.55
    pic.DrawWidth = 1
End Sub

Private Sub IsoPt(ByVal x As Double, ByVal y As Double, ByVal z As Double, ByVal s As Single, _
                  ByVal ox As Single, ByVal oy As Single, sx As Single, sy As Single)
    sx = ox + (x - y) * 0.866 * s
    sy = oy + (x + y) * 0.5 * s - z * s
End Sub
