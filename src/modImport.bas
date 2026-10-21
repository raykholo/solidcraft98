Attribute VB_Name = "modImport"
' modImport - File > Open on a real SolidCraft design (.solidcraft).
'
' A .solidcraft file is a ZIP holding document.json, the design's feature
' history (a plain-JSON design works too). We read that history and rebuild
' what SolidCraft 98 can build: flat sketches of rectangles (rounded or not)
' and circles, extrudes, revolves about the sketch's Y axis, and straight-down
' holes. Everything else stays in the timeline as "Requires SolidCraft 2000",
' and the part opens with what's left.
'
' A feature is brought over whole or not at all: if any part of it can't be
' built exactly, the whole feature waits for SolidCraft 2000.
Option Explicit

Private Const EPS As Double = 0.001          ' mm: "the same height"

Private Const PK_RECT As Integer = 1
Private Const PK_CIRCLE As Integer = 2

Private Type TProfile
    Kind As Integer
    X As Double                 ' rectangle: lower-left corner; circle: centre (world)
    Y As Double
    W As Double                 ' rectangle size, or circle radius in W
    H As Double
    R As Double                 ' rectangle corner radius
    Parent As Integer           ' -1 for an outline, else the outline it's a hole in
End Type

Private Type TSketchInfo
    Id As Long                  ' SolidCraft feature id
    Name As String
    Ok As Boolean
    Why As String               ' why not, when not Ok
    Z As Double                 ' world height of the sketch plane
    OnFace As Boolean           ' sketched on a body's face (so it can sit on an extrude)
    OX As Double                ' world position of the sketch origin
    OY As Double
    Used As Boolean
    Profiles() As TProfile
    NProfiles As Integer
End Type

Private mSketch() As TSketchInfo
Private mNSketch As Integer
Private mParamName() As String
Private mParamExpr() As String
Private mNParam As Integer
Private mForeign As String
Private mNForeign As Integer
Private mFull As Boolean

' Is this file a SolidCraft design rather than a SolidCraft 98 part?
Public Function IsSolidCraftDesign(ByVal sPath As String) As Boolean
    Dim fh As Integer, b(0 To 3) As Byte, n As Long, i As Integer
    On Error GoTo Nope
    fh = FreeFile
    Open sPath For Binary Access Read As #fh
    n = LOF(fh)
    If n >= 4 Then Get #fh, 1, b
    Close #fh
    If n < 4 Then Exit Function
    If b(0) = &H50 And b(1) = &H4B And b(2) = 3 And b(3) = 4 Then IsSolidCraftDesign = True    ' a ZIP
    For i = 0 To 3                                                     ' or plain JSON
        If b(i) = &H7B Then IsSolidCraftDesign = True: Exit For
        If b(i) <> 32 And b(i) <> 9 And b(i) <> 10 And b(i) <> 13 And b(i) <> &HEF And b(i) <> &HBB And b(i) <> &HBF Then Exit For
    Next i
    Exit Function
Nope:
    If fh <> 0 Then Close #fh
End Function

