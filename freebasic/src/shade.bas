' shade.bas - View > Shaded, the software renderer. A port of the Windows
' version's modShade: every triangle is filled in pixel by pixel with a
' depth per pixel; lines go where two faces meet at a corner, and round the
' outline. The slow reveal, a few rows at a time, is in part.bas.

' ---- which triangles make one face (smoothing groups) ----

' Triangles meeting along an edge belong to one face if they come from the
' same feature and meet nearly flat (a cylinder's facets do; a wall and a
' top don't). Edges are matched through a hash table on their end points.

Dim Shared hashKeyT() As Long        ' triangle index, or -1
Dim Shared hashKeyK() As Long        ' which edge of it (0-2)
Dim Shared hashSize As Long

Sub TriCorner(ByRef t As TTri, ByVal k As Long, ByRef x As Double, ByRef y As Double, ByRef z As Double)
    Select Case k
    Case 0: x = t.X1: y = t.Y1: z = t.Z1
    Case 1: x = t.X2: y = t.Y2: z = t.Z2
    Case Else: x = t.X3: y = t.Y3: z = t.Z3
    End Select
End Sub

Function HashD(ByVal v As Double, ByVal h As ULongInt) As ULongInt
    Dim As ULongInt bits = *CPtr(ULongInt Ptr, @v)
    h Xor= bits
    h *= &h100000001B3ULL
    h Xor= (h Shr 29)
    Return h
End Function

Function EdgeHash(ByVal ax As Double, ByVal ay As Double, ByVal az As Double, ByVal bx As Double, ByVal by As Double, ByVal bz As Double) As ULongInt
    Dim As ULongInt h = &hCBF29CE484222325ULL
    h = HashD(ax, h): h = HashD(ay, h): h = HashD(az, h)
    h = HashD(bx, h): h = HashD(by, h): h = HashD(bz, h)
    Return h
End Function

Sub TriNormal(ByRef t As TTri, ByRef nx As Double, ByRef ny As Double, ByRef nz As Double)
    Dim As Double ux = t.X2 - t.X1, uy = t.Y2 - t.Y1, uz = t.Z2 - t.Z1
    Dim As Double vx = t.X3 - t.X1, vy = t.Y3 - t.Y1, vz = t.Z3 - t.Z1
    nx = uy * vz - uz * vy: ny = uz * vx - ux * vz: nz = ux * vy - uy * vx
    Dim As Double l = Sqr(nx * nx + ny * ny + nz * nz)
    If l = 0 Then l = 1
    nx /= l: ny /= l: nz /= l
End Sub

Function Smooth(ByRef a As TTri, ByRef b As TTri) As Boolean
    Dim As Double ax, ay, az, bx, by, bz
    If a.Body <> b.Body Then Return False
    TriNormal a, ax, ay, az
    TriNormal b, bx, by, bz
    Return ax * bx + ay * by + az * bz > 0.9           ' within about 25 degrees
End Function

Function GroupRoot(par() As Long, ByVal i As Long) As Long
    Do While par(i) <> i
        par(i) = par(par(i))
        i = par(i)
    Loop
    Return i
End Function

' g(i) is a face number per triangle, from 1.
Sub FaceGroups(t() As TTri, ByVal n As Long, g() As Long)
    Dim As Long i, k, slot, j, a, b
    Dim As Double ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz
    If n = 0 Then ReDim g(0 To 0): Exit Sub
    ReDim g(0 To n - 1)
    Dim par(0 To n - 1) As Long
    For i = 0 To n - 1: par(i) = i: Next
    hashSize = 1
    Do While hashSize < n * 6: hashSize *= 2: Loop
    ReDim hashKeyT(0 To hashSize - 1): ReDim hashKeyK(0 To hashSize - 1)
    For i = 0 To hashSize - 1: hashKeyT(i) = -1: Next
    ' every directed edge into the table
    For i = 0 To n - 1
        For k = 0 To 2
            TriCorner t(i), k, ax, ay, az
            TriCorner t(i), (k + 1) Mod 3, bx, by, bz
            slot = EdgeHash(ax, ay, az, bx, by, bz) And (hashSize - 1)
            Do While hashKeyT(slot) >= 0
                slot = (slot + 1) And (hashSize - 1)
            Loop
            hashKeyT(slot) = i: hashKeyK(slot) = k
        Next k
    Next i
    ' each edge's twin runs the other way
    For i = 0 To n - 1
        For k = 0 To 2
            TriCorner t(i), k, ax, ay, az
            TriCorner t(i), (k + 1) Mod 3, bx, by, bz
            slot = EdgeHash(bx, by, bz, ax, ay, az) And (hashSize - 1)
            Do While hashKeyT(slot) >= 0
                j = hashKeyT(slot)
                TriCorner t(j), hashKeyK(slot), cx, cy, cz
                TriCorner t(j), (hashKeyK(slot) + 1) Mod 3, dx, dy, dz
                If cx = bx And cy = by And cz = bz And dx = ax And dy = ay And dz = az Then
                    If j > i AndAlso Smooth(t(i), t(j)) Then
                        a = GroupRoot(par(), i): b = GroupRoot(par(), j)
                        If a <> b Then par(a) = b
                    End If
                    Exit Do
                End If
                slot = (slot + 1) And (hashSize - 1)
            Loop
        Next k
    Next i
    For i = 0 To n - 1
        g(i) = GroupRoot(par(), i) + 1
    Next i
End Sub

' ---- the renderer ----

