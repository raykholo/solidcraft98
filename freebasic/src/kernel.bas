' kernel.bas - turns the features into edges (the "geometry kernel").
' A line-for-line port of the Windows version's modKernel.

Const PI = 3.14159265358979
Const CIRCLE_SEGS = 32

Type TEdge
    X1 As Double
    Y1 As Double
    Z1 As Double
    X2 As Double
    Y2 As Double
    Z2 As Double
    Col As ULong
End Type

Const COL_SKETCH = &hFF0000C0          ' blue
Const COL_SKETCH_USED = &hFF80A0C0     ' faded, once a feature consumes it
Const COL_SOLID = &hFF000000           ' black
Const COL_HOLE = &hFF800000            ' dark red
Const COL_AXIS = &hFF808080

Declare Function RefOk(ByRef d As TDesign, ByVal i As Long) As Boolean
Declare Sub ExtrudeRange(ByRef d As TDesign, ByVal i As Long, ByRef z0 As Double, ByRef z1 As Double)

Sub AddEdge(e() As TEdge, ByRef n As Long, ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
            ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double, ByVal c As ULong)
    If n > UBound(e) Then ReDim Preserve e(0 To UBound(e) * 2 + 1)
    e(n).X1 = x1: e(n).Y1 = y1: e(n).Z1 = z1
    e(n).X2 = x2: e(n).Y2 = y2: e(n).Z2 = z2
    e(n).Col = c
    n += 1
End Sub

Sub AddCircle(e() As TEdge, ByRef n As Long, ByVal cx As Double, ByVal cy As Double, ByVal z As Double, _
              ByVal r As Double, ByVal c As ULong)
    Dim i As Long, a0 As Double, a1 As Double
    For i = 0 To CIRCLE_SEGS - 1
        a0 = 2 * PI * i / CIRCLE_SEGS
        a1 = 2 * PI * (i + 1) / CIRCLE_SEGS
        AddEdge e(), n, cx + r * Cos(a0), cy + r * Sin(a0), z, cx + r * Cos(a1), cy + r * Sin(a1), z, c
    Next i
End Sub

' Profile points of a sketch, counter-clockwise, in its own plane. Returns how
' many. seam(j) is True where a solid built on it should show a vertical edge.
Function ProfilePoints(ByRef f As TFeature, px() As Double, py() As Double, seam() As Boolean, _
                       ByVal nCircle As Long = CIRCLE_SEGS) As Long
    Dim As Long i, c, j, k, n
    Dim As Double r, cx, cy, a
    If f.Kind = FK_SKETCH_RECT Then
        r = f.P3
        If r <= 0 Then
            ReDim px(0 To 3): ReDim py(0 To 3): ReDim seam(0 To 3)
            px(0) = f.X: py(0) = f.Y
            px(1) = f.X + f.P1: py(1) = f.Y
            px(2) = f.X + f.P1: py(2) = f.Y + f.P2
            px(3) = f.X: py(3) = f.Y + f.P2
            For i = 0 To 3: seam(i) = True: Next i
            Return 4
        End If
        k = nCircle \ 4
        If k < 2 Then k = 2
        ReDim px(0 To 4 * (k + 1) - 1): ReDim py(0 To 4 * (k + 1) - 1): ReDim seam(0 To 4 * (k + 1) - 1)
        For c = 0 To 3
            Select Case c
            Case 0: cx = f.X + f.P1 - r: cy = f.Y + r
            Case 1: cx = f.X + f.P1 - r: cy = f.Y + f.P2 - r
            Case 2: cx = f.X + r: cy = f.Y + f.P2 - r
            Case 3: cx = f.X + r: cy = f.Y + r
            End Select
            For j = 0 To k
                a = (c * 90 - 90 + 90 * j / k) * PI / 180
                px(n) = cx + r * Cos(a): py(n) = cy + r * Sin(a)
                seam(n) = (j = 0 Or j = k)
                n += 1
            Next j
        Next c
        Return n
    Else
        ReDim px(0 To nCircle - 1): ReDim py(0 To nCircle - 1): ReDim seam(0 To nCircle - 1)
        For i = 0 To nCircle - 1
            px(i) = f.X + f.P1 * Cos(2 * PI * i / nCircle)
            py(i) = f.Y + f.P1 * Sin(2 * PI * i / nCircle)
            seam(i) = (i Mod 4) = 0
        Next i
        Return nCircle
    End If
