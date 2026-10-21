Attribute VB_Name = "modKernel"
' modKernel - the geometry kernel. Not B-rep: a bag of edges.
'
' Regenerate walks the feature list and turns it into 3D line segments,
' which the viewport projects and draws. Z is up, units are mm.
Option Explicit

Public Const PI As Double = 3.14159265358979
Private Const CIRCLE_SEGS As Integer = 32

Public Type TEdge
    X1 As Double
    Y1 As Double
    Z1 As Double
    X2 As Double
    Y2 As Double
    Z2 As Double
    Color As Long
End Type

Public Const COL_SKETCH As Long = &HC00000       ' blue (BGR)
Public Const COL_SKETCH_USED As Long = &HC0A080  ' faded, once a feature consumes it
Public Const COL_SOLID As Long = &H0&            ' black
Public Const COL_HOLE As Long = &H80&            ' dark red
Public Const COL_AXIS As Long = &H808080

' Adds one segment to the list, growing it as needed.
Private Sub AddEdge(e() As TEdge, n As Long, ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
                    ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double, ByVal c As Long)
    If n > UBound(e) Then ReDim Preserve e(0 To UBound(e) * 2 + 1)
    e(n).X1 = x1: e(n).Y1 = y1: e(n).Z1 = z1
    e(n).X2 = x2: e(n).Y2 = y2: e(n).Z2 = z2
    e(n).Color = c
    n = n + 1
End Sub

Private Sub AddCircle(e() As TEdge, n As Long, ByVal cx As Double, ByVal cy As Double, ByVal z As Double, _
                      ByVal r As Double, ByVal c As Long)
    Dim i As Integer, a0 As Double, a1 As Double
    For i = 0 To CIRCLE_SEGS - 1
        a0 = 2 * PI * i / CIRCLE_SEGS
        a1 = 2 * PI * (i + 1) / CIRCLE_SEGS
        AddEdge e, n, cx + r * Cos(a0), cy + r * Sin(a0), z, cx + r * Cos(a1), cy + r * Sin(a1), z, c
    Next i
End Sub

' Profile points of a sketch, counter-clockwise, in its own plane. Returns how
' many. seam(j) is True where a solid built on it should show a vertical edge:
' the corners of a rectangle, the ends of each rounded corner, every 4th
' point of a circle. nCircle is how many points a full circle gets.
Public Function ProfilePoints(f As TFeature, px() As Double, py() As Double, seam() As Boolean, _
                              Optional ByVal nCircle As Integer = CIRCLE_SEGS) As Integer
    Dim i As Integer, c As Integer, j As Integer, k As Integer, n As Integer
    Dim r As Double, cx As Double, cy As Double, a As Double
    If f.Kind = FK_SKETCH_RECT Then
        r = f.P3
        If r <= 0 Then
            ReDim px(0 To 3): ReDim py(0 To 3): ReDim seam(0 To 3)
            px(0) = f.X: py(0) = f.Y
            px(1) = f.X + f.P1: py(1) = f.Y
            px(2) = f.X + f.P1: py(2) = f.Y + f.P2
            px(3) = f.X: py(3) = f.Y + f.P2
            For i = 0 To 3: seam(i) = True: Next i
            ProfilePoints = 4
            Exit Function
        End If
        k = nCircle \ 4                ' segments per rounded corner
        If k < 2 Then k = 2
        ReDim px(0 To 4 * (k + 1) - 1): ReDim py(0 To 4 * (k + 1) - 1): ReDim seam(0 To 4 * (k + 1) - 1)
        For c = 0 To 3
            Select Case c                ' corner centres, going round anticlockwise
            Case 0: cx = f.X + f.P1 - r: cy = f.Y + r
            Case 1: cx = f.X + f.P1 - r: cy = f.Y + f.P2 - r
            Case 2: cx = f.X + r: cy = f.Y + f.P2 - r
            Case 3: cx = f.X + r: cy = f.Y + r
            End Select
            For j = 0 To k
                a = (c * 90 - 90 + 90 * j / k) * PI / 180
                px(n) = cx + r * Cos(a): py(n) = cy + r * Sin(a)
                seam(n) = (j = 0 Or j = k)
                n = n + 1
            Next j
        Next c
        ProfilePoints = n
    Else
        ReDim px(0 To nCircle - 1): ReDim py(0 To nCircle - 1): ReDim seam(0 To nCircle - 1)
        For i = 0 To nCircle - 1
            px(i) = f.X + f.P1 * Cos(2 * PI * i / nCircle)
            py(i) = f.Y + f.P1 * Sin(2 * PI * i / nCircle)
            seam(i) = (i Mod 4) = 0
        Next i
        ProfilePoints = nCircle
    End If
