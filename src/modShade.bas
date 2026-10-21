Attribute VB_Name = "modShade"
' modShade - View > Shaded. A software renderer, as was the custom: every
' triangle of the part is filled in pixel by pixel, off screen, keeping a
' depth for each pixel so near things hide far things. Lines are drawn where
' two faces meet at a corner and round the outline. Then the picture goes
' up a few rows at a time, top to bottom, because rendering is supposed to
' take a while. With Turbo on it takes longer still.
Option Explicit

Public ViewShaded As Boolean
Public ShadeGen(0 To MAX_DOCS) As Long    ' per part: goes up when its picture is redrawn, which stops a render of it in progress

Private Type BITMAPINFOHEADER
    biSize As Long
    biWidth As Long
    biHeight As Long
    biPlanes As Integer
    biBitCount As Integer
    biCompression As Long
    biSizeImage As Long
    biXPelsPerMeter As Long
    biYPelsPerMeter As Long
    biClrUsed As Long
    biClrImportant As Long
End Type

Private Type BITMAPINFO
    bmiHeader As BITMAPINFOHEADER
    bmiColors As Long
End Type

Private Declare Function CreateCompatibleDC Lib "gdi32" (ByVal hdc As Long) As Long
Private Declare Function CreateCompatibleBitmap Lib "gdi32" (ByVal hdc As Long, ByVal nWidth As Long, ByVal nHeight As Long) As Long
Private Declare Function SelectObject Lib "gdi32" (ByVal hdc As Long, ByVal hObject As Long) As Long
Private Declare Function DeleteObject Lib "gdi32" (ByVal hObject As Long) As Long
Private Declare Function DeleteDC Lib "gdi32" (ByVal hdc As Long) As Long
Private Declare Function BitBlt Lib "gdi32" (ByVal hDestDC As Long, ByVal x As Long, ByVal y As Long, ByVal nWidth As Long, ByVal nHeight As Long, _
    ByVal hSrcDC As Long, ByVal xSrc As Long, ByVal ySrc As Long, ByVal dwRop As Long) As Long
Private Declare Function GetDIBits Lib "gdi32" (ByVal hdc As Long, ByVal hBitmap As Long, ByVal nStartScan As Long, ByVal nNumScans As Long, _
    lpBits As Any, lpBI As BITMAPINFO, ByVal wUsage As Long) As Long
Private Declare Function SetDIBitsToDevice Lib "gdi32" (ByVal hdc As Long, ByVal x As Long, ByVal y As Long, ByVal dx As Long, ByVal dy As Long, _
    ByVal SrcX As Long, ByVal SrcY As Long, ByVal Scan As Long, ByVal NumScans As Long, Bits As Any, BitsInfo As BITMAPINFO, ByVal wUsage As Long) As Long
Private Declare Function GetTickCount Lib "kernel32" () As Long
Private Declare Sub Sleep Lib "kernel32" (ByVal dwMilliseconds As Long)

Private Const SRCCOPY As Long = &HCC0020
Private Const BAND_ROWS As Long = 6
Private Const EDGE_RGB As Long = &H202020

' Which triangles make up one face: neighbours on the same feature that
' meet nearly flat (the facets of a cylinder do; a wall and a top don't).
' g(i) is a number per face, from 1.
Public Sub FaceGroups(t() As TTri, ByVal n As Long, g() As Long)
    Dim edges As Collection, par() As Long, i As Long, k As Integer, j As Long, a As Long, b As Long
    Set edges = New Collection
    If n = 0 Then ReDim g(0 To 0): Exit Sub
    ReDim par(0 To n - 1): ReDim g(0 To n - 1)
    For i = 0 To n - 1
        par(i) = i
    Next i
    On Error Resume Next
    For i = 0 To n - 1
        For k = 0 To 2
            edges.Add i, EdgeKey(t(i), k, False)
        Next k
    Next i
    For i = 0 To n - 1
        For k = 0 To 2
            Err.Clear
            j = edges(EdgeKey(t(i), k, True))        ' the triangle across this edge
            If Err.Number = 0 Then
                If j > i Then
                    If Smooth(t(i), t(j)) Then
                        a = Root(par, i): b = Root(par, j)
                        If a <> b Then par(a) = b
                    End If
                End If
            End If
        Next k
    Next i
    On Error GoTo 0
    For i = 0 To n - 1
        g(i) = Root(par, i) + 1
    Next i
End Sub

Private Function Root(par() As Long, ByVal i As Long) As Long
    Do While par(i) <> i
        par(i) = par(par(i))
        i = par(i)
    Loop
    Root = i
End Function

Private Function EdgeKey(t As TTri, ByVal k As Integer, ByVal bBackwards As Boolean) As String
    Dim a As String, b As String
    a = Corner(t, k): b = Corner(t, (k + 1) Mod 3)
    If bBackwards Then EdgeKey = b & ">" & a Else EdgeKey = a & ">" & b
End Function

