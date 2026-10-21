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

Private Sub AddRect(e() As TEdge, n As Long, ByVal x As Double, ByVal y As Double, ByVal z As Double, _
                    ByVal w As Double, ByVal h As Double, ByVal c As Long)
    AddEdge e, n, x, y, z, x + w, y, z, c
    AddEdge e, n, x + w, y, z, x + w, y + h, z, c
    AddEdge e, n, x + w, y + h, z, x, y + h, z, c
    AddEdge e, n, x, y + h, z, x, y, z, c
End Sub

' Profile points of a sketch, in its own plane. Returns how many.
Private Function ProfilePoints(f As TFeature, px() As Double, py() As Double) As Integer
    Dim i As Integer
    If f.Kind = FK_SKETCH_RECT Then
        ReDim px(0 To 3): ReDim py(0 To 3)
        px(0) = f.X: py(0) = f.Y
        px(1) = f.X + f.P1: py(1) = f.Y
        px(2) = f.X + f.P1: py(2) = f.Y + f.P2
        px(3) = f.X: py(3) = f.Y + f.P2
        ProfilePoints = 4
    Else
        ReDim px(0 To CIRCLE_SEGS - 1): ReDim py(0 To CIRCLE_SEGS - 1)
        For i = 0 To CIRCLE_SEGS - 1
            px(i) = f.X + f.P1 * Cos(2 * PI * i / CIRCLE_SEGS)
            py(i) = f.Y + f.P1 * Sin(2 * PI * i / CIRCLE_SEGS)
        Next i
        ProfilePoints = CIRCLE_SEGS
    End If
End Function

' Turns the design into edges. Returns the edge count.
Public Function Regenerate(d As TDesign, e() As TEdge) As Long
    Dim n As Long, i As Integer, j As Integer, k As Integer
    Dim f As TFeature, s As TFeature, b As TFeature
    Dim px() As Double, py() As Double, np As Integer
    Dim z0 As Double, z1 As Double, zt As Double, r As Double
    Dim steps As Integer, a0 As Double, a1 As Double
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
                AddRect e, n, f.X, f.Y, f.Z, f.P1, f.P2, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)
            Case FK_SKETCH_CIRCLE
                AddCircle e, n, f.X, f.Y, f.Z, f.P1, IIf(used(i), COL_SKETCH_USED, COL_SKETCH)

            Case FK_EXTRUDE
                s = d.Features(f.Ref)
                z0 = s.Z: z1 = s.Z + f.P1
                np = ProfilePoints(s, px, py)
                For j = 0 To np - 1
                    k = (j + 1) Mod np
                    AddEdge e, n, px(j), py(j), z0, px(k), py(k), z0, COL_SOLID
                    AddEdge e, n, px(j), py(j), z1, px(k), py(k), z1, COL_SOLID
                    ' every corner of a box, every 4th seam of a cylinder
                    If np = 4 Or (j Mod 4) = 0 Then AddEdge e, n, px(j), py(j), z0, px(j), py(j), z1, COL_SOLID
                Next j

            Case FK_REVOLVE
                ' Spin the profile about the Y axis of its plane.
                s = d.Features(f.Ref)
                np = ProfilePoints(s, px, py)
                steps = Int(Abs(f.P1) / 15 + 0.5)
                If steps < 1 Then steps = 1
                For k = 0 To steps
                    a0 = (f.P1 * PI / 180) * k / steps
                    ' a copy of the profile every 45 degrees and at both ends
                    If k = 0 Or k = steps Or (k Mod 3) = 0 Then
                        For j = 0 To np - 1
                            AddEdge e, n, px(j) * Cos(a0), py(j), s.Z - px(j) * Sin(a0), _
                                px((j + 1) Mod np) * Cos(a0), py((j + 1) Mod np), s.Z - px((j + 1) Mod np) * Sin(a0), COL_SOLID
                        Next j
                    End If
                    ' the path each profile corner traces
                    If k < steps Then
                        a1 = (f.P1 * PI / 180) * (k + 1) / steps
                        For j = 0 To np - 1
                            If np = 4 Or (j Mod 8) = 0 Then
                                AddEdge e, n, px(j) * Cos(a0), py(j), s.Z - px(j) * Sin(a0), _
                                    px(j) * Cos(a1), py(j), s.Z - px(j) * Sin(a1), COL_SOLID
                            End If
                        Next j
                    End If
                Next k
                AddEdge e, n, 0, -10, s.Z, 0, 10 + MaxAbs(py, np), s.Z, COL_AXIS

            Case FK_HOLE
                b = d.Features(f.Ref)
                s = d.Features(b.Ref)
                zt = s.Z + b.P1
                r = f.P1 / 2
                If f.P2 <= 0 Or f.P2 > b.P1 Then z0 = s.Z Else z0 = zt - f.P2
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
        RefOk = True
    Case FK_EXTRUDE, FK_REVOLVE
        If f.Ref >= 1 And f.Ref < i Then RefOk = IsSketch(d.Features(f.Ref).Kind)
    Case FK_HOLE
        If f.Ref >= 1 And f.Ref < i Then
            If d.Features(f.Ref).Kind = FK_EXTRUDE Then RefOk = RefOk(d, f.Ref)
        End If
    End Select
End Function

Private Function MaxAbs(v() As Double, ByVal n As Integer) As Double
    Dim i As Integer
    For i = 0 To n - 1
        If Abs(v(i)) > MaxAbs Then MaxAbs = Abs(v(i))
    Next i
End Function