' Reads the design at sPath into d. Returns False (after saying why) if it can't.
Public Function ImportSolidCraft(ByVal sPath As String, d As TDesign) As Boolean
    Dim b() As Byte, n As Long, root As Long, feats As Long, k As Long, f As Long, sType As String
    Dim fh As Integer, sFormat As String
    On Error GoTo Failed
    n = ZipReadEntry(sPath, "document.json", b)
    If n < 0 Then                         ' not a ZIP: a plain JSON design
        fh = FreeFile
        Open sPath For Binary Access Read As #fh
        n = LOF(fh)
        ReDim b(0 To IIf(n > 0, n - 1, 0))
        If n > 0 Then Get #fh, 1, b
        Close #fh
        fh = 0
    End If
    root = JsonParse(StripBom(Utf8ToString(b, n)))
    sFormat = JStr(JGet(root, "format"))
    feats = JGet(root, "features")
    If JKind(feats) <> JS_ARR Or (Left$(sFormat, 11) <> "solidcraft/" And Left$(sFormat, 11) <> "solvecraft/") Then
        MsgBox "'" & sPath & "' isn't a SolidCraft design that SolidCraft 98 can read.", vbExclamation, App.Title
        Exit Function
    End If

    NewDesign d, JStr(JGet(root, "name"))
    If Len(Trim$(d.Title)) = 0 Then d.Title = FileTitle(sPath)
    LoadParams JGet(root, "params")
    mNSketch = 0
    ReDim mSketch(0 To 15)
    mForeign = ""
    mNForeign = 0
    mFull = False

    For k = 0 To JCount(feats) - 1
        f = JItem(feats, k)
        sType = JStr(JGet(f, "type"))
        Select Case sType
        Case "sketch": ReadSketch d, f
        Case "extrude": ImportExtrude d, f
        Case "revolve": ImportRevolve d, f
        Case "hole": ImportHole d, f
        Case Else: Foreign d, f, PrettyType(sType), ""
        End Select
    Next k
    ' sketches nothing was built from still show up, if they can be drawn
    Dim unused() As Integer
    For k = 0 To mNSketch - 1
        If mSketch(k).Ok And Not mSketch(k).Used Then EmitSketches d, k, mSketch(k).Z, unused
    Next k

    If mNForeign > 0 Then
        MsgBox "This design was made in SolidCraft. SolidCraft 98 has opened what it can build." & vbCrLf & vbCrLf & _
            "These features require SolidCraft 2000 and have been left out:" & vbCrLf & mForeign & vbCrLf & _
            "They're still in the timeline.", vbInformation, App.Title
    End If
    If mFull Then
        MsgBox "The design has more features than a SolidCraft 98 part can hold (" & MAX_FEATURES & ")." & vbCrLf & _
            "The rest have been left out.", vbExclamation, App.Title
    End If
    ImportSolidCraft = True
    Exit Function
Failed:
    If fh <> 0 Then Close #fh
    MsgBox "Can't read '" & sPath & "' as a SolidCraft design." & vbCrLf & vbCrLf & _
        "Run-time error '" & Err.Number & "':" & vbCrLf & Err.Description, vbExclamation, App.Title
End Function

Private Function StripBom(ByVal s As String) As String
    If Left$(s, 1) = ChrW$(&HFEFF) Then StripBom = Mid$(s, 2) Else StripBom = s
End Function

Private Function PrettyType(ByVal s As String) As String
    s = Replace(s, "_", " ")
    PrettyType = UCase$(Left$(s, 1)) & Mid$(s, 2)
End Function

' ---- adding features ----

Private Function AddRaw(d As TDesign, f As TFeature, ByVal sName As String) As Integer
    If d.Count >= MAX_FEATURES Then
        mFull = True
        Exit Function
    End If
    d.Count = d.Count + 1
    f.Name = sName
    d.Features(d.Count) = f
    AddRaw = d.Count
End Function

' A feature SolidCraft 98 can't build: it goes in the timeline as it is.
Private Sub Foreign(d As TDesign, ByVal fNode As Long, ByVal sWhat As String, ByVal sWhy As String)
    Dim f As TFeature, sName As String
    sName = JStr(JGet(fNode, "name"))
    If Len(sName) = 0 Then sName = sWhat
    f.Kind = FK_FOREIGN
    f.Info = sWhat
    AddRaw d, f, sName
    mNForeign = mNForeign + 1
    If mNForeign <= 12 Then
        mForeign = mForeign & "    " & sName & " (" & LCase$(sWhat) & IIf(Len(sWhy) > 0, ": " & sWhy, "") & ")" & vbCrLf
    ElseIf mNForeign = 13 Then
        mForeign = mForeign & "    ...and more." & vbCrLf
    End If
