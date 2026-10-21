Attribute VB_Name = "modMesh"
' modMesh - turns the part into triangles: for Export for Rapid Prototyping
' (.stl) and for the shaded view.
'
' What comes out is closed and faces outward. An extrude's top and bottom are
' its outline with loops cut out of it: the holes, and the footprint of any
' body standing on it. Each loop is joined to the outline by a slit so the cap
' becomes one polygon, which is cut into triangles by clipping off "ears" one
' at a time. A body standing wholly on another's top face is joined to it (no
' top under it, no bottom on it), so a boss and its plate are one solid. A
' revolve is rings of its profile with quads between them, and end caps if it
' doesn't go all the way round.
Option Explicit

Public Type TTri
    X1 As Double
    Y1 As Double
    Z1 As Double
    X2 As Double
    Y2 As Double
    Z2 As Double
    X3 As Double
    Y3 As Double
    Z3 As Double
    Body As Integer          ' the feature that made it (a hole's walls are the hole's)
End Type

Public Const MESH_SEGS As Integer = 64

Private Type THole
    X As Double
    Y As Double
    R As Double
    ZTop As Double
    ZBot As Double
    Feat As Integer          ' the hole feature
End Type

Private Const EPS As Double = 0.000001

Private mT() As TTri
Private mN As Long
Private mErr As String
Private mSegs As Integer
Private mJoin() As Integer     ' mJoin(j) = the extrude that extrude j stands on and is joined to, or 0

' the loops to cut out of the cap being made, all anticlockwise
Private mLX() As Double
Private mLY() As Double
Private mLS() As Long          ' where each loop starts in mLX/mLY
Private mLN() As Long          ' and how many points it has
Private mNL As Integer

' Fills t() with the part's triangles and returns how many. sErr says which
' bodies couldn't be meshed, if any (they're left out).
Public Function MeshDesign(d As TDesign, t() As TTri, Optional ByVal nSegs As Integer = MESH_SEGS, _
                           Optional sErr As String) As Long
    Dim i As Integer, first As Long
    ReDim mT(0 To 1023)
    mN = 0
    mErr = ""
    mSegs = nSegs
    FindJoins d
    For i = 1 To d.Count
        If d.Features(i).Suppressed = 0 And RefOk(d, i) Then
            Select Case d.Features(i).Kind
            Case FK_EXTRUDE
                MeshExtrude d, i
            Case FK_REVOLVE
                first = mN
                MeshRevolve d, i, nSegs
                If mN > first Then OrientOutward first, mN
            End Select
        End If
    Next i
    t = mT
    MeshDesign = mN
    sErr = mErr
End Function

Private Sub AddTri(ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
                   ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double, _
                   ByVal x3 As Double, ByVal y3 As Double, ByVal z3 As Double, ByVal body As Integer)
    ' a corner on the axis of a revolve makes slivers with two corners the
    ' same; they have no area, and leaving them out keeps the mesh closed
    If x1 = x2 And y1 = y2 And z1 = z2 Then Exit Sub
    If x2 = x3 And y2 = y3 And z2 = z3 Then Exit Sub
    If x3 = x1 And y3 = y1 And z3 = z1 Then Exit Sub
    If mN > UBound(mT) Then ReDim Preserve mT(0 To UBound(mT) * 2 + 1)
    With mT(mN)
        .X1 = x1: .Y1 = y1: .Z1 = z1
        .X2 = x2: .Y2 = y2: .Z2 = z2
        .X3 = x3: .Y3 = y3: .Z3 = z3
        .Body = body
    End With
    mN = mN + 1
End Sub

' A revolve's triangles all face out if the volume they enclose is positive;
' if it came out negative, the winding is backwards: turn every one over.
' (Extrudes are built facing out.)
Private Sub OrientOutward(ByVal a As Long, ByVal b As Long)
    Dim i As Long, v As Double, t As Double
    For i = a To b - 1
        With mT(i)
            v = v + (.X1 * (.Y2 * .Z3 - .Y3 * .Z2) - .X2 * (.Y1 * .Z3 - .Y3 * .Z1) + .X3 * (.Y1 * .Z2 - .Y2 * .Z1))
        End With
    Next i
    If v >= 0 Then Exit Sub
    For i = a To b - 1
        With mT(i)
            t = .X2: .X2 = .X3: .X3 = t
            t = .Y2: .Y2 = .Y3: .Y3 = t
            t = .Z2: .Z2 = .Z3: .Z3 = t
        End With
    Next i
End Sub

' ---- extrudes ----

' Bottom and top of extrude i, bottom first, and its outline, anticlockwise.
' False if it is flat or has no outline.
Private Function GetBody(d As TDesign, ByVal i As Integer, z0 As Double, z1 As Double, _
                      ox() As Double, oy() As Double, no As Long) As Boolean
    Dim seam() As Boolean, t As Double
    ExtrudeRange d, i, z0, z1
    If z1 < z0 Then t = z0: z0 = z1: z1 = t
    If z1 - z0 < EPS Then Exit Function
    no = ProfilePoints(d.Features(d.Features(i).Ref), ox, oy, seam, mSegs)
    no = CleanOutline(ox, oy, no)
    GetBody = (no >= 3)
End Function

Private Function IsBody(d As TDesign, ByVal i As Integer) As Boolean
    If d.Features(i).Kind = FK_EXTRUDE And d.Features(i).Suppressed = 0 Then IsBody = RefOk(d, i)
End Function

' The holes that come into extrude i through its top: those that start at or
' above its top, inside its outline, and get down to its top or further.
Private Function CollectHoles(d As TDesign, ByVal i As Integer, ByVal z1 As Double, h() As THole) As Integer
    Dim j As Integer, n As Integer, zt As Double, zb As Double, r As Double, s As TFeature
    ReDim h(0 To 7)
    s = d.Features(d.Features(i).Ref)
    For j = i + 1 To d.Count
        If d.Features(j).Kind = FK_HOLE And d.Features(j).Suppressed = 0 Then
            If RefOk(d, j) Then
                r = d.Features(j).P1 / 2
                If ProfileContains(s, d.Features(j).X, d.Features(j).Y, r) Then
                    HoleSpan d, j, zt, zb
                    If zt >= z1 - EPS And zb <= z1 + EPS Then
                        If n > UBound(h) Then ReDim Preserve h(0 To n * 2)
                        h(n).X = d.Features(j).X: h(n).Y = d.Features(j).Y: h(n).R = r
                        h(n).ZTop = zt: h(n).ZBot = zb: h(n).Feat = j
                        n = n + 1
                    End If
                End If
            End If
        End If
    Next j
    CollectHoles = n
End Function

' Which extrudes stand wholly on another one's top face, clear of its holes
' and of each other, and so can be joined to it.
Private Sub FindJoins(d As TDesign)
    Dim i As Integer, j As Integer, k As Integer, ok As Boolean
    Dim az0 As Double, az1 As Double, bz0 As Double, bz1 As Double, cz0 As Double, cz1 As Double
    Dim ax() As Double, ay() As Double, na As Long, bx() As Double, by() As Double, nb As Long
    Dim cx() As Double, cy() As Double, nc As Long, h() As THole, nh As Integer
    Dim hx() As Double, hy() As Double
    If d.Count > 0 Then ReDim mJoin(1 To d.Count) Else ReDim mJoin(0 To 0)
    For j = 1 To d.Count
        If IsBody(d, j) Then
            If GetBody(d, j, bz0, bz1, bx, by, nb) Then
                For i = 1 To d.Count
                    If i <> j And IsBody(d, i) Then
                        If GetBody(d, i, az0, az1, ax, ay, na) Then
                            If Abs(az1 - bz0) < EPS Then
                                ok = (Relation(ax, ay, na, bx, by, nb) = 1)
                                If ok Then
                                    nh = CollectHoles(d, i, az1, h)
                                    For k = 0 To nh - 1
                                        CircleLoop h(k).X, h(k).Y, h(k).R, hx, hy
                                        If Relation(bx, by, nb, hx, hy, mSegs) = -1 Then ok = False: Exit For
                                    Next k
                                End If
                                If ok Then
                                    For k = 1 To j - 1
                                        If mJoin(k) = i Then
                                            GetBody d, k, cz0, cz1, cx, cy, nc
                                            If Relation(cx, cy, nc, bx, by, nb) <> 0 Then ok = False: Exit For
                                        End If
                                    Next k
                                End If
                                If ok Then
                                    mJoin(j) = i
                                    Exit For
                                End If
                            End If
                        End If
                    End If
                Next i
            End If
        End If
    Next j
End Sub

Private Sub MeshExtrude(d As TDesign, ByVal i As Integer)
    Dim z0 As Double, z1 As Double, ox() As Double, oy() As Double, no As Long
    Dim h() As THole, nh As Integer, inFoot() As Boolean, j As Integer, k As Long, k2 As Long
    Dim fx() As Double, fy() As Double, nf As Long, fz0 As Double, fz1 As Double
    Dim hx() As Double, hy() As Double, zb As Double

    If Not GetBody(d, i, z0, z1, ox, oy, no) Then Exit Sub
    nh = CollectHoles(d, i, z1, h)
    ReDim inFoot(0 To nh)

    ' the top: the outline less the holes and the bodies standing on it
    ClearLoops
    For j = 1 To d.Count
        If mJoin(j) = i Then
            GetBody d, j, fz0, fz1, fx, fy, nf
            AddLoop fx, fy, nf
            For k = 0 To nh - 1
                CircleLoop h(k).X, h(k).Y, h(k).R, hx, hy
                If Relation(fx, fy, nf, hx, hy, mSegs) = 1 Then inFoot(k) = True
            Next k
        End If
    Next j
    For k = 0 To nh - 1
        If Not inFoot(k) And h(k).ZBot < z1 - EPS Then AddCircleLoop h(k).X, h(k).Y, h(k).R
    Next k
    If Not CapLoops(ox, oy, no, z1, True, i) Then
        mErr = mErr & FeatureName(d, i) & " (its holes are too close together to cap). "
        Exit Sub
    End If

    ' the bottom, unless it stands on (and is joined to) another body
    If mJoin(i) = 0 Then
        ClearLoops
        For k = 0 To nh - 1
            If h(k).ZBot <= z0 + EPS Then AddCircleLoop h(k).X, h(k).Y, h(k).R
        Next k
        CapLoops ox, oy, no, z0, False, i
    End If

    ' the outside walls
    For k = 0 To no - 1
        k2 = (k + 1) Mod no
        AddTri ox(k), oy(k), z0, ox(k2), oy(k2), z0, ox(k2), oy(k2), z1, i
        AddTri ox(k), oy(k), z0, ox(k2), oy(k2), z1, ox(k), oy(k), z1, i
    Next k

    ' the holes: walls facing into them, floors where they stop, and a roof
    ' where one starts on this top under a body that stands on it
    For k = 0 To nh - 1
        zb = h(k).ZBot
        If zb < z0 Then zb = z0
        If zb < z1 - EPS Then
            HoleWall h(k).X, h(k).Y, h(k).R, zb, z1, h(k).Feat
            If zb > z0 + EPS Then HoleDisc h(k).X, h(k).Y, h(k).R, zb, True, h(k).Feat
            If inFoot(k) And h(k).ZTop <= z1 + EPS Then HoleDisc h(k).X, h(k).Y, h(k).R, z1, False, h(k).Feat
        ElseIf inFoot(k) Then
            HoleDisc h(k).X, h(k).Y, h(k).R, z1, True, h(k).Feat       ' a hole above that stops right here
        End If
    Next k
End Sub

' Drops repeated points (a rounded corner as big as the side makes two) and
' turns a clockwise outline round. Returns the new count.
Private Function CleanOutline(ox() As Double, oy() As Double, ByVal n As Long) As Long
    Dim i As Long, m As Long, a As Double, t As Double
    For i = 0 To n - 1
        If m = 0 Then
            ox(m) = ox(i): oy(m) = oy(i): m = m + 1
        ElseIf Abs(ox(i) - ox(m - 1)) > 0.000000001 Or Abs(oy(i) - oy(m - 1)) > 0.000000001 Then
            ox(m) = ox(i): oy(m) = oy(i): m = m + 1
        End If
    Next i
    Do While m > 1
        If Abs(ox(m - 1) - ox(0)) > 0.000000001 Or Abs(oy(m - 1) - oy(0)) > 0.000000001 Then Exit Do
        m = m - 1
    Loop
    For i = 0 To m - 1
        a = a + ox(i) * oy((i + 1) Mod m) - ox((i + 1) Mod m) * oy(i)
    Next i
    If a < 0 Then
        For i = 0 To m \ 2 - 1
            t = ox(i): ox(i) = ox(m - 1 - i): ox(m - 1 - i) = t
            t = oy(i): oy(i) = oy(m - 1 - i): oy(m - 1 - i) = t
        Next i
    End If
    CleanOutline = m
End Function

' A hole's edge, anticlockwise, starting at its right-most point. Every
' hole edge in the mesh comes from here, so neighbouring triangles meet exactly.
Private Sub CircleLoop(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, px() As Double, py() As Double)
    Dim k As Long
    ReDim px(0 To mSegs - 1): ReDim py(0 To mSegs - 1)
    For k = 0 To mSegs - 1
        px(k) = cx + r * Cos(2 * PI * k / mSegs)
        py(k) = cy + r * Sin(2 * PI * k / mSegs)
    Next k
End Sub

Private Sub HoleWall(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, ByVal za As Double, ByVal zb As Double, ByVal body As Integer)
    Dim k As Long, k2 As Long, px() As Double, py() As Double
    CircleLoop cx, cy, r, px, py
    For k = 0 To mSegs - 1
        k2 = (k + 1) Mod mSegs
        ' wound the other way from an outside wall, so it faces into the hole
        AddTri px(k2), py(k2), za, px(k), py(k), za, px(k), py(k), zb, body
        AddTri px(k2), py(k2), za, px(k), py(k), zb, px(k2), py(k2), zb, body
    Next k
End Sub

' The floor of a hole (facing up) or its roof (facing down).
Private Sub HoleDisc(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, ByVal z As Double, ByVal bUp As Boolean, ByVal body As Integer)
    Dim k As Long, k2 As Long, px() As Double, py() As Double
    CircleLoop cx, cy, r, px, py
    For k = 0 To mSegs - 1
        k2 = (k + 1) Mod mSegs
        If bUp Then
            AddTri cx, cy, z, px(k), py(k), z, px(k2), py(k2), z, body
        Else
            AddTri cx, cy, z, px(k2), py(k2), z, px(k), py(k), z, body
        End If
    Next k
End Sub

' ---- loops and caps ----

Private Sub ClearLoops()
    ReDim mLX(0 To 255): ReDim mLY(0 To 255)
    ReDim mLS(0 To 7): ReDim mLN(0 To 7)
    mNL = 0
End Sub

Private Sub AddLoop(px() As Double, py() As Double, ByVal n As Long)
    Dim k As Long, at As Long
    If mNL > UBound(mLS) Then ReDim Preserve mLS(0 To mNL * 2): ReDim Preserve mLN(0 To mNL * 2)
    If mNL = 0 Then at = 0 Else at = mLS(mNL - 1) + mLN(mNL - 1)
    Do While at + n > UBound(mLX) + 1
        ReDim Preserve mLX(0 To UBound(mLX) * 2 + 1): ReDim Preserve mLY(0 To UBound(mLY) * 2 + 1)
    Loop
    For k = 0 To n - 1
        mLX(at + k) = px(k): mLY(at + k) = py(k)
    Next k
    mLS(mNL) = at: mLN(mNL) = n
    mNL = mNL + 1
End Sub

Private Sub AddCircleLoop(ByVal cx As Double, ByVal cy As Double, ByVal r As Double)
    Dim px() As Double, py() As Double
    CircleLoop cx, cy, r, px, py
    AddLoop px, py, mSegs
End Sub

' A flat cap at height z: the outline (anticlockwise) less the loops.
' bUp: facing up (a top) or down (a bottom). False if it couldn't be cut up.
Private Function CapLoops(ox() As Double, oy() As Double, ByVal no As Long, _
                          ByVal z As Double, ByVal bUp As Boolean, ByVal body As Integer) As Boolean
    Dim px() As Double, py() As Double, np As Long, tri() As Long, nt As Long, k As Long
    If Not BridgeLoops(ox, oy, no, px, py, np) Then Exit Function
    If Not EarClip(px, py, np, tri, nt) Then Exit Function
    For k = 0 To nt - 1
        If bUp Then
            AddTri px(tri(3 * k)), py(tri(3 * k)), z, px(tri(3 * k + 1)), py(tri(3 * k + 1)), z, px(tri(3 * k + 2)), py(tri(3 * k + 2)), z, body
        Else
            AddTri px(tri(3 * k)), py(tri(3 * k)), z, px(tri(3 * k + 2)), py(tri(3 * k + 2)), z, px(tri(3 * k + 1)), py(tri(3 * k + 1)), z, body
        End If
    Next k
    CapLoops = True
End Function

' Joins each loop (turned clockwise) into the outline with a slit, from the
' loop's right-most point to the nearest outline point it can see. The loop
' reaching furthest right goes first, so later slits can't be boxed in.
Private Function BridgeLoops(ox() As Double, oy() As Double, ByVal no As Long, _
                             px() As Double, py() As Double, np As Long) As Boolean
    Dim i As Long, j As Integer, L As Integer, done() As Boolean, pick As Integer, best As Double
    Dim cx() As Double, cy() As Double, nc As Long, k As Long, m As Long, s As Long, tried() As Boolean
    Dim mx As Double, my As Double, bestK As Long, dd As Double, ok As Boolean, attempt As Long
    Dim nx() As Double, ny() As Double, nn As Long
    ReDim px(0 To no - 1): ReDim py(0 To no - 1)
    For i = 0 To no - 1
        px(i) = ox(i): py(i) = oy(i)
    Next i
    np = no
    If mNL = 0 Then BridgeLoops = True: Exit Function
    ReDim done(0 To mNL - 1)
    For j = 1 To mNL
        best = -1E+30: pick = -1
        For L = 0 To mNL - 1
            If Not done(L) Then
                For k = mLS(L) To mLS(L) + mLN(L) - 1
                    If mLX(k) > best Then best = mLX(k): pick = L: s = k
                Next k
            End If
        Next L
        done(pick) = True
        ' the loop, clockwise, from its right-most point
        nc = mLN(pick)
        ReDim cx(0 To nc - 1): ReDim cy(0 To nc - 1)
        For k = 0 To nc - 1
            i = mLS(pick) + ((s - mLS(pick)) - k + nc) Mod nc
            cx(k) = mLX(i): cy(k) = mLY(i)
        Next k
        mx = cx(0): my = cy(0)
        ' the nearest outline point whose slit crosses nothing
        ReDim tried(0 To np - 1)
        ok = False
        For attempt = 1 To np
            best = 1E+30: bestK = -1
            For k = 0 To np - 1
                If Not tried(k) Then
                    dd = (px(k) - mx) ^ 2 + (py(k) - my) ^ 2
                    If dd < best Then best = dd: bestK = k
                End If
            Next k
            If bestK < 0 Then Exit For
            tried(bestK) = True
            If SlitIsClear(mx, my, px(bestK), py(bestK), px, py, np, cx, cy, nc, done) Then
                ok = True
                Exit For
            End If
        Next attempt
        If Not ok Then Exit Function
        ' splice: ... p, m, loop ..., m, p ...
        nn = np + nc + 2
        ReDim nx(0 To nn - 1): ReDim ny(0 To nn - 1)
        m = 0
        For k = 0 To bestK
            nx(m) = px(k): ny(m) = py(k): m = m + 1
        Next k
        For k = 0 To nc - 1
            nx(m) = cx(k): ny(m) = cy(k): m = m + 1
        Next k
        nx(m) = cx(0): ny(m) = cy(0): m = m + 1
        For k = bestK To np - 1
            nx(m) = px(k): ny(m) = py(k): m = m + 1
        Next k
        px = nx: py = ny: np = nn
    Next j
    BridgeLoops = True
End Function

' Does the slit (ax,ay)-(bx,by) stay clear of the polygon so far, the loop it
' comes from, and the loops still to come?
Private Function SlitIsClear(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, _
        px() As Double, py() As Double, ByVal np As Long, cx() As Double, cy() As Double, ByVal nc As Long, _
        done() As Boolean) As Boolean
    Dim k As Long, L As Integer, a As Long, b As Long
    For k = 0 To np - 1
        If Crosses(ax, ay, bx, by, px(k), py(k), px((k + 1) Mod np), py((k + 1) Mod np)) Then Exit Function
    Next k
    For k = 0 To nc - 1
        If Crosses(ax, ay, bx, by, cx(k), cy(k), cx((k + 1) Mod nc), cy((k + 1) Mod nc)) Then Exit Function
    Next k
    For L = 0 To mNL - 1
        If Not done(L) Then
            For k = 0 To mLN(L) - 1
                a = mLS(L) + k: b = mLS(L) + (k + 1) Mod mLN(L)
                If Crosses(ax, ay, bx, by, mLX(a), mLY(a), mLX(b), mLY(b)) Then Exit Function
            Next k
        End If
    Next L
    SlitIsClear = True
End Function

' Do segments ab and cd cross? Touching at a shared end doesn't count.
Private Function Crosses(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, _
                         ByVal cx As Double, ByVal cy As Double, ByVal dx As Double, ByVal dy As Double) As Boolean
    Dim d1 As Double, d2 As Double, d3 As Double, d4 As Double
    If (ax = cx And ay = cy) Or (ax = dx And ay = dy) Or (bx = cx And by = cy) Or (bx = dx And by = dy) Then Exit Function
    d1 = Orient(cx, cy, dx, dy, ax, ay)
    d2 = Orient(cx, cy, dx, dy, bx, by)
    d3 = Orient(ax, ay, bx, by, cx, cy)
    d4 = Orient(ax, ay, bx, by, dx, dy)
    Crosses = ((d1 > 0) <> (d2 > 0)) And ((d3 > 0) <> (d4 > 0))
End Function

Private Function Orient(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, ByVal cx As Double, ByVal cy As Double) As Double
    Orient = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
End Function

' Two convex anticlockwise outlines: 1 if B is wholly inside A, 0 if they
' don't meet at all, -1 if they overlap or touch.
Private Function Relation(ax() As Double, ay() As Double, ByVal na As Long, _
                          bx() As Double, by() As Double, ByVal nb As Long) As Integer
    Dim k As Long, j As Long, allIn As Boolean, anyIn As Boolean
    allIn = True
    For k = 0 To nb - 1
        Select Case Inside(ax, ay, na, bx(k), by(k))
        Case 1: anyIn = True
        Case 0: anyIn = True: allIn = False
        Case Else: allIn = False
        End Select
    Next k
    If allIn Then Relation = 1: Exit Function
    Relation = -1
    If anyIn Then Exit Function
    For k = 0 To na - 1
        If Inside(bx, by, nb, ax(k), ay(k)) >= 0 Then Exit Function
    Next k
    For k = 0 To na - 1
        For j = 0 To nb - 1
            If Crosses(ax(k), ay(k), ax((k + 1) Mod na), ay((k + 1) Mod na), bx(j), by(j), bx((j + 1) Mod nb), by((j + 1) Mod nb)) Then Exit Function
        Next j
    Next k
    Relation = 0
End Function

' Is (x, y) inside a convex anticlockwise outline? 1 inside, 0 on its edge, -1 outside.
Private Function Inside(px() As Double, py() As Double, ByVal n As Long, ByVal x As Double, ByVal y As Double) As Integer
    Dim k As Long, o As Double, onEdge As Boolean
    Const TOL As Double = 0.0000001
    For k = 0 To n - 1
        o = Orient(px(k), py(k), px((k + 1) Mod n), py((k + 1) Mod n), x, y)
        If o < -TOL Then Inside = -1: Exit Function
        If o <= TOL Then onEdge = True
    Next k
    If onEdge Then Inside = 0 Else Inside = 1
End Function

' Cuts an anticlockwise polygon (which may touch itself along slits) into
' triangles. tri() gets 3 point indices per triangle.
Private Function EarClip(px() As Double, py() As Double, ByVal n As Long, tri() As Long, nt As Long) As Boolean
    Dim nxt() As Long, prv() As Long, i As Long, a As Long, b As Long, c As Long, nLeft As Long
    Dim p As Long, isEar As Boolean, guard As Long, found As Boolean
    ReDim nxt(0 To n - 1): ReDim prv(0 To n - 1)
    ReDim tri(0 To 3 * n)
    For i = 0 To n - 1
        nxt(i) = (i + 1) Mod n
        prv(i) = (i + n - 1) Mod n
    Next i
    nLeft = n
    b = 0
    nt = 0
    Do While nLeft > 3
        found = False
        For guard = 1 To nLeft
            a = prv(b): c = nxt(b)
            If Orient(px(a), py(a), px(b), py(b), px(c), py(c)) > 0.000000001 Then
                ' an ear if no other corner pokes into the triangle (every
                ' corner, since the slits make the polygon touch itself)
                isEar = True
                p = nxt(c)
                Do While p <> a
                    If Not (SamePt(px, py, p, a) Or SamePt(px, py, p, b) Or SamePt(px, py, p, c)) Then
                        If Orient(px(a), py(a), px(b), py(b), px(p), py(p)) >= 0 And _
                           Orient(px(b), py(b), px(c), py(c), px(p), py(p)) >= 0 And _
                           Orient(px(c), py(c), px(a), py(a), px(p), py(p)) >= 0 Then
                            isEar = False
                            Exit Do
                        End If
                    End If
                    p = nxt(p)
                Loop
                If isEar Then
                    tri(3 * nt) = a: tri(3 * nt + 1) = b: tri(3 * nt + 2) = c
                    nt = nt + 1
                    nxt(a) = c: prv(c) = a
                    nLeft = nLeft - 1
                    b = c
                    found = True
                    Exit For
                End If
            End If
            b = nxt(b)
        Next guard
        If Not found Then Exit Function
    Loop
    a = prv(b): c = nxt(b)
    tri(3 * nt) = a: tri(3 * nt + 1) = b: tri(3 * nt + 2) = c
    nt = nt + 1
    EarClip = True
End Function

Private Function SamePt(px() As Double, py() As Double, ByVal i As Long, ByVal j As Long) As Boolean
    SamePt = (px(i) = px(j) And py(i) = py(j))
End Function

' ---- revolves ----

Private Sub MeshRevolve(d As TDesign, ByVal i As Integer, ByVal nSegs As Integer)
    Dim s As TFeature, sz As Double, px() As Double, py() As Double, seam() As Boolean, np As Long
    Dim ang As Double, steps As Long, full As Boolean, k As Long, j As Long, j2 As Long
    Dim a0 As Double, a1 As Double
    s = d.Features(d.Features(i).Ref)
    sz = SketchZ(d, d.Features(i).Ref)
    np = ProfilePoints(s, px, py, seam, nSegs)
    np = CleanOutline(px, py, np)
    If np < 3 Or Abs(d.Features(i).P1) < 0.000001 Then Exit Sub
    ang = d.Features(i).P1 * PI / 180
    full = Abs(Abs(d.Features(i).P1) - 360) < 0.000001
    steps = Int(Abs(d.Features(i).P1) / 360 * nSegs + 0.5)
    If steps < 2 Then steps = 2
    For k = 0 To steps - 1
        a0 = ang * k / steps
        If full And k + 1 = steps Then a1 = 0 Else a1 = ang * (k + 1) / steps
        For j = 0 To np - 1
            j2 = (j + 1) Mod np
            AddTri px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                   px(j2) * Cos(a0), py(j2), sz - px(j2) * Sin(a0), _
                   px(j2) * Cos(a1), py(j2), sz - px(j2) * Sin(a1), i
            AddTri px(j) * Cos(a0), py(j), sz - px(j) * Sin(a0), _
                   px(j2) * Cos(a1), py(j2), sz - px(j2) * Sin(a1), _
                   px(j) * Cos(a1), py(j), sz - px(j) * Sin(a1), i
        Next j
    Next k
    If Not full Then
        ' the two ends: the profile itself, which is convex, as a fan
        For j = 1 To np - 2
            AddTri px(0), py(0), sz, px(j + 1), py(j + 1), sz, px(j), py(j), sz, i
            AddTri px(0) * Cos(ang), py(0), sz - px(0) * Sin(ang), _
                   px(j) * Cos(ang), py(j), sz - px(j) * Sin(ang), _
                   px(j + 1) * Cos(ang), py(j + 1), sz - px(j + 1) * Sin(ang), i
        Next j
    End If
End Sub