End Function

' Is the circle (x, y, radius rr) wholly inside the sketch's outline?
Function ProfileContains(ByRef s As TFeature, ByVal x As Double, ByVal y As Double, ByVal rr As Double) As Boolean
    Dim As Double r, cx, cy
    Const EPS = 0.000001
    If s.Kind = FK_SKETCH_CIRCLE Then
        Return Sqr((x - s.X) ^ 2 + (y - s.Y) ^ 2) + rr <= s.P1 + EPS
    End If
    If x - rr < s.X - EPS Or x + rr > s.X + s.P1 + EPS Or y - rr < s.Y - EPS Or y + rr > s.Y + s.P2 + EPS Then Return False
    r = s.P3
    If r > 0 Then
        cx = x: cy = y
        If x < s.X + r Then cx = s.X + r
        If x > s.X + s.P1 - r Then cx = s.X + s.P1 - r
        If y < s.Y + r Then cy = s.Y + r
        If y > s.Y + s.P2 - r Then cy = s.Y + s.P2 - r
        If Sqr((x - cx) ^ 2 + (y - cy) ^ 2) + rr > r + EPS Then
            If (x < s.X + r Or x > s.X + s.P1 - r) And (y < s.Y + r Or y > s.Y + s.P2 - r) Then Return False
        End If
    End If
    Return True
End Function

' The height of sketch i. A sketch can sit on the top face of an extrude
' (its Ref); then Z is how far above that face it is, and it moves with it.
Function SketchZ(ByRef d As TDesign, ByVal i As Long) As Double
    Dim As Long r
    Dim As Double z0, z1, z = d.F(i).Z
    r = d.F(i).Ref
    If r >= 1 And r < i Then
        If d.F(r).Kind = FK_EXTRUDE Then
            ExtrudeRange d, r, z0, z1
            z += z1
        End If
    End If
    Return z
End Function

' The bottom and top of an extruded body.
Sub ExtrudeRange(ByRef d As TDesign, ByVal i As Long, ByRef z0 As Double, ByRef z1 As Double)
    z0 = SketchZ(d, d.F(i).Ref)
    z1 = z0 + d.F(i).P1
End Sub

' Where hole i starts and stops. "Through all" keeps going through every
' extruded body stacked underneath that the hole fits inside.
Sub HoleSpan(ByRef d As TDesign, ByVal i As Long, ByRef zTop As Double, ByRef zBot As Double)
    Dim As Long j
    Dim As Double b0, b1
    Dim As Boolean moved
    Const EPS = 0.000001
    ExtrudeRange d, d.F(i).Ref, zBot, zTop
    If d.F(i).P2 > 0 Then
        zBot = zTop - d.F(i).P2
        Exit Sub
    End If
    Do
        moved = False
        For j = 1 To i - 1
            If d.F(j).Kind = FK_EXTRUDE And d.F(j).Suppressed = 0 And j <> d.F(i).Ref Then
                If RefOk(d, j) Then
                    ExtrudeRange d, j, b0, b1
                    If b0 < zBot - EPS And b1 >= zBot - EPS And b1 <= zTop + EPS Then
                        If ProfileContains(d.F(d.F(j).Ref), d.F(i).X, d.F(i).Y, d.F(i).P1 / 2) Then
                            zBot = b0
                            moved = True
                        End If
                    End If
                End If
            End If
        Next j
    Loop While moved
End Sub

Function MaxAbs(v() As Double, ByVal n As Long) As Double
    Dim As Long i
    Dim As Double m
    For i = 0 To n - 1
        If Abs(v(i)) > m Then m = Abs(v(i))
    Next i
    Return m
End Function

