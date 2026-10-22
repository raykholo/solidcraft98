' view.bas - projection, orbit and the wireframe, one line at a time.
' A port of the Windows version's modView. Drawing goes to the current
' surface S, whose size is the viewport's.

Type TView
    Yaw As Double       ' degrees, about Z
    Pitch As Double     ' degrees, down from the horizon
    Zoom As Double      ' pixels per mm
    PanX As Double      ' pixels
    PanY As Double
End Type

Const ISO_YAW = 135         ' looking at the front, right and top
Const ISO_PITCH = 35.264

Sub ResetView(ByRef v As TView)
    v.Yaw = ISO_YAW: v.Pitch = ISO_PITCH
    v.Zoom = 3: v.PanX = 0: v.PanY = 0
End Sub

' 3D mm -> 2D pixels, before zoom and pan. sx right, sy up.
Sub ProjectRaw(ByRef v As TView, ByVal x As Double, ByVal y As Double, ByVal z As Double, ByRef sx As Double, ByRef sy As Double)
    Dim As Double cy = Cos(v.Yaw * PI / 180), syw = Sin(v.Yaw * PI / 180)
    Dim As Double cp = Cos(v.Pitch * PI / 180), sp = Sin(v.Pitch * PI / 180)
    Dim As Double x1 = x * cy - y * syw, y1 = x * syw + y * cy
    sx = -x1
    sy = z * cp - y1 * sp
End Sub

' The view's directions in model space: toward the eye, screen right, screen up.
Sub ViewAxes(ByRef v As TView, ByRef ex As Double, ByRef ey As Double, ByRef ez As Double, _
             ByRef rx As Double, ByRef ry As Double, ByRef rz As Double, ByRef ux As Double, ByRef uy As Double, ByRef uz As Double)
    Dim As Double cy = Cos(v.Yaw * PI / 180), syw = Sin(v.Yaw * PI / 180)
    Dim As Double cp = Cos(v.Pitch * PI / 180), sp = Sin(v.Pitch * PI / 180)
    ex = syw * cp: ey = cy * cp: ez = sp
    rx = -cy: ry = syw: rz = 0
    ux = -syw * sp: uy = -cy * sp: uz = cp
End Sub

Sub ToScreen(ByRef v As TView, ByVal vw As Long, ByVal vh As Long, ByVal x As Double, ByVal y As Double, ByVal z As Double, ByRef px As Long, ByRef py As Long)
    Dim As Double sx, sy
    ProjectRaw v, x, y, z, sx, sy
    px = CLng(vw / 2 + v.PanX + sx * v.Zoom)
    py = CLng(vh / 2 + v.PanY - sy * v.Zoom)
End Sub

' 3D mm -> pixel position, and depth (bigger is nearer), for the shaded view.
Sub ProjectPixel(ByRef v As TView, ByVal vw As Long, ByVal vh As Long, ByVal x As Double, ByVal y As Double, ByVal z As Double, _
                 ByRef px As Double, ByRef py As Double, ByRef dep As Double)
    Dim As Double sx, sy, ex, ey, ez, rx, ry, rz, ux, uy, uz
    ProjectRaw v, x, y, z, sx, sy
    px = vw / 2 + v.PanX + sx * v.Zoom
    py = vh / 2 + v.PanY - sy * v.Zoom
    ViewAxes v, ex, ey, ez, rx, ry, rz, ux, uy, uz
    dep = x * ex + y * ey + z * ez
End Sub

Sub GrowBox(ByVal x As Double, ByVal y As Double, ByRef minX As Double, ByRef maxX As Double, ByRef minY As Double, ByRef maxY As Double)
    If x < minX Then minX = x
    If x > maxX Then maxX = x
    If y < minY Then minY = y
    If y > maxY Then maxY = y
End Sub

' Zoom and pan so every edge fits, with a margin.
Sub FitView(ByRef v As TView, ByVal vw As Long, ByVal vh As Long, ByVal e As TEdge Ptr, ByVal n As Long)
    Dim As Long i
    Dim As Double sx, sy, minX = 1E+30, maxX = -1E+30, minY = 1E+30, maxY = -1E+30, w, h
    If n = 0 Then v.Zoom = 3: v.PanX = 0: v.PanY = 0: Exit Sub
    For i = 0 To n - 1
        ProjectRaw v, e[i].X1, e[i].Y1, e[i].Z1, sx, sy: GrowBox sx, sy, minX, maxX, minY, maxY
        ProjectRaw v, e[i].X2, e[i].Y2, e[i].Z2, sx, sy: GrowBox sx, sy, minX, maxX, minY, maxY
    Next i
    w = maxX - minX: h = maxY - minY
    If w < 1 Then w = 1
    If h < 1 Then h = 1
    v.Zoom = 0.8 * vw / w
    If 0.8 * vh / h < v.Zoom Then v.Zoom = 0.8 * vh / h
    v.PanX = -(minX + maxX) / 2 * v.Zoom
    v.PanY = (minY + maxY) / 2 * v.Zoom
End Sub

Sub DrawEdge(ByRef v As TView, ByVal vw As Long, ByVal vh As Long, ByRef e As TEdge)
    Dim As Long ax, ay, bx, by
    ToScreen v, vw, vh, e.X1, e.Y1, e.Z1, ax, ay
    ToScreen v, vw, vh, e.X2, e.Y2, e.Z2, bx, by
    DrawLine ax, ay, bx, by, e.Col
End Sub

' A faint floor grid, 10 mm squares, so an empty part isn't just grey.
Sub DrawGrid(ByRef v As TView, ByVal vw As Long, ByVal vh As Long)
    Dim As Long i, ax, ay, bx, by
    Const G = 50
    For i = -5 To 5
        ToScreen v, vw, vh, i * 10, -G, 0, ax, ay
        ToScreen v, vw, vh, i * 10, G, 0, bx, by
        DrawLine ax, ay, bx, by, &hFFB8B8B8
        ToScreen v, vw, vh, -G, i * 10, 0, ax, ay
        ToScreen v, vw, vh, G, i * 10, 0, bx, by
        DrawLine ax, ay, bx, by, &hFFB8B8B8
    Next i
End Sub

' X red, Y green, Z blue, bottom left. Drawn without zoom so it stays the same size.
Sub DrawTriad(ByRef v As TView, ByVal vh As Long)
    Dim As Long ox = 40, oy = vh - 40
    Dim As Double sx, sy
    ProjectRaw v, 25, 0, 0, sx, sy
    DrawLine ox, oy, ox + sx, oy - sy, &hFFFF0000
    Text ox + sx + 2, oy - sy - 6, "X", &hFFFF0000
    ProjectRaw v, 0, 25, 0, sx, sy
    DrawLine ox, oy, ox + sx, oy - sy, &hFF008000
    Text ox + sx + 2, oy - sy - 6, "Y", &hFF008000
    ProjectRaw v, 0, 0, 25, sx, sy
    DrawLine ox, oy, ox + sx, oy - sy, &hFF0000FF
    Text ox + sx + 2, oy - sy - 6, "Z", &hFF0000FF
End Sub

' Background, grid, the edges (n of them; 0 for none), triad.
Sub DrawScene(ByRef v As TView, ByVal vw As Long, ByVal vh As Long, ByVal e As TEdge Ptr, ByVal n As Long)
    Dim i As Long
    Fill 0, 0, vw, vh, &hFFE0E0E0
    DrawGrid v, vw, vh
    For i = 0 To n - 1
        DrawEdge v, vw, vh, e[i]
    Next i
    DrawTriad v, vh
End Sub
