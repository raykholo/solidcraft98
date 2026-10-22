' mesh.bas - turns the part into triangles: for Export for Rapid
' Prototyping (.stl) and for the shaded view. A port of the Windows
' version's modMesh: closed, outward-facing; holes cut through; a body
' standing wholly on another's top face is joined to it.

Type TTri
    X1 As Double
    Y1 As Double
    Z1 As Double
    X2 As Double
    Y2 As Double
    Z2 As Double
    X3 As Double
    Y3 As Double
    Z3 As Double
    Body As Long             ' the feature that made it (a hole's walls are the hole's)
End Type

Const MESH_SEGS = 64

Type THole
    X As Double
    Y As Double
    R As Double
    ZTop As Double
    ZBot As Double
    Feat As Long
End Type

Const MEPS = 0.000001

Dim Shared mT() As TTri
Dim Shared mN As Long
Dim Shared mErr As String
Dim Shared mSegs As Long
Dim Shared mJoin() As Long
Dim Shared mLX() As Double, mLY() As Double
Dim Shared mLS() As Long, mLN() As Long
Dim Shared mNL As Long

Sub CopyArr(dst() As Double, src() As Double, ByVal n As Long)
    Dim i As Long
    ReDim dst(0 To IIf(n > 0, n - 1, 0))
    For i = 0 To n - 1: dst(i) = src(i): Next
End Sub

Sub AddTri(ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
           ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double, _
           ByVal x3 As Double, ByVal y3 As Double, ByVal z3 As Double, ByVal body As Long)
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
    mN += 1
End Sub

' A revolve's triangles all face out if the volume they enclose is positive.
Sub OrientOutward(ByVal a As Long, ByVal b As Long)
    Dim i As Long, v As Double, t As Double
    For i = a To b - 1
        With mT(i)
            v += (.X1 * (.Y2 * .Z3 - .Y3 * .Z2) - .X2 * (.Y1 * .Z3 - .Y3 * .Z1) + .X3 * (.Y1 * .Z2 - .Y2 * .Z1))
        End With
    Next i
    If v >= 0 Then Exit Sub
    For i = a To b - 1
        With mT(i)
            Swap .X2, .X3: Swap .Y2, .Y3: Swap .Z2, .Z3
        End With
    Next i
End Sub

Function Orient(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, ByVal cx As Double, ByVal cy As Double) As Double
    Return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
End Function

' Do segments ab and cd cross? Touching at a shared end doesn't count.
Function Crosses(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, _
                 ByVal cx As Double, ByVal cy As Double, ByVal dx As Double, ByVal dy As Double) As Boolean
    If (ax = cx And ay = cy) Or (ax = dx And ay = dy) Or (bx = cx And by = cy) Or (bx = dx And by = dy) Then Return False
    Dim As Double d1 = Orient(cx, cy, dx, dy, ax, ay), d2 = Orient(cx, cy, dx, dy, bx, by)
    Dim As Double d3 = Orient(ax, ay, bx, by, cx, cy), d4 = Orient(ax, ay, bx, by, dx, dy)
    Return ((d1 > 0) <> (d2 > 0)) And ((d3 > 0) <> (d4 > 0))
End Function

' Drops repeated points and turns a clockwise outline round. Returns the new count.
Function CleanOutline(ox() As Double, oy() As Double, ByVal n As Long) As Long
    Dim As Long i, m
    Dim As Double a
    For i = 0 To n - 1
        If m = 0 Then
            ox(m) = ox(i): oy(m) = oy(i): m += 1
        ElseIf Abs(ox(i) - ox(m - 1)) > 0.000000001 Or Abs(oy(i) - oy(m - 1)) > 0.000000001 Then
            ox(m) = ox(i): oy(m) = oy(i): m += 1
        End If
    Next i
    Do While m > 1
        If Abs(ox(m - 1) - ox(0)) > 0.000000001 Or Abs(oy(m - 1) - oy(0)) > 0.000000001 Then Exit Do
        m -= 1
    Loop
    For i = 0 To m - 1
        a += ox(i) * oy((i + 1) Mod m) - ox((i + 1) Mod m) * oy(i)
    Next i
    If a < 0 Then
        For i = 0 To m \ 2 - 1
            Swap ox(i), ox(m - 1 - i)
            Swap oy(i), oy(m - 1 - i)
        Next i
    End If
    Return m
End Function

' A hole's edge, anticlockwise, from its right-most point.
Sub CircleLoop(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, px() As Double, py() As Double)
    Dim k As Long
    ReDim px(0 To mSegs - 1): ReDim py(0 To mSegs - 1)
    For k = 0 To mSegs - 1
        px(k) = cx + r * Cos(2 * PI * k / mSegs)
        py(k) = cy + r * Sin(2 * PI * k / mSegs)
    Next k