' Turns the design into edges. Returns the edge count.
Function Regenerate(ByRef d As TDesign, e() As TEdge) As Long
    Dim As Long n, i, j, k, np, steps
    Dim As Double z0, z1, zt, r, a0, a1, sz
    Dim As Double px(Any), py(Any)
    Dim As Boolean seam(Any)
    ReDim e(0 To 255)
    Dim used(0 To MAX_FEATURES) As Boolean
    For i = 1 To d.Count
        Select Case d.F(i).Kind
        Case FK_EXTRUDE, FK_REVOLVE
            If d.F(i).Ref >= 1 And d.F(i).Ref <= d.Count Then used(d.F(i).Ref) = True
        End Select
    Next i

    For i = 1 To d.Count
        If d.F(i).Suppressed = 0 And RefOk(d, i) Then
            With d.F(i)
            Select Case .Kind
            Case FK_SKETCH_RECT
                sz = SketchZ(d, i)
                np = ProfilePoints(d.F(i), px(), py(), seam())
                For j = 0 To np - 1
                    k = (j + 1) Mod np
                    AddEdge e(), n, px(j), py(j), sz, px(k), py(k), sz, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)
                Next j
            Case FK_SKETCH_CIRCLE
                AddCircle e(), n, .X, .Y, SketchZ(d, i), .P1, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)

            Case FK_EXTRUDE
                ExtrudeRange d, i, z0, z1
                np = ProfilePoints(d.F(.Ref), px(), py(), seam())
                For j = 0 To np - 1
                    k = (j + 1) Mod np
                    AddEdge e(), n, px(j), py(j), z0, px(k), py(k), z0, COL_SOLID
                    AddEdge e(), n, px(j), py(j), z1, px(k), py(k), z1, COL_SOLID
                    If seam(j) Then AddEdge e(), n, px(j), py(j), z0, px(j), py(j), z1, COL_SOLID
                Next j

            Case FK_REVOLVE
                ' Spin the profile about the Y axis of its plane.
                Dim As Long sk = .Ref
                sz = SketchZ(d, sk)
                np = ProfilePoints(d.F(sk), px(), py(), seam())
                steps = Int(Abs(.P1) / 15 + 0.5)
                If steps < 1 Then steps = 1
                For k = 0 To steps
                    a0 = (.P1 * PI / 180) * k / steps
                    If k = 0 Or k = steps Or (k Mod 3) = 0 Then
                        For j = 0 To np - 1
                            AddEdge e(), n, px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                                px((j + 1) Mod np) * Cos(a0), py((j + 1) Mod np), sz - px((j + 1) Mod np) * Sin(a0), COL_SOLID
                        Next j
                    End If
                    If k < steps Then
                        a1 = (.P1 * PI / 180) * (k + 1) / steps
                        For j = 0 To np - 1
                            If seam(j) AndAlso (np <= 4 Or d.F(sk).Kind = FK_SKETCH_RECT Or (j Mod 8) = 0) Then
                                AddEdge e(), n, px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                                    px(j) * Cos(a1), py(j), sz - px(j) * Sin(a1), COL_SOLID
                            End If
                        Next j
                    End If
                Next k
                AddEdge e(), n, 0, -10, sz, 0, 10 + MaxAbs(py(), np), sz, COL_AXIS

            Case FK_HOLE
                HoleSpan d, i, zt, z0
                r = .P1 / 2
                AddCircle e(), n, .X, .Y, zt, r, COL_HOLE
                AddCircle e(), n, .X, .Y, z0, r, COL_HOLE
                For j = 0 To 3
                    a0 = j * PI / 2
                    AddEdge e(), n, .X + r * Cos(a0), .Y + r * Sin(a0), zt, .X + r * Cos(a0), .Y + r * Sin(a0), z0, COL_HOLE
                Next j
            End Select
            End With
        End If
    Next i
    Return n
End Function

' A feature is only drawn if what it is built on exists and comes before it.
Function RefOk(ByRef d As TDesign, ByVal i As Long) As Boolean
    With d.F(i)
        Select Case .Kind
        Case FK_SKETCH_RECT, FK_SKETCH_CIRCLE
            If .Ref = 0 Then Return True
            If .Ref >= 1 And .Ref < i Then
                If d.F(.Ref).Kind = FK_EXTRUDE Then Return RefOk(d, .Ref)
            End If
        Case FK_EXTRUDE, FK_REVOLVE
            If .Ref >= 1 And .Ref < i Then Return IsSketch(d.F(.Ref).Kind)
        Case FK_FOREIGN
            Return True          ' nothing to build, nothing to break
        Case FK_HOLE
            If .Ref >= 1 And .Ref < i Then
                If d.F(.Ref).Kind = FK_EXTRUDE Then
                    If RefOk(d, .Ref) Then
                        Return ProfileContains(d.F(d.F(.Ref).Ref), .X, .Y, .P1 / 2)
                    End If
                End If
            End If
        End Select
    End With
    Return False
End Function