End Sub

' ---- parameters and expressions ----

Private Sub LoadParams(ByVal ps As Long)
    Dim i As Long, p As Long
    mNParam = JCount(ps)
    ReDim mParamName(0 To mNParam)
    ReDim mParamExpr(0 To mNParam)
    For i = 0 To mNParam - 1
        p = JItem(ps, i)
        mParamName(i) = JStr(JGet(p, "name"))
        mParamExpr(i) = JStr(JGet(p, "expr"))
    Next i
End Sub

' The value of an expression like "6", "12 mm", "d1 / 2", "90 deg".
' ok goes False when it uses something we don't know.
Private Function EvalExpr(ByVal s As String, ok As Boolean, Optional ByVal depth As Integer = 0) As Double
    Dim out As String, i As Long, ch As String, j As Long, word As String, k As Integer, v As Double
    ok = False
    If depth > 20 Then Exit Function
    s = Replace(s, ChrW$(176), "")             ' the degree sign
    i = 1
    Do While i <= Len(s)
        ch = Mid$(s, i, 1)
        If ch Like "[A-Za-z_]" Then
            j = i
            Do While j <= Len(s)
                If Mid$(s, j, 1) Like "[A-Za-z0-9_]" Then j = j + 1 Else Exit Do
            Loop
            word = Mid$(s, i, j - i)
            Select Case LCase$(word)
            Case "mm", "deg", "degree", "degrees"
                ' units the numbers are already in
            Case "cm": out = out & "*10"
            Case "m": out = out & "*1000"
            Case "in", "inch": out = out & "*25.4"
            Case "rad": out = out & "*57.2957795130823"
            Case "pi": out = out & "3.14159265358979"
            Case Else
                For k = 0 To mNParam - 1
                    If mParamName(k) = word Then Exit For
                Next k
                If k >= mNParam Then Exit Function
                v = EvalExpr(mParamExpr(k), ok, depth + 1)
                If Not ok Then Exit Function
                out = out & "(" & Trim$(Str$(v)) & ")"
            End Select
            i = j
        Else
            out = out & ch
            i = i + 1
        End If
    Loop
    On Error GoTo Bad
    EvalExpr = Evaluate(out)
    ok = True
Bad:
End Function

' A number or expression node (SolidCraft writes dimensions as strings).
Private Function NodeValue(ByVal n As Long, ok As Boolean) As Double
    If JKind(n) = JS_NUM Then
        NodeValue = JNum(n)
        ok = True
    ElseIf JKind(n) = JS_STR Then
        NodeValue = EvalExpr(JStr(n), ok)
    Else
        ok = False
    End If
End Function

' ---- sketches ----