End Sub

' Is (x, y) inside a convex anticlockwise outline? 1 inside, 0 on its edge, -1 outside.
Function Inside(px() As Double, py() As Double, ByVal n As Long, ByVal x As Double, ByVal y As Double) As Long
    Dim As Long k
    Dim As Double o
    Dim As Boolean onEdge
    Const TOL = 0.0000001
    For k = 0 To n - 1
        o = Orient(px(k), py(k), px((k + 1) Mod n), py((k + 1) Mod n), x, y)
        If o < -TOL Then Return -1
        If o <= TOL Then onEdge = True
    Next k
    Return IIf(onEdge, 0, 1)
End Function

' Two convex anticlockwise outlines: 1 if B is wholly inside A, 0 if they
' don't meet at all, -1 if they overlap or touch.
Function Relation(ax() As Double, ay() As Double, ByVal na As Long, bx() As Double, by() As Double, ByVal nb As Long) As Long
    Dim As Long k, j
    Dim As Boolean allIn = True, anyIn
    For k = 0 To nb - 1
        Select Case Inside(ax(), ay(), na, bx(k), by(k))
        Case 1: anyIn = True
        Case 0: anyIn = True: allIn = False
        Case Else: allIn = False
        End Select
    Next k
    If allIn Then Return 1
    If anyIn Then Return -1
    For k = 0 To na - 1
        If Inside(bx(), by(), nb, ax(k), ay(k)) >= 0 Then Return -1
    Next k
    For k = 0 To na - 1
        For j = 0 To nb - 1
            If Crosses(ax(k), ay(k), ax((k + 1) Mod na), ay((k + 1) Mod na), bx(j), by(j), bx((j + 1) Mod nb), by((j + 1) Mod nb)) Then Return -1
        Next j
    Next k
    Return 0
End Function

' ---- extrudes ----

Function GetBody(ByRef d As TDesign, ByVal i As Long, ByRef z0 As Double, ByRef z1 As Double, _
                 ox() As Double, oy() As Double, ByRef no As Long) As Boolean
    Dim As Boolean seam(Any)
    ExtrudeRange d, i, z0, z1
    If z1 < z0 Then Swap z0, z1
    If z1 - z0 < MEPS Then Return False
    no = ProfilePoints(d.F(d.F(i).Ref), ox(), oy(), seam(), mSegs)
    no = CleanOutline(ox(), oy(), no)
    Return no >= 3
End Function

Function IsBody(ByRef d As TDesign, ByVal i As Long) As Boolean
    If d.F(i).Kind = FK_EXTRUDE And d.F(i).Suppressed = 0 Then Return RefOk(d, i)
    Return False
End Function

' The holes that come into extrude i through its top.
Function CollectHoles(ByRef d As TDesign, ByVal i As Long, ByVal z1 As Double, h() As THole) As Long
    Dim As Long j, n
    Dim As Double zt, zb, r
    ReDim h(0 To 7)
    For j = i + 1 To d.Count
        If d.F(j).Kind = FK_HOLE And d.F(j).Suppressed = 0 Then
            If RefOk(d, j) Then
                r = d.F(j).P1 / 2
                If ProfileContains(d.F(d.F(i).Ref), d.F(j).X, d.F(j).Y, r) Then
                    HoleSpan d, j, zt, zb
                    If zt >= z1 - MEPS And zb <= z1 + MEPS Then
                        If n > UBound(h) Then ReDim Preserve h(0 To n * 2)
                        h(n).X = d.F(j).X: h(n).Y = d.F(j).Y: h(n).R = r
                        h(n).ZTop = zt: h(n).ZBot = zb: h(n).Feat = j
                        n += 1
                    End If
                End If
            End If
        End If
    Next j
    Return n
End Function