End Function

' Is the circle (x, y, radius rr) wholly inside the sketch's outline?
Public Function ProfileContains(s As TFeature, ByVal x As Double, ByVal y As Double, ByVal rr As Double) As Boolean
    Dim r As Double, cx As Double, cy As Double
    Const EPS As Double = 0.000001
    If s.Kind = FK_SKETCH_CIRCLE Then
        ProfileContains = Sqr((x - s.X) ^ 2 + (y - s.Y) ^ 2) + rr <= s.P1 + EPS
        Exit Function
    End If
    If x - rr < s.X - EPS Or x + rr > s.X + s.P1 + EPS Or y - rr < s.Y - EPS Or y + rr > s.Y + s.P2 + EPS Then Exit Function
    r = s.P3
    If r > 0 Then
        ' in a corner square, the circle must also be inside the rounded corner
        cx = x: cy = y
        If x < s.X + r Then cx = s.X + r
        If x > s.X + s.P1 - r Then cx = s.X + s.P1 - r
        If y < s.Y + r Then cy = s.Y + r
        If y > s.Y + s.P2 - r Then cy = s.Y + s.P2 - r
        If Sqr((x - cx) ^ 2 + (y - cy) ^ 2) + rr > r + EPS Then
            If (x < s.X + r Or x > s.X + s.P1 - r) And (y < s.Y + r Or y > s.Y + s.P2 - r) Then Exit Function
        End If
    End If
    ProfileContains = True
End Function

' The height of sketch i. A sketch can sit on the top face of an extrude
' (its Ref); then Z is how far above that face it is, and it moves with it.
Public Function SketchZ(d As TDesign, ByVal i As Integer) As Double
    Dim r As Integer, z0 As Double, z1 As Double
    SketchZ = d.Features(i).Z
    r = d.Features(i).Ref
    If r >= 1 And r < i Then
        If d.Features(r).Kind = FK_EXTRUDE Then
            ExtrudeRange d, r, z0, z1
            SketchZ = SketchZ + z1
        End If
    End If
End Function

' The bottom and top of an extruded body.
Public Sub ExtrudeRange(d As TDesign, ByVal i As Integer, z0 As Double, z1 As Double)
    z0 = SketchZ(d, d.Features(i).Ref)
    z1 = z0 + d.Features(i).P1
End Sub

' Where hole i starts and stops. It starts on the top face of the body it was
' put on. A blind hole goes down its depth; "through all" keeps going through
' every extruded body stacked underneath that the hole fits inside.
Public Sub HoleSpan(d As TDesign, ByVal i As Integer, zTop As Double, zBot As Double)
    Dim h As TFeature, j As Integer, b0 As Double, b1 As Double, moved As Boolean
    Const EPS As Double = 0.000001
    h = d.Features(i)
    ExtrudeRange d, h.Ref, zBot, zTop
    If h.P2 > 0 Then
        zBot = zTop - h.P2
        Exit Sub
    End If
    Do
        moved = False
        For j = 1 To i - 1
            If d.Features(j).Kind = FK_EXTRUDE And d.Features(j).Suppressed = 0 And j <> h.Ref Then
                If RefOk(d, j) Then
                    ExtrudeRange d, j, b0, b1
                    If b0 < zBot - EPS And b1 >= zBot - EPS And b1 <= zTop + EPS Then
                        If ProfileContains(d.Features(d.Features(j).Ref), h.X, h.Y, h.P1 / 2) Then
                            zBot = b0
                            moved = True
                        End If
                    End If
                End If
            End If
        Next j
    Loop While moved
End Sub