Private Sub ReadSketch(d As TDesign, ByVal f As Long)
    Dim s As TSketchInfo, plane As Long, pl As Long, sk As Long, pts As Long, curves As Long
    Dim px() As Double, py() As Double, np As Long, i As Long, c As Long, sType As String
    Dim nLine As Integer, nArc As Integer, ok As Boolean, v As Double

    s.Id = JNum(JGet(f, "id"))
    s.Name = JStr(JGet(f, "name"))
    s.Ok = True
    ReDim s.Profiles(0 To 7)

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
        If Not (Near(JNum(JItem(JGet(pl, "x_dir"), 0)), 1) And Near(JNum(JItem(JGet(pl, "y_dir"), 1)), 1)) Then
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

    ' the points, in world X and Y
    sk = JGet(f, "sketch")
    pts = JGet(sk, "points")
    np = JCount(pts)
    ReDim px(0 To IIf(np > 0, np - 1, 0)): ReDim py(0 To IIf(np > 0, np - 1, 0))
    For i = 0 To np - 1
        px(i) = s.OX + JNum(JItem(JGet(JItem(pts, i), "pos"), 0))
        py(i) = s.OY + JNum(JItem(JGet(JItem(pts, i), "pos"), 1))
    Next i

    ' circles are profiles of their own; lines and arcs have to make one rectangle
    curves = JGet(sk, "curves")
    Dim minX As Double, maxX As Double, minY As Double, maxY As Double, rr As Double, a As Long, b As Long
    minX = 1E+30: minY = 1E+30: maxX = -1E+30: maxY = -1E+30: rr = -1
    For i = 0 To JCount(curves) - 1
        c = JItem(curves, i)
        If Not JBool(JGet(c, "construction")) And JGet(c, "link") = 0 Then
            sType = JStr(JGet(c, "type"))
            Select Case sType
            Case "circle"
                AddProfile s, PK_CIRCLE, px(JNum(JGet(c, "c"))), py(JNum(JGet(c, "c"))), JNum(JGet(c, "r")), 0, 0
            Case "line"
                a = JNum(JGet(c, "a")): b = JNum(JGet(c, "b"))
                If Not (Near(px(a), px(b)) Or Near(py(a), py(b))) Then NotOk s, "a line that isn't horizontal or vertical"
                GrowBox px(a), py(a), minX, maxX, minY, maxY
                GrowBox px(b), py(b), minX, maxX, minY, maxY
                nLine = nLine + 1
            Case "arc"
                a = JNum(JGet(c, "a")): b = JNum(JGet(c, "c"))
                v = Sqr((px(a) - px(b)) ^ 2 + (py(a) - py(b)) ^ 2)
                If rr >= 0 And Not Near(v, rr) Then NotOk s, "corners of different sizes"
                rr = v
                nArc = nArc + 1
            Case Else
                NotOk s, "a " & sType
            End Select
        End If
    Next i
    If nLine > 0 Or nArc > 0 Then
        If nLine = 4 And (nArc = 0 Or nArc = 4) Then
            If nArc = 0 Then rr = 0
            ' with rounded corners, the straight sides stop short of the box: widen it
            If rr > 0 Then ReboxRounded px, py, curves, minX, maxX, minY, maxY
            AddProfile s, PK_RECT, minX, minY, maxX - minX, maxY - minY, rr
        Else
            NotOk s, "a shape that isn't a rectangle or a circle"
        End If
    End If
    If s.NProfiles = 0 And s.Ok Then NotOk s, "nothing SolidCraft 98 can draw"
    If s.Ok Then FindHoles s

    If mNSketch > UBound(mSketch) Then ReDim Preserve mSketch(0 To UBound(mSketch) * 2 + 1)
    mSketch(mNSketch) = s
    mNSketch = mNSketch + 1
End Sub

' A rounded rectangle's box is the extent of its arcs' far sides: use the arc
' centres plus the radius.
Private Sub ReboxRounded(px() As Double, py() As Double, ByVal curves As Long, minX As Double, maxX As Double, minY As Double, maxY As Double)
    Dim i As Long, c As Long, cx As Double, cy As Double, r As Double, a As Long
    For i = 0 To JCount(curves) - 1
        c = JItem(curves, i)
        If JStr(JGet(c, "type")) = "arc" And Not JBool(JGet(c, "construction")) And JGet(c, "link") = 0 Then
            cx = px(JNum(JGet(c, "c"))): cy = py(JNum(JGet(c, "c")))
            a = JNum(JGet(c, "a"))
            r = Sqr((px(a) - cx) ^ 2 + (py(a) - cy) ^ 2)
            GrowBox cx - r, cy - r, minX, maxX, minY, maxY
            GrowBox cx + r, cy + r, minX, maxX, minY, maxY
        End If
    Next i
End Sub

Private Sub NotOk(s As TSketchInfo, ByVal sWhy As String)
    If s.Ok Then
        s.Ok = False
        s.Why = sWhy
    End If
End Sub