' Which extrudes stand wholly on another one's top face, clear of its holes
' and of each other, and so can be joined to it.
Sub FindJoins(ByRef d As TDesign)
    Dim As Long i, j, k, na, nb, nc, nh
    Dim As Boolean ok
    Dim As Double az0, az1, bz0, bz1, cz0, cz1
    Dim As Double ax(Any), ay(Any), bx(Any), by(Any), cx(Any), cy(Any), hx(Any), hy(Any)
    Dim h() As THole
    ReDim mJoin(0 To d.Count)
    For j = 1 To d.Count
        If IsBody(d, j) AndAlso GetBody(d, j, bz0, bz1, bx(), by(), nb) Then
            For i = 1 To d.Count
                If i <> j AndAlso IsBody(d, i) AndAlso GetBody(d, i, az0, az1, ax(), ay(), na) Then
                    If Abs(az1 - bz0) < MEPS Then
                        ok = (Relation(ax(), ay(), na, bx(), by(), nb) = 1)
                        If ok Then
                            nh = CollectHoles(d, i, az1, h())
                            For k = 0 To nh - 1
                                CircleLoop h(k).X, h(k).Y, h(k).R, hx(), hy()
                                If Relation(bx(), by(), nb, hx(), hy(), mSegs) = -1 Then ok = False: Exit For
                            Next k
                        End If
                        If ok Then
                            For k = 1 To j - 1
                                If mJoin(k) = i Then
                                    GetBody d, k, cz0, cz1, cx(), cy(), nc
                                    If Relation(cx(), cy(), nc, bx(), by(), nb) <> 0 Then ok = False: Exit For
                                End If
                            Next k
                        End If
                        If ok Then mJoin(j) = i: Exit For
                    End If
                End If
            Next i
        End If
    Next j
End Sub

Sub HoleWall(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, ByVal za As Double, ByVal zb As Double, ByVal body As Long)
    Dim As Long k, k2
    Dim As Double px(Any), py(Any)
    CircleLoop cx, cy, r, px(), py()
    For k = 0 To mSegs - 1
        k2 = (k + 1) Mod mSegs
        ' wound the other way from an outside wall, so it faces into the hole
        AddTri px(k2), py(k2), za, px(k), py(k), za, px(k), py(k), zb, body
        AddTri px(k2), py(k2), za, px(k), py(k), zb, px(k2), py(k2), zb, body
    Next k
End Sub

' The floor of a hole (facing up) or its roof (facing down).
Sub HoleDisc(ByVal cx As Double, ByVal cy As Double, ByVal r As Double, ByVal z As Double, ByVal bUp As Boolean, ByVal body As Long)
    Dim As Long k, k2
    Dim As Double px(Any), py(Any)
    CircleLoop cx, cy, r, px(), py()
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

Sub ClearLoops()
    ReDim mLX(0 To 255): ReDim mLY(0 To 255)
    ReDim mLS(0 To 7): ReDim mLN(0 To 7)
    mNL = 0
End Sub

Sub AddLoop(px() As Double, py() As Double, ByVal n As Long)
    Dim As Long k, at
    If mNL > UBound(mLS) Then ReDim Preserve mLS(0 To mNL * 2): ReDim Preserve mLN(0 To mNL * 2)
    If mNL > 0 Then at = mLS(mNL - 1) + mLN(mNL - 1)
    Do While at + n > UBound(mLX) + 1
        ReDim Preserve mLX(0 To UBound(mLX) * 2 + 1): ReDim Preserve mLY(0 To UBound(mLY) * 2 + 1)
    Loop
    For k = 0 To n - 1
        mLX(at + k) = px(k): mLY(at + k) = py(k)
    Next k
    mLS(mNL) = at: mLN(mNL) = n
    mNL += 1
End Sub

Sub AddCircleLoop(ByVal cx As Double, ByVal cy As Double, ByVal r As Double)
    Dim As Double px(Any), py(Any)
    CircleLoop cx, cy, r, px(), py()
    AddLoop px(), py(), mSegs
End Sub

Function SlitIsClear(ByVal ax As Double, ByVal ay As Double, ByVal bx As Double, ByVal by As Double, _
        px() As Double, py() As Double, ByVal np As Long, cx() As Double, cy() As Double, ByVal nc As Long, done() As Boolean) As Boolean
    Dim As Long k, L, a, b
    For k = 0 To np - 1
        If Crosses(ax, ay, bx, by, px(k), py(k), px((k + 1) Mod np), py((k + 1) Mod np)) Then Return False
    Next k
    For k = 0 To nc - 1
        If Crosses(ax, ay, bx, by, cx(k), cy(k), cx((k + 1) Mod nc), cy((k + 1) Mod nc)) Then Return False
    Next k
    For L = 0 To mNL - 1
        If Not done(L) Then
            For k = 0 To mLN(L) - 1
                a = mLS(L) + k: b = mLS(L) + (k + 1) Mod mLN(L)
                If Crosses(ax, ay, bx, by, mLX(a), mLY(a), mLX(b), mLY(b)) Then Return False
            Next k
        End If
    Next L
    Return True
End Function