' Turns the design into edges. Returns the edge count.
Public Function Regenerate(d As TDesign, e() As TEdge) As Long
    Dim n As Long, i As Integer, j As Integer, k As Integer
    Dim f As TFeature, s As TFeature, b As TFeature
    Dim px() As Double, py() As Double, np As Integer, seam() As Boolean
    Dim z0 As Double, z1 As Double, zt As Double, r As Double
    Dim steps As Integer, a0 As Double, a1 As Double, sz As Double
    Dim used() As Boolean

    ReDim e(0 To 255)
    If d.Count > 0 Then ReDim used(1 To d.Count) Else ReDim used(0 To 0)
    For i = 1 To d.Count
        Select Case d.Features(i).Kind
        Case FK_EXTRUDE, FK_REVOLVE
            If d.Features(i).Ref >= 1 And d.Features(i).Ref <= d.Count Then used(d.Features(i).Ref) = True
        End Select
    Next i

    For i = 1 To d.Count
        f = d.Features(i)
        If f.Suppressed = 0 And RefOk(d, i) Then
            Select Case f.Kind
            Case FK_SKETCH_RECT
                sz = SketchZ(d, i)
                np = ProfilePoints(f, px, py, seam)
                For j = 0 To np - 1
                    k = (j + 1) Mod np
                    AddEdge e, n, px(j), py(j), sz, px(k), py(k), sz, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)
                Next j
            Case FK_SKETCH_CIRCLE
                AddCircle e, n, f.X, f.Y, SketchZ(d, i), f.P1, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)

            Case FK_EXTRUDE
                s = d.Features(f.Ref)
                ExtrudeRange d, i, z0, z1
                np = ProfilePoints(s, px, py, seam)
                For j = 0 To np - 1
                    k = (j + 1) Mod np
                    AddEdge e, n, px(j), py(j), z0, px(k), py(k), z0, COL_SOLID
                    AddEdge e, n, px(j), py(j), z1, px(k), py(k), z1, COL_SOLID
                    If seam(j) Then AddEdge e, n, px(j), py(j), z0, px(j), py(j), z1, COL_SOLID
                Next j

            Case FK_REVOLVE
                ' Spin the profile about the Y axis of its plane.
                s = d.Features(f.Ref)
                sz = SketchZ(d, f.Ref)
                np = ProfilePoints(s, px, py, seam)
                steps = Int(Abs(f.P1) / 15 + 0.5)
                If steps < 1 Then steps = 1
                For k = 0 To steps
                    a0 = (f.P1 * PI / 180) * k / steps
                    ' a copy of the profile every 45 degrees and at both ends
                    If k = 0 Or k = steps Or (k Mod 3) = 0 Then
                        For j = 0 To np - 1
                            AddEdge e, n, px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                                px((j + 1) Mod np) * Cos(a0), py((j + 1) Mod np), sz - px((j + 1) Mod np) * Sin(a0), COL_SOLID
                        Next j
                    End If
                    ' the path each profile corner traces
                    If k < steps Then
                        a1 = (f.P1 * PI / 180) * (k + 1) / steps
                        For j = 0 To np - 1
                            If seam(j) And (np <= 4 Or s.Kind = FK_SKETCH_RECT Or (j Mod 8) = 0) Then
                                AddEdge e, n, px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                                    px(j) * Cos(a1), py(j), sz - px(j) * Sin(a1), COL_SOLID
                            End If
                        Next j
                    End If
                Next k
                AddEdge e, n, 0, -10, sz, 0, 10 + MaxAbs(py, np), sz, COL_AXIS

            Case FK_HOLE
                HoleSpan d, i, zt, z0
                r = f.P1 / 2
                AddCircle e, n, f.X, f.Y, zt, r, COL_HOLE
                AddCircle e, n, f.X, f.Y, z0, r, COL_HOLE
                For j = 0 To 3
                    a0 = j * PI / 2
                    AddEdge e, n, f.X + r * Cos(a0), f.Y + r * Sin(a0), zt, f.X + r * Cos(a0), f.Y + r * Sin(a0), z0, COL_HOLE
                Next j
            End Select
        End If
    Next i
    Regenerate = n
End Function

' A feature is only drawn if what it is built on exists and comes before it.
Public Function RefOk(d As TDesign, ByVal i As Integer) As Boolean
    Dim f As TFeature
    f = d.Features(i)
    Select Case f.Kind
    Case FK_SKETCH_RECT, FK_SKETCH_CIRCLE
        If f.Ref = 0 Then
            RefOk = True
        ElseIf f.Ref >= 1 And f.Ref < i Then
            If d.Features(f.Ref).Kind = FK_EXTRUDE Then RefOk = RefOk(d, f.Ref)
        End If
    Case FK_EXTRUDE, FK_REVOLVE
        If f.Ref >= 1 And f.Ref < i Then RefOk = IsSketch(d.Features(f.Ref).Kind)
    Case FK_HOLE
        If f.Ref >= 1 And f.Ref < i Then
            If d.Features(f.Ref).Kind = FK_EXTRUDE Then
                If RefOk(d, f.Ref) Then
                    RefOk = ProfileContains(d.Features(d.Features(f.Ref).Ref), f.X, f.Y, f.P1 / 2)
                End If
            End If
        End If
    End Select
End Function

Private Function MaxAbs(v() As Double, ByVal n As Integer) As Double
    Dim i As Integer
    For i = 0 To n - 1
        If Abs(v(i)) > MaxAbs Then MaxAbs = Abs(v(i))
    Next i
End Function