Private Function Corner(t As TTri, ByVal k As Integer) As String
    Select Case k
    Case 0: Corner = CStr(t.X1) & "," & CStr(t.Y1) & "," & CStr(t.Z1)
    Case 1: Corner = CStr(t.X2) & "," & CStr(t.Y2) & "," & CStr(t.Z2)
    Case Else: Corner = CStr(t.X3) & "," & CStr(t.Y3) & "," & CStr(t.Z3)
    End Select
End Function

Private Function Smooth(a As TTri, b As TTri) As Boolean
    Dim ax As Double, ay As Double, az As Double, bx As Double, by As Double, bz As Double
    If a.Body <> b.Body Then Exit Function
    Normal a, ax, ay, az
    Normal b, bx, by, bz
    Smooth = (ax * bx + ay * by + az * bz > 0.9)      ' within about 25 degrees
End Function

Private Sub Normal(t As TTri, nx As Double, ny As Double, nz As Double)
    Dim ux As Double, uy As Double, uz As Double, vx As Double, vy As Double, vz As Double, l As Double
    ux = t.X2 - t.X1: uy = t.Y2 - t.Y1: uz = t.Z2 - t.Z1
    vx = t.X3 - t.X1: vy = t.Y3 - t.Y1: vz = t.Z3 - t.Z1
    nx = uy * vz - uz * vy: ny = uz * vx - ux * vz: nz = ux * vy - uy * vx
    l = Sqr(nx * nx + ny * ny + nz * nz)
    If l = 0 Then l = 1
    nx = nx / l: ny = ny / l: nz = nz / l
End Sub

' Renders the triangles over what pic shows now (the grid). False if it was
' stopped part way because something else wanted the picture.
Public Function RenderShaded(ByVal slot As Integer, v As TView, pic As PictureBox, t() As TTri, ByVal n As Long, g() As Long) As Boolean
    Dim w As Long, h As Long, gen As Long, bmi As BITMAPINFO, px() As Long, zb() As Single, gid() As Long
    Dim ex As Double, ey As Double, ez As Double, rx As Double, ry As Double, rz As Double
    Dim ux As Double, uy As Double, uz As Double, lx As Double, ly As Double, lz As Double, l As Double
    Dim i As Long, x As Long, y As Long, p As Long, q As Long, c As Long
    Dim nx As Double, ny As Double, nz As Double, k As Double
    Dim x1 As Double, y1 As Double, d1 As Double, x2 As Double, y2 As Double, d2 As Double, x3 As Double, y3 As Double, d3 As Double
    Dim t0 As Long, total As Long, due As Long, sWhat As String, band As BITMAPINFO

    ShadeGen(slot) = ShadeGen(slot) + 1
    gen = ShadeGen(slot)
    w = pic.ScaleWidth: h = pic.ScaleHeight
    If w < 2 Or h < 2 Then Exit Function
    With bmi.bmiHeader
        .biSize = Len(bmi.bmiHeader)
        .biWidth = w
        .biHeight = h                 ' bottom-up: row 0 is the bottom of the picture
        .biPlanes = 1
        .biBitCount = 32
    End With
    ReDim px(0 To w * h - 1): ReDim zb(0 To w * h - 1): ReDim gid(0 To w * h - 1)
    Grab pic, w, h, bmi, px
    For p = 0 To w * h - 1
        zb(p) = -1E+30
    Next p

    ' which way is the eye, and the light over the viewer's left shoulder
    ViewAxes v, ex, ey, ez, rx, ry, rz, ux, uy, uz
    lx = ex + 0.6 * ux - 0.4 * rx: ly = ey + 0.6 * uy - 0.4 * ry: lz = ez + 0.6 * uz - 0.4 * rz
    l = Sqr(lx * lx + ly * ly + lz * lz)
    lx = lx / l: ly = ly / l: lz = lz / l

    For i = 0 To n - 1
        Normal t(i), nx, ny, nz
        If nx * ex + ny * ey + nz * ez > 0.000001 Then        ' facing us
            k = nx * lx + ny * ly + nz * lz
            If k < 0 Then k = 0
            k = 0.3 + 0.7 * k
            If Docs(slot).Features(t(i).Body).Kind = FK_HOLE Then c = Shade(205, 135, 125, k) Else c = Shade(165, 178, 200, k)
            ProjectPixel v, pic, t(i).X1, t(i).Y1, t(i).Z1, x1, y1, d1
            ProjectPixel v, pic, t(i).X2, t(i).Y2, t(i).Z2, x2, y2, d2
            ProjectPixel v, pic, t(i).X3, t(i).Y3, t(i).Z3, x3, y3, d3
            FillTri px, zb, gid, w, h, x1, y1, d1, x2, y2, d2, x3, y3, d3, c, g(i)
        End If
    Next i

    ' lines where one face meets another, or meets the background
    For y = 0 To h - 1
        For x = 0 To w - 1
            p = (h - 1 - y) * w + x
            If x < w - 1 Then
                q = p + 1
                If gid(p) <> gid(q) Then
                    If gid(p) <> 0 Then px(p) = EDGE_RGB Else px(q) = EDGE_RGB
                End If
            End If
            If y < h - 1 Then
                q = p - w
                If gid(p) <> gid(q) Then
                    If gid(p) <> 0 Then px(p) = EDGE_RGB Else px(q) = EDGE_RGB
                End If
            End If
        Next x
    Next y

    ' and now, slowly, show it
    If Turbo Then
        total = 4000
        sWhat = "Rendering at Turbo quality"
    Else
        total = 1500
        sWhat = "Rendering"
    End If
    t0 = GetTickCount()
    For y = 0 To h - 1 Step BAND_ROWS
        If ShadeGen(slot) <> gen Then Exit Function
        x = BAND_ROWS
        If y + x > h Then x = h - y
        ' a band's rows are one run of the bottom-up picture: hand over just
        ' those, as a picture of their own (some systems get the offsets wrong)
        band = bmi
        band.bmiHeader.biHeight = x
        SetDIBitsToDevice pic.hDC, 0, y, w, x, 0, 0, 0, x, px((h - y - x) * w), band, 0
        pic.Refresh
        frmMain.SetStatus sWhat & "... " & Int(100 * (y + x) / h) & "%"
        due = t0 + total * (y + x) / h
        Do
            DoEvents
            If ShadeGen(slot) <> gen Then Exit Function
            If GetTickCount() - due >= 0 Then Exit Do
            Sleep 10
        Loop
    Next y
    If Turbo Then
        frmMain.SetStatus "Shaded at Turbo quality in " & Format$((GetTickCount() - t0) / 1000, "0.0") & " seconds. Every pixel was rendered twice, to be sure."
    Else
        frmMain.SetStatus "Shaded in " & Format$((GetTickCount() - t0) / 1000, "0.0") & " seconds."
    End If
    RenderShaded = True