' Joins each loop (turned clockwise) into the outline with a slit.
Function BridgeLoops(ox() As Double, oy() As Double, ByVal no As Long, px() As Double, py() As Double, ByRef np As Long) As Boolean
    Dim As Long i, j, L, pick, nc, k, m, s, bestK, attempt, nn
    Dim As Double best, mx, my, dd
    Dim As Boolean ok
    Dim As Double cx(Any), cy(Any), nx(Any), ny(Any)
    Dim As Boolean tried(Any)
    CopyArr px(), ox(), no: CopyArr py(), oy(), no
    np = no
    If mNL = 0 Then Return True
    Dim done(0 To mNL - 1) As Boolean
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
        nc = mLN(pick)
        ReDim cx(0 To nc - 1): ReDim cy(0 To nc - 1)
        For k = 0 To nc - 1
            i = mLS(pick) + ((s - mLS(pick)) - k + nc) Mod nc
            cx(k) = mLX(i): cy(k) = mLY(i)
        Next k
        mx = cx(0): my = cy(0)
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
            If SlitIsClear(mx, my, px(bestK), py(bestK), px(), py(), np, cx(), cy(), nc, done()) Then ok = True: Exit For
        Next attempt
        If Not ok Then Return False
        nn = np + nc + 2
        ReDim nx(0 To nn - 1): ReDim ny(0 To nn - 1)
        m = 0
        For k = 0 To bestK: nx(m) = px(k): ny(m) = py(k): m += 1: Next k
        For k = 0 To nc - 1: nx(m) = cx(k): ny(m) = cy(k): m += 1: Next k
        nx(m) = cx(0): ny(m) = cy(0): m += 1
        For k = bestK To np - 1: nx(m) = px(k): ny(m) = py(k): m += 1: Next k
        CopyArr px(), nx(), nn: CopyArr py(), ny(), nn
        np = nn
    Next j
    Return True
End Function

Function SamePt(px() As Double, py() As Double, ByVal i As Long, ByVal j As Long) As Boolean
    Return px(i) = px(j) And py(i) = py(j)
End Function

' Cuts an anticlockwise polygon (which may touch itself along slits) into triangles.
Function EarClip(px() As Double, py() As Double, ByVal n As Long, tri() As Long, ByRef nt As Long) As Boolean
    Dim As Long i, a, b, c, nLeft, p, guard
    Dim As Boolean isEar, found
    Dim nxt(0 To n - 1) As Long, prv(0 To n - 1) As Long
    ReDim tri(0 To 3 * n)
    For i = 0 To n - 1
        nxt(i) = (i + 1) Mod n
        prv(i) = (i + n - 1) Mod n
    Next i
    nLeft = n: b = 0: nt = 0
    Do While nLeft > 3
        found = False
        For guard = 1 To nLeft
            a = prv(b): c = nxt(b)
            If Orient(px(a), py(a), px(b), py(b), px(c), py(c)) > 0.000000001 Then
                isEar = True
                p = nxt(c)
                Do While p <> a
                    If Not (SamePt(px(), py(), p, a) Or SamePt(px(), py(), p, b) Or SamePt(px(), py(), p, c)) Then
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
                    nt += 1
                    nxt(a) = c: prv(c) = a
                    nLeft -= 1
                    b = c
                    found = True
                    Exit For
                End If
            End If
            b = nxt(b)
        Next guard
        If Not found Then Return False
    Loop
    a = prv(b): c = nxt(b)
    tri(3 * nt) = a: tri(3 * nt + 1) = b: tri(3 * nt + 2) = c
    nt += 1
    Return True
End Function

' A flat cap at height z: the outline less the loops. bUp: facing up.
Function CapLoops(ox() As Double, oy() As Double, ByVal no As Long, ByVal z As Double, ByVal bUp As Boolean, ByVal body As Long) As Boolean
    Dim As Double px(Any), py(Any)
    Dim As Long np, nt, k
    Dim As Long tri(Any)
    If Not BridgeLoops(ox(), oy(), no, px(), py(), np) Then Return False
    If Not EarClip(px(), py(), np, tri(), nt) Then Return False
    For k = 0 To nt - 1
        Dim As Long a = tri(3 * k), b = tri(3 * k + 1), c = tri(3 * k + 2)
        If bUp Then
            AddTri px(a), py(a), z, px(b), py(b), z, px(c), py(c), z, body
        Else
            AddTri px(a), py(a), z, px(c), py(c), z, px(b), py(b), z, body
        End If
    Next k
    Return True
End Function