' Floating-point dust from the source (5.9999999999999964) back to the round number.
Private Function Snap(ByVal v As Double) As Double
    Snap = Round(v, 6)
    If Abs(Snap) < 0.000001 Then Snap = 0
End Function

Private Function Near(ByVal a As Double, ByVal b As Double) As Boolean
    Near = Abs(a - b) < EPS
End Function

Private Sub GrowBox(ByVal x As Double, ByVal y As Double, minX As Double, maxX As Double, minY As Double, maxY As Double)
    If x < minX Then minX = x
    If x > maxX Then maxX = x
    If y < minY Then minY = y
    If y > maxY Then maxY = y
End Sub

Private Sub AddProfile(s As TSketchInfo, ByVal kind As Integer, ByVal x As Double, ByVal y As Double, _
                       ByVal w As Double, ByVal h As Double, ByVal r As Double)
    If s.NProfiles > UBound(s.Profiles) Then ReDim Preserve s.Profiles(0 To UBound(s.Profiles) * 2 + 1)
    With s.Profiles(s.NProfiles)
        .Kind = kind
        .X = x: .Y = y: .W = w: .H = h: .R = r
        .Parent = -1
    End With
    s.NProfiles = s.NProfiles + 1
End Sub

' A circle inside another outline is a hole in it. One level deep.
Private Sub FindHoles(s As TSketchInfo)
    Dim i As Integer, j As Integer, t As TFeature
    For i = 0 To s.NProfiles - 1
        If s.Profiles(i).Kind = PK_CIRCLE Then
            For j = 0 To s.NProfiles - 1
                If j <> i And s.Profiles(j).Parent = -1 Then
                    ProfileAsFeature s.Profiles(j), t
                    If ProfileContains(t, s.Profiles(i).X, s.Profiles(i).Y, s.Profiles(i).W) Then
                        If Not (s.Profiles(j).Kind = PK_CIRCLE And s.Profiles(j).W <= s.Profiles(i).W) Then
                            s.Profiles(i).Parent = j
                            Exit For
                        End If
                    End If
                End If
            Next j
        End If
    Next i
    ' an outline can't also be a hole: only one level
    For i = 0 To s.NProfiles - 1
        If s.Profiles(i).Parent >= 0 Then
            If s.Profiles(s.Profiles(i).Parent).Parent >= 0 Then NotOk s, "islands inside holes"
        End If
    Next i
End Sub

Private Sub ProfileAsFeature(p As TProfile, t As TFeature)
    If p.Kind = PK_CIRCLE Then
        t.Kind = FK_SKETCH_CIRCLE
        t.X = p.X: t.Y = p.Y: t.P1 = p.W
    Else
        t.Kind = FK_SKETCH_RECT
        t.X = p.X: t.Y = p.Y: t.P1 = p.W: t.P2 = p.H: t.P3 = p.R
    End If
End Sub

Private Function FindSketch(ByVal id As Long) As Integer
    Dim i As Integer
    FindSketch = -1
    For i = 0 To mNSketch - 1
        If mSketch(i).Id = id Then
            FindSketch = i
            Exit Function
        End If
    Next i
End Function

' The SolidCraft 98 extrude whose top is at height z and that the circle fits on.
Private Function ExtrudeWithTopAt(d As TDesign, ByVal z As Double, ByVal x As Double, ByVal y As Double, ByVal r As Double) As Integer
    Dim i As Integer, z0 As Double, z1 As Double
    For i = d.Count To 1 Step -1
        If d.Features(i).Kind = FK_EXTRUDE Then
            If RefOk(d, i) Then
                ExtrudeRange d, i, z0, z1
                If Abs(z1 - z) < EPS Then
                    If ProfileContains(d.Features(d.Features(i).Ref), x, y, r) Then
                        ExtrudeWithTopAt = i
                        Exit Function
                    End If
                End If
            End If
        End If
    Next i
End Function