End Function

' Copies what pic shows now into px(), in the DIB's layout.
Private Sub Grab(pic As PictureBox, ByVal w As Long, ByVal h As Long, bmi As BITMAPINFO, px() As Long)
    Dim hMem As Long, hBmp As Long, hOld As Long
    hMem = CreateCompatibleDC(pic.hDC)
    hBmp = CreateCompatibleBitmap(pic.hDC, w, h)
    hOld = SelectObject(hMem, hBmp)
    BitBlt hMem, 0, 0, w, h, pic.hDC, 0, 0, SRCCOPY
    SelectObject hMem, hOld
    GetDIBits hMem, hBmp, 0, h, px(0), bmi, 0
    DeleteObject hBmp
    DeleteDC hMem
End Sub

' r, g, b scaled by k, as a DIB pixel (blue in the low byte).
Private Function Shade(ByVal r As Long, ByVal g As Long, ByVal b As Long, ByVal k As Double) As Long
    Shade = Int(r * k) * &H10000 + Int(g * k) * &H100& + Int(b * k)
End Function

' Fills one triangle into px(), where it is nearer than what's there.
Private Sub FillTri(px() As Long, zb() As Single, gid() As Long, ByVal w As Long, ByVal h As Long, _
        ByVal x1 As Double, ByVal y1 As Double, ByVal d1 As Double, ByVal x2 As Double, ByVal y2 As Double, ByVal d2 As Double, _
        ByVal x3 As Double, ByVal y3 As Double, ByVal d3 As Double, ByVal c As Long, ByVal grp As Long)
    Dim area As Double, x0 As Long, xe As Long, y0 As Long, ye As Long, x As Long, y As Long, p As Long
    Dim cx As Double, cy As Double, a1 As Double, a2 As Double, a3 As Double, dep As Single
    area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)
    If Abs(area) < 0.000001 Then Exit Sub
    x0 = Int(Min3(x1, x2, x3)): xe = Int(Max3(x1, x2, x3)) + 1
    y0 = Int(Min3(y1, y2, y3)): ye = Int(Max3(y1, y2, y3)) + 1
    If x0 < 0 Then x0 = 0
    If y0 < 0 Then y0 = 0
    If xe > w - 1 Then xe = w - 1
    If ye > h - 1 Then ye = h - 1
    For y = y0 To ye
        cy = y + 0.5
        For x = x0 To xe
            cx = x + 0.5
            a1 = ((x3 - x2) * (cy - y2) - (y3 - y2) * (cx - x2)) / area
            a2 = ((x1 - x3) * (cy - y3) - (y1 - y3) * (cx - x3)) / area
            a3 = 1 - a1 - a2
            If a1 >= 0 And a2 >= 0 And a3 >= 0 Then
                dep = a1 * d1 + a2 * d2 + a3 * d3
                p = (h - 1 - y) * w + x
                If dep > zb(p) Then
                    zb(p) = dep
                    px(p) = c
                    gid(p) = grp
                End If
            End If
        Next x
    Next y
End Sub

Private Function Min3(ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    Min3 = a
    If b < Min3 Then Min3 = b
    If c < Min3 Then Min3 = c
End Function

Private Function Max3(ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    Max3 = a
    If b > Max3 Then Max3 = b
    If c > Max3 Then Max3 = c
End Function