Sub MeshExtrude(ByRef d As TDesign, ByVal i As Long)
    Dim As Double z0, z1, fz0, fz1, zb
    Dim As Double ox(Any), oy(Any), fx(Any), fy(Any), hx(Any), hy(Any)
    Dim As Long no, nh, j, k, k2, nf
    Dim h() As THole
    If Not GetBody(d, i, z0, z1, ox(), oy(), no) Then Exit Sub
    nh = CollectHoles(d, i, z1, h())
    Dim inFoot(0 To nh) As Boolean

    ' the top: the outline less the holes and the bodies standing on it
    ClearLoops
    For j = 1 To d.Count
        If mJoin(j) = i Then
            GetBody d, j, fz0, fz1, fx(), fy(), nf
            AddLoop fx(), fy(), nf
            For k = 0 To nh - 1
                CircleLoop h(k).X, h(k).Y, h(k).R, hx(), hy()
                If Relation(fx(), fy(), nf, hx(), hy(), mSegs) = 1 Then inFoot(k) = True
            Next k
        End If
    Next j
    For k = 0 To nh - 1
        If (Not inFoot(k)) AndAlso h(k).ZBot < z1 - MEPS Then AddCircleLoop h(k).X, h(k).Y, h(k).R
    Next k
    If Not CapLoops(ox(), oy(), no, z1, True, i) Then
        mErr &= FeatureName(d, i) & " (its holes are too close together to cap). "
        Exit Sub
    End If

    ' the bottom, unless it stands on (and is joined to) another body
    If mJoin(i) = 0 Then
        ClearLoops
        For k = 0 To nh - 1
            If h(k).ZBot <= z0 + MEPS Then AddCircleLoop h(k).X, h(k).Y, h(k).R
        Next k
        CapLoops ox(), oy(), no, z0, False, i
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
        If zb < z1 - MEPS Then
            HoleWall h(k).X, h(k).Y, h(k).R, zb, z1, h(k).Feat
            If zb > z0 + MEPS Then HoleDisc h(k).X, h(k).Y, h(k).R, zb, True, h(k).Feat
            If inFoot(k) AndAlso h(k).ZTop <= z1 + MEPS Then HoleDisc h(k).X, h(k).Y, h(k).R, z1, False, h(k).Feat
        ElseIf inFoot(k) Then
            HoleDisc h(k).X, h(k).Y, h(k).R, z1, True, h(k).Feat
        End If
    Next k
End Sub

' ---- revolves ----

Sub MeshRevolve(ByRef d As TDesign, ByVal i As Long, ByVal nSegs As Long)
    Dim As Double sz, ang, a0, a1
    Dim As Double px(Any), py(Any)
    Dim As Boolean seam(Any)
    Dim As Long np, steps, k, j, j2
    Dim As Boolean full
    sz = SketchZ(d, d.F(i).Ref)
    np = ProfilePoints(d.F(d.F(i).Ref), px(), py(), seam(), nSegs)
    np = CleanOutline(px(), py(), np)
    If np < 3 Or Abs(d.F(i).P1) < 0.000001 Then Exit Sub
    ang = d.F(i).P1 * PI / 180
    full = Abs(Abs(d.F(i).P1) - 360) < 0.000001
    steps = Int(Abs(d.F(i).P1) / 360 * nSegs + 0.5)
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
        For j = 1 To np - 2
            AddTri px(0), py(0), sz, px(j + 1), py(j + 1), sz, px(j), py(j), sz, i
            AddTri px(0) * Cos(ang), py(0), sz - px(0) * Sin(ang), _
                   px(j) * Cos(ang), py(j), sz - px(j) * Sin(ang), _
                   px(j + 1) * Cos(ang), py(j + 1), sz - px(j + 1) * Sin(ang), i
        Next j
    End If
End Sub

' Fills t() with the part's triangles and returns how many. sErr says which
' bodies couldn't be meshed, if any (they're left out).
Function MeshDesign(ByRef d As TDesign, t() As TTri, ByVal nSegs As Long, ByRef sErr As String) As Long
    Dim As Long i, first
    ReDim mT(0 To 1023)
    mN = 0: mErr = "": mSegs = nSegs
    FindJoins d
    For i = 1 To d.Count
        If d.F(i).Suppressed = 0 AndAlso RefOk(d, i) Then
            Select Case d.F(i).Kind
            Case FK_EXTRUDE
                MeshExtrude d, i
            Case FK_REVOLVE
                first = mN
                MeshRevolve d, i, nSegs
                If mN > first Then OrientOutward first, mN
            End Select
        End If
    Next i
    ReDim t(0 To IIf(mN > 0, mN - 1, 0))
    For i = 0 To mN - 1: t(i) = mT(i): Next
    sErr = mErr
    Return mN
End Function