' Adds one SolidCraft 98 sketch per outline of sketch k, at height z, and
' puts their indices in idx(). A sketch on a face sits on the extrude under
' it, so it follows that extrude when it's edited.
Private Sub EmitSketches(d As TDesign, ByVal k As Integer, ByVal z As Double, idx() As Integer)
    Dim i As Integer, f As TFeature, blank As TFeature, n As Integer, base As Integer, sName As String, t As TFeature
    Dim z0 As Double, z1 As Double
    ReDim idx(0 To CountOutlines(k))
    mSketch(k).Used = True
    For i = 0 To mSketch(k).NProfiles - 1
        If mSketch(k).Profiles(i).Parent = -1 Then
            f = blank
            ProfileAsFeature mSketch(k).Profiles(i), f
            base = 0
            If mSketch(k).OnFace And Abs(z - mSketch(k).Z) < EPS Then
                ProfileAsFeature mSketch(k).Profiles(i), t
                base = ExtrudeWithTopAt(d, z, t.X, t.Y, 0)
            End If
            If base > 0 Then
                ExtrudeRange d, base, z0, z1
                f.Ref = base
                f.Z = Snap(z - z1)
            Else
                f.Z = Snap(z)
            End If
            n = n + 1
            sName = mSketch(k).Name
            If CountOutlines(k) > 1 Then sName = Left$(sName, 20) & " " & n
            idx(n - 1) = AddRaw(d, f, sName)
        End If
    Next i
End Sub

Private Function CountOutlines(ByVal k As Integer) As Integer
    Dim i As Integer
    For i = 0 To mSketch(k).NProfiles - 1
        If mSketch(k).Profiles(i).Parent = -1 Then CountOutlines = CountOutlines + 1
    Next i
End Function

' The outline indices of sketch k, in the order EmitSketches adds them.
Private Function OutlineProfile(ByVal k As Integer, ByVal n As Integer) As Integer
    Dim i As Integer, c As Integer
    For i = 0 To mSketch(k).NProfiles - 1
        If mSketch(k).Profiles(i).Parent = -1 Then
            If c = n Then
                OutlineProfile = i
                Exit Function
            End If
            c = c + 1
        End If
    Next i
End Function

' ---- extrude, revolve, hole ----

Private Sub ImportExtrude(d As TDesign, ByVal f As Long)
    Dim k As Integer, ext As Long, dist As Double, ok As Boolean, sDir As String, sOp As String
    Dim z As Double, idx() As Integer, n As Integer, i As Integer, e As TFeature, j As Integer, blank As TFeature
    Dim sName As String, hole As TFeature, p As TProfile, through As Boolean

    sName = JStr(JGet(f, "name"))
    k = FindSketch(JNum(JGet(f, "sketch")))
    If k < 0 Then Foreign d, f, "Extrude", "not from a sketch": Exit Sub
    If Not mSketch(k).Ok Then
        mSketch(k).Used = True
        Foreign d, f, "Extrude", "its sketch has " & mSketch(k).Why
        Exit Sub
    End If
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
        Foreign d, f, "Extrude", PrettyType(sOp)
        Exit Sub
    End Select
    If through Then Foreign d, f, "Extrude", "through all": Exit Sub

    z = mSketch(k).Z
    Select Case sDir
    Case "negative": z = z - dist
    Case "symmetric": z = z - dist / 2
    End Select
    n = CountOutlines(k)
    EmitSketches d, k, z, idx
    For i = 0 To n - 1
        If idx(i) = 0 Then Exit Sub
        e = blank
        e.Kind = FK_EXTRUDE
        e.Ref = idx(i)
        e.P1 = dist
        j = AddRaw(d, e, IIf(n > 1, Left$(sName, 20) & " " & (i + 1), sName))
        If j = 0 Then Exit Sub
        ' circles inside this outline are holes right through it
        p = mSketch(k).Profiles(OutlineProfile(k, i))
        Dim h As Integer, c As Integer
        For h = 0 To mSketch(k).NProfiles - 1
            If mSketch(k).Profiles(h).Parent = OutlineProfile(k, i) Then
                c = c + 1
                hole = blank
                hole.Kind = FK_HOLE
                hole.Ref = j
                hole.X = mSketch(k).Profiles(h).X
                hole.Y = mSketch(k).Profiles(h).Y
                hole.P1 = mSketch(k).Profiles(h).W * 2
                hole.P2 = dist                    ' through this body, and no further
                AddRaw d, hole, Left$(sName, 17) & " hole " & c
            End If
        Next h
    Next i
