' import.bas - File > Open on a real SolidCraft design (.solidcraft). A port
' of the Windows version's modImport.
'
' A .solidcraft file is a ZIP holding document.json, the design's feature
' history (a plain-JSON design works too). We rebuild what SolidCraft 98 can
' build: flat sketches of rectangles (rounded or not) and circles, extrudes,
' revolves about the sketch's Y axis, and straight-down holes. Everything
' else stays in the timeline as "Requires SolidCraft 2000". A feature comes
' over whole or not at all.

Const IEPS = 0.001          ' mm: "the same height"
Const PK_RECT = 1, PK_CIRCLE = 2
Const MAX_PROFILES = 64

Type TProfile
    Kind As Long
    X As Double                 ' rectangle: lower-left corner; circle: centre (world)
    Y As Double
    W As Double                 ' rectangle size, or circle radius in W
    H As Double
    R As Double                 ' rectangle corner radius
    Parent As Long              ' -1 for an outline, else the outline it's a hole in
End Type

Type TSketchInfo
    Id As Long
    Name As String
    Ok As Boolean
    Why As String
    Z As Double
    OnFace As Boolean
    OX As Double
    OY As Double
    Used As Boolean
    P(0 To MAX_PROFILES - 1) As TProfile
    NP As Long
End Type

Dim Shared iSk() As TSketchInfo
Dim Shared iNSk As Long
Dim Shared iParamName() As String, iParamExpr() As String
Dim Shared iNParam As Long
Dim Shared iForeign As String
Dim Shared iNForeign As Long
Dim Shared iFull As Boolean