Function ShadeRGB(ByVal r As Long, ByVal g As Long, ByVal b As Long, ByVal k As Double) As ULong
    Return &hFF000000 Or (CULng(r * k) Shl 16) Or (CULng(g * k) Shl 8) Or CULng(b * k)
End Function

Function Min3(ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    Dim m As Double = a
    If b < m Then m = b
    If c < m Then m = c
    Return m
End Function

Function Max3(ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    Dim m As Double = a
    If b > m Then m = b
    If c > m Then m = c
    Return m
End Function

Dim Shared zbuf() As Single
Dim Shared gbuf() As Long

' Fills one triangle into the surface, where it is nearer than what's there.
Sub FillTri(ByVal x1 As Double, ByVal y1 As Double, ByVal d1 As Double, ByVal x2 As Double, ByVal y2 As Double, ByVal d2 As Double, _
            ByVal x3 As Double, ByVal y3 As Double, ByVal d3 As Double, ByVal c As ULong, ByVal grp As Long)
    Dim As Double area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)
    If Abs(area) < 0.000001 Then Exit Sub
    Dim As Long x0 = Int(Min3(x1, x2, x3)), xe = Int(Max3(x1, x2, x3)) + 1
    Dim As Long y0 = Int(Min3(y1, y2, y3)), ye = Int(Max3(y1, y2, y3)) + 1
    If x0 < 0 Then x0 = 0
    If y0 < 0 Then y0 = 0
    If xe > S.w - 1 Then xe = S.w - 1
    If ye > S.h - 1 Then ye = S.h - 1
    Dim As Long x, y, p
    Dim As Double cx, cy, a1, a2, a3
    Dim As Single dep
    For y = y0 To ye
        cy = y + 0.5
        For x = x0 To xe
            cx = x + 0.5
            a1 = ((x3 - x2) * (cy - y2) - (y3 - y2) * (cx - x2)) / area
            a2 = ((x1 - x3) * (cy - y3) - (y1 - y3) * (cx - x3)) / area
            a3 = 1 - a1 - a2
            If a1 >= 0 And a2 >= 0 And a3 >= 0 Then
                dep = a1 * d1 + a2 * d2 + a3 * d3
                p = y * S.w + x
                If dep > zbuf(p) Then
                    zbuf(p) = dep
                    S.px[y * S.pitch + x] = c
                    gbuf(p) = grp
                End If
            End If
        Next x
    Next y
End Sub

' Renders the triangles over what the surface shows now (the grid). The
' caller supplies isHole(feature) so holes are tinted red.
Sub RenderShaded(ByRef v As TView, ByVal t As TTri Ptr, ByVal n As Long, ByVal g As Long Ptr, ByRef d As TDesign)
    Dim As Long vw = S.w, vh = S.h, i, x, y, p, q
    Dim As Double ex, ey, ez, rx, ry, rz, ux, uy, uz, lx, ly, lz, l, nx, ny, nz, k
    Dim As Double x1, y1, d1, x2, y2, d2, x3, y3, d3
    Const EDGE_RGB = &hFF202020
    ReDim zbuf(0 To vw * vh - 1): ReDim gbuf(0 To vw * vh - 1)
    For i = 0 To vw * vh - 1: zbuf(i) = -1E+30: Next

    ' which way is the eye, and the light over the viewer's left shoulder
    ViewAxes v, ex, ey, ez, rx, ry, rz, ux, uy, uz
    lx = ex + 0.6 * ux - 0.4 * rx: ly = ey + 0.6 * uy - 0.4 * ry: lz = ez + 0.6 * uz - 0.4 * rz
    l = Sqr(lx * lx + ly * ly + lz * lz)
    lx /= l: ly /= l: lz /= l

    For i = 0 To n - 1
        TriNormal t[i], nx, ny, nz
        If nx * ex + ny * ey + nz * ez > 0.000001 Then        ' facing us
            k = nx * lx + ny * ly + nz * lz
            If k < 0 Then k = 0
            k = 0.3 + 0.7 * k
            Dim As ULong c
            If d.F(t[i].Body).Kind = FK_HOLE Then c = ShadeRGB(205, 135, 125, k) Else c = ShadeRGB(165, 178, 200, k)
            ProjectPixel v, vw, vh, t[i].X1, t[i].Y1, t[i].Z1, x1, y1, d1
            ProjectPixel v, vw, vh, t[i].X2, t[i].Y2, t[i].Z2, x2, y2, d2
            ProjectPixel v, vw, vh, t[i].X3, t[i].Y3, t[i].Z3, x3, y3, d3
            FillTri x1, y1, d1, x2, y2, d2, x3, y3, d3, c, g[i]
        End If
    Next i

    ' lines where one face meets another, or meets the background
    For y = 0 To vh - 1
        For x = 0 To vw - 1
            p = y * vw + x
            If x < vw - 1 Then
                q = p + 1
                If gbuf(p) <> gbuf(q) Then
                    If gbuf(p) <> 0 Then S.px[y * S.pitch + x] = EDGE_RGB Else S.px[y * S.pitch + x + 1] = EDGE_RGB
                End If
            End If
            If y < vh - 1 Then
                q = p + vw
                If gbuf(p) <> gbuf(q) Then
                    If gbuf(p) <> 0 Then S.px[y * S.pitch + x] = EDGE_RGB Else S.px[(y + 1) * S.pitch + x] = EDGE_RGB
                End If
            End If
        Next x
    Next y
End Sub