End Sub

' A cut extrude of circles is a set of holes into the body underneath.
Private Sub ImportCut(d As TDesign, ByVal f As Long, ByVal k As Integer, ByVal dist As Double, ByVal through As Boolean)
    Dim i As Integer, p As TProfile, t As Integer, c As Integer, hole As TFeature, blank As TFeature
    Dim targets() As Integer, n As Integer, sName As String
    sName = JStr(JGet(f, "name"))
    n = mSketch(k).NProfiles
    ReDim targets(0 To n)
    ' check every circle first: all or nothing
    For i = 0 To n - 1
        p = mSketch(k).Profiles(i)
        If p.Kind <> PK_CIRCLE Then mSketch(k).Used = True: Foreign d, f, "Extrude (cut)", "a cut that isn't round": Exit Sub
        targets(i) = ExtrudeWithTopAt(d, mSketch(k).Z, p.X, p.Y, p.W)
        If targets(i) = 0 Then mSketch(k).Used = True: Foreign d, f, "Extrude (cut)", "not into the top of a block": Exit Sub
    Next i
    mSketch(k).Used = True
    For i = 0 To n - 1
        p = mSketch(k).Profiles(i)
        hole = blank
        hole.Kind = FK_HOLE
        hole.Ref = targets(i)
        hole.X = p.X: hole.Y = p.Y
        hole.P1 = p.W * 2
        If Not through Then hole.P2 = dist
        c = c + 1
        If AddRaw(d, hole, IIf(n > 1, Left$(sName, 20) & " " & c, sName)) = 0 Then Exit Sub
    Next i
End Sub

Private Sub ImportRevolve(d As TDesign, ByVal f As Long)
    Dim k As Integer, ax As Long, ang As Double, ok As Boolean, idx() As Integer, n As Integer, i As Integer
    Dim e As TFeature, blank As TFeature, sName As String, p As TProfile
    sName = JStr(JGet(f, "name"))
    k = FindSketch(JNum(JGet(f, "sketch")))
    If k < 0 Then Foreign d, f, "Revolve", "not from a sketch": Exit Sub
    If Not mSketch(k).Ok Then
        mSketch(k).Used = True
        Foreign d, f, "Revolve", "its sketch has " & mSketch(k).Why
        Exit Sub
    End If
    ax = JGet(f, "axis")
    If JStr(JGet(ax, "type")) <> "sketch_axis" Or JStr(JGet(ax, "axis")) <> "y" Then
        Foreign d, f, "Revolve", "about an axis other than the sketch's Y": Exit Sub
    End If
    If Not Near(mSketch(k).OX, 0) Then Foreign d, f, "Revolve", "about an axis off the origin": Exit Sub
    If JStr(JGet(f, "operation")) = "cut" Or JStr(JGet(f, "operation")) = "intersect" Then
        Foreign d, f, "Revolve", PrettyType(JStr(JGet(f, "operation"))): Exit Sub
    End If
    If JStr(JGet(f, "direction")) = "symmetric" Or JGet(f, "angle2") > 0 Or JGet(f, "to") > 0 Then
        Foreign d, f, "Revolve", "a two-sided or symmetric angle": Exit Sub
    End If
    If JStr(JGet(JGet(f, "profiles"), "type")) <> "all" Then Foreign d, f, "Revolve", "only some of its sketch's profiles": Exit Sub
    If JGet(f, "angle") > 0 Then
        ang = NodeValue(JGet(f, "angle"), ok)
        If Not ok Then Foreign d, f, "Revolve", "an angle SolidCraft 98 can't work out": Exit Sub
    Else
        ang = 360
    End If
    If ang = 0 Or Abs(ang) > 360 Then Foreign d, f, "Revolve", "an angle over 360 degrees": Exit Sub
    For i = 0 To mSketch(k).NProfiles - 1
        p = mSketch(k).Profiles(i)
        If p.Parent >= 0 Then Foreign d, f, "Revolve", "a profile with a hole in it": Exit Sub
        If p.Kind = PK_CIRCLE Then
            If p.X - p.W < -EPS And p.X + p.W > EPS Then Foreign d, f, "Revolve", "a profile across the axis": Exit Sub
        Else
            If p.X < -EPS And p.X + p.W > EPS Then Foreign d, f, "Revolve", "a profile across the axis": Exit Sub
        End If
    Next i
    n = CountOutlines(k)
    EmitSketches d, k, mSketch(k).Z, idx
    For i = 0 To n - 1
        If idx(i) = 0 Then Exit Sub
        e = blank
        e.Kind = FK_REVOLVE
        e.Ref = idx(i)
        e.P1 = -ang          ' SolidCraft turns +X towards +Z; SolidCraft 98 the other way
        If AddRaw(d, e, IIf(n > 1, Left$(sName, 20) & " " & (i + 1), sName)) = 0 Then Exit Sub
    Next i