Function IsSolidCraftDesign(ByRef sPath As String) As Boolean
    Dim As Long fh = FreeFile, i
    If Open(sPath For Binary Access Read As #fh) <> 0 Then Return False
    If LOF(fh) < 4 Then Close #fh: Return False
    Dim As String b = String(4, 0)
    Get #fh, , b
    Close #fh
    If b = "PK" & Chr(3, 4) Then Return True           ' a ZIP
    For i = 0 To 3                                     ' or plain JSON
        If b[i] = &h7B Then Return True
        If b[i] <> 32 And b[i] <> 9 And b[i] <> 10 And b[i] <> 13 And b[i] <> &hEF And b[i] <> &hBB And b[i] <> &hBF Then Exit For
    Next
    Return False
End Function

Function PrettyType(ByVal s As String) As String
    Dim i As Long
    For i = 0 To Len(s) - 1
        If s[i] = Asc("_") Then s[i] = 32
    Next
    Return UCase(Left(s, 1)) & Mid(s, 2)
End Function

Function AddRaw(ByRef d As TDesign, ByRef f As TFeature, ByRef sName As String) As Long
    If d.Count >= MAX_FEATURES Then iFull = True: Return 0
    d.Count += 1
    f.Name = Left(sName, 24)
    d.F(d.Count) = f
    Return d.Count
End Function

Sub Foreign(ByRef d As TDesign, ByVal fNode As Long, ByRef sWhat As String, ByRef sWhy As String)
    Dim f As TFeature
    Dim As String sName = JStr(JGet(fNode, "name"))
    If Len(sName) = 0 Then sName = sWhat
    f.Kind = FK_FOREIGN
    f.Info = Left(sWhat, 32)
    AddRaw d, f, sName
    iNForeign += 1
    If iNForeign <= 12 Then
        iForeign &= "    " & sName & " (" & LCase(sWhat) & IIf(Len(sWhy) > 0, ": " & sWhy, "") & ")" & Chr(10)
    ElseIf iNForeign = 13 Then
        iForeign &= "    ...and more." & Chr(10)
    End If
End Sub

Sub LoadParams(ByVal ps As Long)
    Dim As Long i, p
    iNParam = JCount(ps)
    ReDim iParamName(0 To iNParam): ReDim iParamExpr(0 To iNParam)
    For i = 0 To iNParam - 1
        p = JItem(ps, i)
        iParamName(i) = JStr(JGet(p, "name"))
        iParamExpr(i) = JStr(JGet(p, "expr"))
    Next
End Sub

Function IsAlpha(ByVal c As Long) As Boolean
    Return (c >= 65 And c <= 90) Or (c >= 97 And c <= 122) Or c = 95
End Function

' The value of an expression like "6", "12 mm", "d1 / 2", "90 deg".
Function EvalExpr(ByVal s As String, ByRef ok As Boolean, ByVal depth As Long = 0) As Double
    Dim As String outS, word
    Dim As Long i, j, k
    Dim As Double v
    ok = False
    If depth > 20 Then Return 0
    i = 0
    Do While i < Len(s)
        Dim As Long c = s[i]
        If c = 176 Then
            i += 1                       ' the degree sign
        ElseIf IsAlpha(c) Then
            j = i
            Do While j < Len(s) AndAlso (IsAlpha(s[j]) Or (s[j] >= 48 And s[j] <= 57))
                j += 1
            Loop
            word = Mid(s, i + 1, j - i)
            Select Case LCase(word)
            Case "mm", "deg", "degree", "degrees"
            Case "cm": outS &= "*10"
            Case "m": outS &= "*1000"
            Case "in", "inch": outS &= "*25.4"
            Case "rad": outS &= "*57.2957795130823"
            Case "pi": outS &= "3.14159265358979"
            Case Else
                For k = 0 To iNParam - 1
                    If iParamName(k) = word Then Exit For
                Next
                If k >= iNParam Then Return 0
                v = EvalExpr(iParamExpr(k), ok, depth + 1)
                If Not ok Then Return 0
                outS &= "(" & Trim(Str(v)) & ")"
            End Select
            i = j
        Else
            outS &= Chr(c)
            i += 1
        End If
    Loop
    v = Evaluate(outS)
    ok = (exErr = 0)
    Return v
End Function

Function NodeValue(ByVal n As Long, ByRef ok As Boolean) As Double
    If JKind(n) = JS_NUM Then ok = True: Return JNum(n)
    If JKind(n) = JS_STR Then Return EvalExpr(JStr(n), ok)
    ok = False
    Return 0
End Function

Function INear(ByVal a As Double, ByVal b As Double) As Boolean
    Return Abs(a - b) < IEPS
End Function

' Floating-point dust from the source (5.9999999999999964) back to the round number.
Function Snap(ByVal v As Double) As Double
    Dim As Double r = Sgn(v) * Int(Abs(v) * 1000000 + 0.5) / 1000000
    If Abs(r) < 0.000001 Then r = 0
    Return r
End Function

Sub NotOk(ByRef s As TSketchInfo, ByRef sWhy As String)
    If s.Ok Then s.Ok = False: s.Why = sWhy
End Sub

Sub AddProfile(ByRef s As TSketchInfo, ByVal kind As Long, ByVal x As Double, ByVal y As Double, ByVal w As Double, ByVal h As Double, ByVal r As Double)
    If s.NP >= MAX_PROFILES Then NotOk s, "too many shapes": Exit Sub
    With s.P(s.NP)
        .Kind = kind: .X = x: .Y = y: .W = w: .H = h: .R = r: .Parent = -1
    End With
    s.NP += 1
End Sub

Sub ProfileAsFeature(ByRef p As TProfile, ByRef t As TFeature)
    If p.Kind = PK_CIRCLE Then
        t.Kind = FK_SKETCH_CIRCLE: t.X = p.X: t.Y = p.Y: t.P1 = p.W
    Else
        t.Kind = FK_SKETCH_RECT: t.X = p.X: t.Y = p.Y: t.P1 = p.W: t.P2 = p.H: t.P3 = p.R
    End If
End Sub

' A circle inside another outline is a hole in it. One level deep.
Sub FindHoles(ByRef s As TSketchInfo)
    Dim As Long i, j
    Dim t As TFeature
    For i = 0 To s.NP - 1
        If s.P(i).Kind = PK_CIRCLE Then
            For j = 0 To s.NP - 1
                If j <> i And s.P(j).Parent = -1 Then
                    Dim blank As TFeature
                    t = blank
                    ProfileAsFeature s.P(j), t
                    If ProfileContains(t, s.P(i).X, s.P(i).Y, s.P(i).W) Then
                        If Not (s.P(j).Kind = PK_CIRCLE And s.P(j).W <= s.P(i).W) Then s.P(i).Parent = j: Exit For
                    End If
                End If
            Next
        End If
    Next
    For i = 0 To s.NP - 1
        If s.P(i).Parent >= 0 AndAlso s.P(s.P(i).Parent).Parent >= 0 Then NotOk s, "islands inside holes"
    Next
End Sub

Sub ReboxRounded(px() As Double, py() As Double, ByVal curves As Long, ByRef minX As Double, ByRef maxX As Double, ByRef minY As Double, ByRef maxY As Double)
    Dim As Long i, c, a
    Dim As Double cx, cy, r
    For i = 0 To JCount(curves) - 1
        c = JItem(curves, i)
        If JStr(JGet(c, "type")) = "arc" And Not JBool(JGet(c, "construction")) And JGet(c, "link") = 0 Then
            cx = px(JNum(JGet(c, "c"))): cy = py(JNum(JGet(c, "c")))
            a = JNum(JGet(c, "a"))
            r = Sqr((px(a) - cx) ^ 2 + (py(a) - cy) ^ 2)
            GrowBox cx - r, cy - r, minX, maxX, minY, maxY
            GrowBox cx + r, cy + r, minX, maxX, minY, maxY
        End If
    Next
End Sub

Sub ReadSketch(ByRef d As TDesign, ByVal f As Long)
    Dim s As TSketchInfo
    Dim As Long plane, pl, sk, pts, curves, np, i, c, nLine, nArc, a, b
    Dim As Boolean ok
    Dim As Double v, minX = 1E+30, maxX = -1E+30, minY = 1E+30, maxY = -1E+30, rr = -1
    Dim As String sType
    s.Id = JNum(JGet(f, "id"))
    s.Name = JStr(JGet(f, "name"))
    s.Ok = True
    ' where the sketch is: the XY plane, or a flat face pointing straight up
    plane = JGet(f, "plane")
    Select Case JStr(JGet(plane, "type"))
    Case "origin"
        If JStr(JGet(plane, "name")) <> "XY" Then
            NotOk s, "drawn on the " & JStr(JGet(plane, "name")) & " plane"
        ElseIf JGet(plane, "offset") > 0 Then
            v = NodeValue(JGet(plane, "offset"), ok)
            If ok Then s.Z = v Else NotOk s, "an offset SolidCraft 98 can't work out"
        End If
    Case "face"
        pl = JGet(plane, "plane")
        If Not (INear(JNum(JItem(JGet(pl, "x_dir"), 0)), 1) And INear(JNum(JItem(JGet(pl, "y_dir"), 1)), 1)) Then
            NotOk s, "drawn on a face that doesn't point straight up"
        Else
            s.OX = JNum(JItem(JGet(pl, "origin"), 0))
            s.OY = JNum(JItem(JGet(pl, "origin"), 1))
            s.Z = JNum(JItem(JGet(pl, "origin"), 2))
            s.OnFace = True
        End If
    Case Else
        NotOk s, "drawn on a construction plane"
    End Select
    If JBool(JGet(plane, "flip")) Then NotOk s, "drawn on a flipped plane"

    sk = JGet(f, "sketch")
    pts = JGet(sk, "points")
    np = JCount(pts)
    Dim As Double px(0 To IIf(np > 0, np - 1, 0)), py(0 To IIf(np > 0, np - 1, 0))
    For i = 0 To np - 1
        px(i) = s.OX + JNum(JItem(JGet(JItem(pts, i), "pos"), 0))
        py(i) = s.OY + JNum(JItem(JGet(JItem(pts, i), "pos"), 1))
    Next

    ' circles are profiles of their own; lines and arcs have to make one rectangle
    curves = JGet(sk, "curves")
    For i = 0 To JCount(curves) - 1
        c = JItem(curves, i)
        If Not JBool(JGet(c, "construction")) And JGet(c, "link") = 0 Then
            sType = JStr(JGet(c, "type"))
            Select Case sType
            Case "circle"
                Dim As Long ci = JNum(JGet(c, "c"))
                If ci >= 0 And ci < np Then AddProfile s, PK_CIRCLE, px(ci), py(ci), JNum(JGet(c, "r")), 0, 0
            Case "line"
                a = JNum(JGet(c, "a")): b = JNum(JGet(c, "b"))
                If a < 0 Or a >= np Or b < 0 Or b >= np Then NotOk s, "a broken line": Continue For
                If Not (INear(px(a), px(b)) Or INear(py(a), py(b))) Then NotOk s, "a line that isn't horizontal or vertical"
                GrowBox px(a), py(a), minX, maxX, minY, maxY
                GrowBox px(b), py(b), minX, maxX, minY, maxY
                nLine += 1
            Case "arc"
                a = JNum(JGet(c, "a")): b = JNum(JGet(c, "c"))
                If a < 0 Or a >= np Or b < 0 Or b >= np Then NotOk s, "a broken arc": Continue For
                v = Sqr((px(a) - px(b)) ^ 2 + (py(a) - py(b)) ^ 2)
                If rr >= 0 And Not INear(v, rr) Then NotOk s, "corners of different sizes"
                rr = v
                nArc += 1
            Case Else
                NotOk s, "a " & sType
            End Select
        End If
    Next
    If nLine > 0 Or nArc > 0 Then
        If nLine = 4 And (nArc = 0 Or nArc = 4) Then
            If nArc = 0 Then rr = 0
            If rr > 0 Then ReboxRounded px(), py(), curves, minX, maxX, minY, maxY
            AddProfile s, PK_RECT, minX, minY, maxX - minX, maxY - minY, rr
        Else
            NotOk s, "a shape that isn't a rectangle or a circle"
        End If
    End If
    If s.NP = 0 And s.Ok Then NotOk s, "nothing SolidCraft 98 can draw"
    If s.Ok Then FindHoles s
    If iNSk > UBound(iSk) Then ReDim Preserve iSk(0 To UBound(iSk) * 2 + 1)
    iSk(iNSk) = s
    iNSk += 1
End Sub

Function FindSketch(ByVal id As Long) As Long
    Dim i As Long
    For i = 0 To iNSk - 1
        If iSk(i).Id = id Then Return i
    Next
    Return -1
End Function

' The SolidCraft 98 extrude whose top is at height z and that the circle fits on.
Function ExtrudeWithTopAt(ByRef d As TDesign, ByVal z As Double, ByVal x As Double, ByVal y As Double, ByVal r As Double) As Long
    Dim As Long i
    Dim As Double z0, z1
    For i = d.Count To 1 Step -1
        If d.F(i).Kind = FK_EXTRUDE AndAlso RefOk(d, i) Then
            ExtrudeRange d, i, z0, z1
            If Abs(z1 - z) < IEPS AndAlso ProfileContains(d.F(d.F(i).Ref), x, y, r) Then Return i
        End If
    Next
    Return 0
End Function

Function CountOutlines(ByVal k As Long) As Long
    Dim As Long i, n
    For i = 0 To iSk(k).NP - 1
        If iSk(k).P(i).Parent = -1 Then n += 1
    Next
    Return n
End Function

Function OutlineProfile(ByVal k As Long, ByVal n As Long) As Long
    Dim As Long i, c
    For i = 0 To iSk(k).NP - 1
        If iSk(k).P(i).Parent = -1 Then
            If c = n Then Return i
            c += 1
        End If
    Next
    Return 0
End Function

' Adds one SolidCraft 98 sketch per outline of sketch k, at height z, and puts
' their indices in idx(). A sketch on a face sits on the extrude under it.
Sub EmitSketches(ByRef d As TDesign, ByVal k As Long, ByVal z As Double, idx() As Long)
    Dim As Long i, n, onExt
    Dim As Double z0, z1
    ReDim idx(0 To CountOutlines(k))
    iSk(k).Used = True
    For i = 0 To iSk(k).NP - 1
        If iSk(k).P(i).Parent = -1 Then
            Dim f As TFeature
            ProfileAsFeature iSk(k).P(i), f
            onExt = 0
            If iSk(k).OnFace And Abs(z - iSk(k).Z) < IEPS Then onExt = ExtrudeWithTopAt(d, z, f.X, f.Y, 0)
            If onExt > 0 Then
                ExtrudeRange d, onExt, z0, z1
                f.Ref = onExt: f.Z = Snap(z - z1)
            Else
                f.Z = Snap(z)
            End If
            n += 1
            Dim As String sName = iSk(k).Name
            If CountOutlines(k) > 1 Then sName = Left(sName, 20) & " " & n
            idx(n - 1) = AddRaw(d, f, sName)
        End If
    Next
End Sub

Sub ImportCut(ByRef d As TDesign, ByVal f As Long, ByVal k As Long, ByVal dist As Double, ByVal through As Boolean)
    Dim As Long i, c, n = iSk(k).NP
    Dim As String sName = JStr(JGet(f, "name"))
    Dim targets(0 To n) As Long
    ' check every circle first: all or nothing
    For i = 0 To n - 1
        If iSk(k).P(i).Kind <> PK_CIRCLE Then iSk(k).Used = True: Foreign d, f, "Extrude (cut)", "a cut that isn't round": Exit Sub
        targets(i) = ExtrudeWithTopAt(d, iSk(k).Z, iSk(k).P(i).X, iSk(k).P(i).Y, iSk(k).P(i).W)
        If targets(i) = 0 Then iSk(k).Used = True: Foreign d, f, "Extrude (cut)", "not into the top of a block": Exit Sub
    Next
    iSk(k).Used = True
    For i = 0 To n - 1
        Dim hole As TFeature
        hole.Kind = FK_HOLE: hole.Ref = targets(i)
        hole.X = iSk(k).P(i).X: hole.Y = iSk(k).P(i).Y: hole.P1 = iSk(k).P(i).W * 2
        If Not through Then hole.P2 = dist
        c += 1
        If AddRaw(d, hole, IIf(n > 1, Left(sName, 20) & " " & c, sName)) = 0 Then Exit Sub
    Next
End Sub

Sub ImportExtrude(ByRef d As TDesign, ByVal f As Long)
    Dim As Long k, ext, n, i, j, h, c
    Dim As Double dist, z
    Dim As Boolean ok, through
    Dim As String sName = JStr(JGet(f, "name")), sDir, sOp
    Dim idx() As Long
    k = FindSketch(JNum(JGet(f, "sketch")))
    If k < 0 Then Foreign d, f, "Extrude", "not from a sketch": Exit Sub
    If Not iSk(k).Ok Then iSk(k).Used = True: Foreign d, f, "Extrude", "its sketch has " & iSk(k).Why: Exit Sub
    If JStr(JGet(JGet(f, "profiles"), "type")) <> "all" Then Foreign d, f, "Extrude", "only some of its sketch's profiles": Exit Sub
    If JGet(f, "taper") > 0 Then Foreign d, f, "Extrude", "tapered": Exit Sub
    ext = JGet(f, "extent")
    If JGet(ext, "distance2") > 0 Or JGet(ext, "to") > 0 Or JGet(ext, "start_offset") > 0 Then
        Foreign d, f, "Extrude", "an extent SolidCraft 98 doesn't have": Exit Sub
    End If
    through = JBool(JGet(ext, "through_all"))
    If Not through Then
        dist = NodeValue(JGet(ext, "distance"), ok)
        If Not ok Or dist <= 0 Then Foreign d, f, "Extrude", "a distance SolidCraft 98 can't work out": Exit Sub
    End If
    sDir = JStr(JGet(ext, "direction"))
    sOp = JStr(JGet(f, "operation"))
    Select Case sOp
    Case "cut"
        ImportCut d, f, k, dist, through
        Exit Sub
    Case "new_body", "new", "join", "auto", ""
    Case Else
        Foreign d, f, "Extrude", PrettyType(sOp): Exit Sub
    End Select
    If through Then Foreign d, f, "Extrude", "through all": Exit Sub
    z = iSk(k).Z
    Select Case sDir
    Case "negative": z -= dist
    Case "symmetric": z -= dist / 2
    End Select
    n = CountOutlines(k)
    EmitSketches d, k, z, idx()
    For i = 0 To n - 1
        If idx(i) = 0 Then Exit Sub
        Dim e As TFeature
        e.Kind = FK_EXTRUDE: e.Ref = idx(i): e.P1 = dist
        j = AddRaw(d, e, IIf(n > 1, Left(sName, 20) & " " & (i + 1), sName))
        If j = 0 Then Exit Sub
        ' circles inside this outline are holes right through it
        For h = 0 To iSk(k).NP - 1
            If iSk(k).P(h).Parent = OutlineProfile(k, i) Then
                c += 1
                Dim hole As TFeature
                hole.Kind = FK_HOLE: hole.Ref = j
                hole.X = iSk(k).P(h).X: hole.Y = iSk(k).P(h).Y: hole.P1 = iSk(k).P(h).W * 2
                hole.P2 = dist                   ' through this body, and no further
                AddRaw d, hole, Left(sName, 17) & " hole " & c
            End If
        Next
    Next
End Sub

Sub ImportRevolve(ByRef d As TDesign, ByVal f As Long)
    Dim As Long k, ax, n, i
    Dim As Double ang
    Dim As Boolean ok
    Dim As String sName = JStr(JGet(f, "name")), op
    Dim idx() As Long
    k = FindSketch(JNum(JGet(f, "sketch")))
    If k < 0 Then Foreign d, f, "Revolve", "not from a sketch": Exit Sub
    If Not iSk(k).Ok Then iSk(k).Used = True: Foreign d, f, "Revolve", "its sketch has " & iSk(k).Why: Exit Sub
    ax = JGet(f, "axis")
    If JStr(JGet(ax, "type")) <> "sketch_axis" Or JStr(JGet(ax, "axis")) <> "y" Then Foreign d, f, "Revolve", "about an axis other than the sketch's Y": Exit Sub
    If Not INear(iSk(k).OX, 0) Then Foreign d, f, "Revolve", "about an axis off the origin": Exit Sub
    op = JStr(JGet(f, "operation"))
    If op = "cut" Or op = "intersect" Then Foreign d, f, "Revolve", PrettyType(op): Exit Sub
    If JStr(JGet(f, "direction")) = "symmetric" Or JGet(f, "angle2") > 0 Or JGet(f, "to") > 0 Then Foreign d, f, "Revolve", "a two-sided or symmetric angle": Exit Sub
    If JStr(JGet(JGet(f, "profiles"), "type")) <> "all" Then Foreign d, f, "Revolve", "only some of its sketch's profiles": Exit Sub
    If JGet(f, "angle") > 0 Then
        ang = NodeValue(JGet(f, "angle"), ok)
        If Not ok Then Foreign d, f, "Revolve", "an angle SolidCraft 98 can't work out": Exit Sub
    Else
        ang = 360
    End If
    If ang = 0 Or Abs(ang) > 360 Then Foreign d, f, "Revolve", "an angle over 360 degrees": Exit Sub
    For i = 0 To iSk(k).NP - 1
        With iSk(k).P(i)
            If .Parent >= 0 Then Foreign d, f, "Revolve", "a profile with a hole in it": Exit Sub
            If .Kind = PK_CIRCLE Then
                If .X - .W < -IEPS And .X + .W > IEPS Then Foreign d, f, "Revolve", "a profile across the axis": Exit Sub
            Else
                If .X < -IEPS And .X + .W > IEPS Then Foreign d, f, "Revolve", "a profile across the axis": Exit Sub
            End If
        End With
    Next
    n = CountOutlines(k)
    EmitSketches d, k, iSk(k).Z, idx()
    For i = 0 To n - 1
        If idx(i) = 0 Then Exit Sub
        Dim e As TFeature
        e.Kind = FK_REVOLVE: e.Ref = idx(i)
        e.P1 = -ang          ' SolidCraft turns +X towards +Z; SolidCraft 98 the other way
        If AddRaw(d, e, IIf(n > 1, Left(sName, 20) & " " & (i + 1), sName)) = 0 Then Exit Sub
    Next
End Sub

Sub ImportHole(ByRef d As TDesign, ByVal f As Long)
    Dim As Long pos_ = JGet(f, "position"), dirn = JGet(f, "direction"), t
    Dim As Double x, y, z, dia, depth
    Dim As Boolean ok
    If JKind(pos_) <> JS_ARR Then Foreign d, f, "Hole", "placed on sketch points": Exit Sub
    If dirn > 0 Then
        If Not (INear(JNum(JItem(dirn, 0)), 0) And INear(JNum(JItem(dirn, 1)), 0) And JNum(JItem(dirn, 2)) < 0) Then Foreign d, f, "Hole", "not straight down": Exit Sub
    End If
    Dim As String sKind = JStr(JGet(JGet(f, "hole"), "type"))
    If sKind <> "" And sKind <> "simple" And sKind <> "drilled" Then Foreign d, f, "Hole", PrettyType(sKind): Exit Sub
    If JGet(f, "diameter") = 0 Then Foreign d, f, "Hole", "a clearance or tapped size": Exit Sub
    dia = NodeValue(JGet(f, "diameter"), ok)
    If Not ok Or dia <= 0 Then Foreign d, f, "Hole", "a diameter SolidCraft 98 can't work out": Exit Sub
    If JGet(f, "depth") > 0 Then
        depth = NodeValue(JGet(f, "depth"), ok)
        If Not ok Or depth <= 0 Then Foreign d, f, "Hole", "a depth SolidCraft 98 can't work out": Exit Sub
    End If
    If JGet(f, "to") > 0 Then Foreign d, f, "Hole", "drilled to an object": Exit Sub
    x = NodeValue(JItem(pos_, 0), ok): y = NodeValue(JItem(pos_, 1), ok): z = NodeValue(JItem(pos_, 2), ok)
    t = ExtrudeWithTopAt(d, z, x, y, dia / 2)
    If t = 0 Then Foreign d, f, "Hole", "not on the top of a block SolidCraft 98 built": Exit Sub
    Dim h As TFeature
    h.Kind = FK_HOLE: h.Ref = t: h.X = x: h.Y = y: h.P1 = dia: h.P2 = depth
    AddRaw d, h, JStr(JGet(f, "name"))
End Sub

' Reads the design at sPath into d. Returns False (after saying why) if it can't.
Function ImportSolidCraft(ByRef sPath As String, ByRef d As TDesign) As Boolean
    Dim As String txt
    Dim As Long n, root, feats, k, f
    n = ZipReadEntry(sPath, "document.json", txt)
    If Len(ZipErr) Then
        MsgBox "Can't read '" & sPath & "' as a SolidCraft design." & Chr(10) & Chr(10) & ZipErr, MB_EXCLAMATION
        Return False
    End If
    If n < 0 Then                         ' not a ZIP: a plain JSON design
        Dim As Long fh = FreeFile
        If Open(sPath For Binary Access Read As #fh) <> 0 Then MsgBox "File not found: " & sPath, MB_EXCLAMATION: Return False
        txt = String(LOF(fh), 0)
        Get #fh, , txt
        Close #fh
    End If
    root = JsonParse(txt)
    If Len(JsonErr) Then
        MsgBox "Can't read '" & sPath & "' as a SolidCraft design." & Chr(10) & Chr(10) & JsonErr, MB_EXCLAMATION
        Return False
    End If
    Dim As String sFormat = JStr(JGet(root, "format"))
    feats = JGet(root, "features")
    If JKind(feats) <> JS_ARR Or (Left(sFormat, 11) <> "solidcraft/" And Left(sFormat, 11) <> "solvecraft/") Then
        MsgBox "'" & sPath & "' isn't a SolidCraft design that SolidCraft 98 can read.", MB_EXCLAMATION
        Return False
    End If
    NewDesign d, Left(JStr(JGet(root, "name")), 64)
    If Len(Trim(d.Title)) = 0 Then d.Title = FileTitle(sPath)
    LoadParams JGet(root, "params")
    iNSk = 0: ReDim iSk(0 To 15)
    iForeign = "": iNForeign = 0: iFull = False
    For k = 0 To JCount(feats) - 1
        f = JItem(feats, k)
        Dim As String sType = JStr(JGet(f, "type"))
        Select Case sType
        Case "sketch": ReadSketch d, f
        Case "extrude": ImportExtrude d, f
        Case "revolve": ImportRevolve d, f
        Case "hole": ImportHole d, f
        Case Else: Foreign d, f, PrettyType(sType), ""
        End Select
    Next
    ' sketches nothing was built from still show up, if they can be drawn
    Dim unused() As Long
    For k = 0 To iNSk - 1
        If iSk(k).Ok And Not iSk(k).Used Then EmitSketches d, k, iSk(k).Z, unused()
    Next
    If iNForeign > 0 Then
        MsgBox "This design was made in SolidCraft. SolidCraft 98 has opened what it can build." & Chr(10) & Chr(10) & _
            "These features require SolidCraft 2000 and have been left out:" & Chr(10) & iForeign & Chr(10) & _
            "They're still in the timeline.", MB_INFO
    End If
    If iFull Then
        MsgBox "The design has more features than a SolidCraft 98 part can hold (" & MAX_FEATURES & ")." & Chr(10) & _
            "The rest have been left out.", MB_EXCLAMATION
    End If
    Return True
End Function
