Attribute VB_Name = "modView"
' modView - projects the edges and draws them on a PictureBox, one Line at a time.
Option Explicit

Public Type TView
    Yaw As Double       ' degrees, about Z
    Pitch As Double     ' degrees, down from the horizon
    Zoom As Double      ' pixels per mm
    PanX As Double      ' pixels
    PanY As Double
End Type

Public Const ISO_YAW As Double = 45
Public Const ISO_PITCH As Double = 35.264

Public Sub ResetView(v As TView)
    v.Yaw = ISO_YAW
    v.Pitch = ISO_PITCH
    v.Zoom = 3
    v.PanX = 0
    v.PanY = 0
End Sub

' 3D mm -> 2D pixels, before zoom and pan. sx right, sy up.
Public Sub ProjectRaw(v As TView, ByVal x As Double, ByVal y As Double, ByVal z As Double, sx As Double, sy As Double)
    Dim cy As Double, sy_ As Double, cp As Double, sp As Double, x1 As Double, y1 As Double
    cy = Cos(v.Yaw * PI / 180): sy_ = Sin(v.Yaw * PI / 180)
    cp = Cos(v.Pitch * PI / 180): sp = Sin(v.Pitch * PI / 180)
    x1 = x * cy - y * sy_
    y1 = x * sy_ + y * cy
    sx = x1
    sy = z * cp - y1 * sp
End Sub

Private Sub ToScreen(v As TView, pic As PictureBox, ByVal x As Double, ByVal y As Double, ByVal z As Double, px As Single, py As Single)
    Dim sx As Double, sy As Double
    ProjectRaw v, x, y, z, sx, sy
    px = pic.ScaleWidth / 2 + v.PanX + sx * v.Zoom
    py = pic.ScaleHeight / 2 + v.PanY - sy * v.Zoom
End Sub

' Zoom and pan so every edge fits, with a margin.
Public Sub FitView(v As TView, pic As PictureBox, e() As TEdge, ByVal n As Long)
    Dim i As Long, sx As Double, sy As Double
    Dim minX As Double, maxX As Double, minY As Double, maxY As Double
    Dim w As Double, h As Double
    If n = 0 Then
        v.Zoom = 3: v.PanX = 0: v.PanY = 0
        Exit Sub
    End If
    minX = 1E+30: minY = 1E+30: maxX = -1E+30: maxY = -1E+30
    For i = 0 To n - 1
        ProjectRaw v, e(i).X1, e(i).Y1, e(i).Z1, sx, sy
        GrowBox sx, sy, minX, maxX, minY, maxY
        ProjectRaw v, e(i).X2, e(i).Y2, e(i).Z2, sx, sy
        GrowBox sx, sy, minX, maxX, minY, maxY
    Next i
    w = maxX - minX: h = maxY - minY
    If w < 1 Then w = 1
    If h < 1 Then h = 1
    v.Zoom = 0.8 * pic.ScaleWidth / w
    If 0.8 * pic.ScaleHeight / h < v.Zoom Then v.Zoom = 0.8 * pic.ScaleHeight / h
    v.PanX = -(minX + maxX) / 2 * v.Zoom
    v.PanY = (minY + maxY) / 2 * v.Zoom
End Sub

Private Sub GrowBox(ByVal x As Double, ByVal y As Double, minX As Double, maxX As Double, minY As Double, maxY As Double)
    If x < minX Then minX = x
    If x > maxX Then maxX = x
    If y < minY Then minY = y
    If y > maxY Then maxY = y
End Sub

Public Sub DrawScene(v As TView, pic As PictureBox, e() As TEdge, ByVal n As Long)
    Dim i As Long, ax As Single, ay As Single, bx As Single, by As Single
    pic.Cls
    DrawGrid v, pic
    pic.DrawWidth = 1
    For i = 0 To n - 1
        ToScreen v, pic, e(i).X1, e(i).Y1, e(i).Z1, ax, ay
        ToScreen v, pic, e(i).X2, e(i).Y2, e(i).Z2, bx, by
        pic.Line (ax, ay)-(bx, by), e(i).Color
    Next i
    DrawTriad v, pic
End Sub

' A faint floor grid, 10 mm squares, so an empty part isn't just grey.
Private Sub DrawGrid(v As TView, pic As PictureBox)
    Dim i As Integer, ax As Single, ay As Single, bx As Single, by As Single
    Const G As Double = 50
    For i = -5 To 5
        ToScreen v, pic, i * 10, -G, 0, ax, ay
        ToScreen v, pic, i * 10, G, 0, bx, by
        pic.Line (ax, ay)-(bx, by), &HB8B8B8
        ToScreen v, pic, -G, i * 10, 0, ax, ay
        ToScreen v, pic, G, i * 10, 0, bx, by
        pic.Line (ax, ay)-(bx, by), &HB8B8B8
    Next i
End Sub

' X red, Y green, Z blue, bottom left. Drawn without zoom so it stays the same size.
Private Sub DrawTriad(v As TView, pic As PictureBox)
    Dim ox As Single, oy As Single, sx As Double, sy As Double
    ox = 40: oy = pic.ScaleHeight - 40
    ProjectRaw v, 25, 0, 0, sx, sy
    pic.Line (ox, oy)-(ox + sx, oy - sy), vbRed
    pic.CurrentX = ox + sx + 2: pic.CurrentY = oy - sy - 6: pic.ForeColor = vbRed: pic.Print "X"
    ProjectRaw v, 0, 25, 0, sx, sy
    pic.Line (ox, oy)-(ox + sx, oy - sy), &H8000&
    pic.CurrentX = ox + sx + 2: pic.CurrentY = oy - sy - 6: pic.ForeColor = &H8000&: pic.Print "Y"
    ProjectRaw v, 0, 0, 25, sx, sy
    pic.Line (ox, oy)-(ox + sx, oy - sy), vbBlue
    pic.CurrentX = ox + sx + 2: pic.CurrentY = oy - sy - 6: pic.ForeColor = vbBlue: pic.Print "Z"
    pic.ForeColor = vbBlack
End Sub