End Sub

Private Sub ImportHole(d As TDesign, ByVal f As Long)
    Dim pos As Long, dirn As Long, x As Double, y As Double, z As Double, dia As Double, depth As Double
    Dim ok As Boolean, t As Integer, h As TFeature, sKind As String
    pos = JGet(f, "position")
    If JKind(pos) <> JS_ARR Then Foreign d, f, "Hole", "placed on sketch points": Exit Sub
    dirn = JGet(f, "direction")
    If dirn > 0 Then
        If Not (Near(JNum(JItem(dirn, 0)), 0) And Near(JNum(JItem(dirn, 1)), 0) And JNum(JItem(dirn, 2)) < 0) Then
            Foreign d, f, "Hole", "not straight down": Exit Sub
        End If
    End If
    sKind = JStr(JGet(JGet(f, "hole"), "type"))
    If sKind <> "" And sKind <> "simple" And sKind <> "drilled" Then Foreign d, f, "Hole", PrettyType(sKind): Exit Sub
    If JGet(f, "diameter") = 0 Then Foreign d, f, "Hole", "a clearance or tapped size": Exit Sub
    dia = NodeValue(JGet(f, "diameter"), ok)
    If Not ok Or dia <= 0 Then Foreign d, f, "Hole", "a diameter SolidCraft 98 can't work out": Exit Sub
    If JGet(f, "depth") > 0 Then
        depth = NodeValue(JGet(f, "depth"), ok)
        If Not ok Or depth <= 0 Then Foreign d, f, "Hole", "a depth SolidCraft 98 can't work out": Exit Sub
    End If
    If JGet(f, "to") > 0 Then Foreign d, f, "Hole", "drilled to an object": Exit Sub
    x = NodeValue(JItem(pos, 0), ok): y = NodeValue(JItem(pos, 1), ok): z = NodeValue(JItem(pos, 2), ok)
    t = ExtrudeWithTopAt(d, z, x, y, dia / 2)
    If t = 0 Then Foreign d, f, "Hole", "not on the top of a block SolidCraft 98 built": Exit Sub
    h.Kind = FK_HOLE
    h.Ref = t
    h.X = x: h.Y = y
    h.P1 = dia
    h.P2 = depth
    AddRaw d, h, JStr(JGet(f, "name"))
End Sub
