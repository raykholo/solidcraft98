' part.bas - a part window: feature tree on the left, the view (wireframe or
' shaded) on the right, timeline along the bottom. The designs themselves
' are kept here too (modDoc in the Windows version).

Const MAX_DOCS = 16

Dim Shared Docs(1 To MAX_DOCS) As TDesign
Dim Shared DocPath(1 To MAX_DOCS) As String
Dim Shared DocDirty(1 To MAX_DOCS) As Boolean
Dim Shared DocInUse(1 To MAX_DOCS) As Boolean
Dim Shared mUntitled As Long

Function NewDocSlot() As Long
    Dim i As Long
    For i = 1 To MAX_DOCS
        If Not DocInUse(i) Then
            mUntitled += 1
            NewDesign Docs(i), "Part" & mUntitled
            DocPath(i) = "": DocDirty(i) = False: DocInUse(i) = True
            Return i
        End If
    Next
    Return 0
End Function

Sub FreeDocSlot(ByVal i As Long)
    If i >= 1 And i <= MAX_DOCS Then DocInUse(i) = False
End Sub

Function DocTitle(ByVal i As Long) As String
    Dim As String t = Docs(i).Title
    If DocDirty(i) Then t &= " *"
    Return t
End Function

' ---- part windows ----

Const TREE_W = 160
Const TL_H = 116
Const TITLE_H = 18
Const ROW_H = 16
Const LV_ROW_H = 15
Const LV_HEAD_H = 18

Type TPart
    inUse As Boolean
    slot As Long
    x As Long
    y As Long
    w As Long
    h As Long
    minimized As Boolean
    v As TView
    edges As TEdge Ptr
    edgeN As Long
    tris As TTri Ptr
    triN As Long
    faces As Long Ptr
    meshOk As Boolean
    viewImg As Any Ptr        ' what the view shows
    shadeImg As Any Ptr       ' the finished shaded picture, revealed into viewImg
    imgW As Long
    imgH As Long
    revealing As Boolean
    revealStart As Double
    revealTotal As Double
    revealRows As Long
    selected As Long          ' feature picked in the tree or timeline
    focusTree As Boolean
    expanded(0 To MAX_FEATURES) As Boolean
    originOpen As Boolean
    treeTop As Long
    listTop As Long
    dragKind As Long          ' 0 none, 1 orbit, 2 pan, 3 move window, 4 resize
    dragX As Long
    dragY As Long
    moved As Boolean
    lastDraw As Double
    frames As Long
    frameStart As Double
    regenTries As Long
    spinning As Boolean
End Type

Dim Shared Parts(1 To MAX_DOCS) As TPart
Dim Shared ZOrder(0 To MAX_DOCS) As Long     ' part numbers, bottom to top
Dim Shared ZCount As Long
Dim Shared MdiX As Long, MdiY As Long, MdiW As Long, MdiH As Long
Dim Shared ViewShaded As Boolean

Declare Sub SetStatus(ByRef t As String)
Declare Sub SetFps(ByRef t As String)
Declare Function OrbitFrameInterval() As Double
Declare Function SolverConverges(ByRef nTries As Long) As Boolean
Declare Sub EditFeature(ByVal p As Long, ByVal i As Long)

Function ActivePart() As Long
    If ZCount = 0 Then Return 0
    Return ZOrder(ZCount - 1)
End Function

Sub BringToFront(ByVal p As Long)
    Dim As Long i, j
    For i = 0 To ZCount - 1
        If ZOrder(i) = p Then
            For j = i To ZCount - 2: ZOrder(j) = ZOrder(j + 1): Next
            ZOrder(ZCount - 1) = p
            Exit Sub
        End If
    Next
End Sub

' Client area of the window: below the title, inside the border.
Sub ClientRect(ByVal p As Long, ByRef cx As Long, ByRef cy As Long, ByRef cw As Long, ByRef ch As Long)
    With Parts(p)
        cx = .x + 4: cy = .y + 4 + TITLE_H + 1
        cw = .w - 8: ch = .h - 8 - TITLE_H - 1
    End With
End Sub

Sub ViewRect(ByVal p As Long, ByRef vx As Long, ByRef vy As Long, ByRef vw As Long, ByRef vh As Long)
    Dim As Long cx, cy, cw, ch
    ClientRect p, cx, cy, cw, ch
    vx = cx + TREE_W + 4 + 2: vy = cy + 2
    vw = cw - TREE_W - 4 - 4: vh = ch - TL_H - 4 - 4
    If vw < 16 Then vw = 16
    If vh < 16 Then vh = 16
End Sub

Sub FreeMesh(ByVal p As Long)
    With Parts(p)
        If .tris Then Deallocate .tris: .tris = 0
        If .faces Then Deallocate .faces: .faces = 0
        .triN = 0: .meshOk = False
    End With
End Sub

Sub EnsureImages(ByVal p As Long)
    Dim As Long vx, vy, vw, vh
    ViewRect p, vx, vy, vw, vh
    With Parts(p)
        If .viewImg = 0 Or .imgW <> vw Or .imgH <> vh Then
            If .viewImg Then ImageDestroy .viewImg
            If .shadeImg Then ImageDestroy .shadeImg
            .viewImg = ImageCreate(vw, vh, &hFFE0E0E0, 32)
            .shadeImg = ImageCreate(vw, vh, &hFFE0E0E0, 32)
            .imgW = vw: .imgH = vh
        End If
    End With
End Sub

Sub DrawLabel(ByVal p As Long)
    With Parts(p)
        If Docs(.slot).Count = 0 Then
            Text 6, 4, "Empty part. Sketch a rectangle (R) or a circle (C) to begin.", &hFF404040
        ElseIf ViewShaded And Not .revealing And .tris <> 0 And (.dragKind <> 1 And .dragKind <> 2) And Not .spinning Then
            Text 6, 4, "Shaded, " & .triN & " triangles", &hFF404040
        Else
            Text 6, 4, .edgeN & " edges", &hFF404040
        End If
    End With
End Sub

' Draws the view: wireframe, or (when shaded, and the view isn't moving)
' starts a shaded render that the timer reveals a few rows at a time.
Sub PartRedraw(ByVal p As Long)
    Dim As Long i
    EnsureImages p
    With Parts(p)
        Dim As Long vw = .imgW, vh = .imgH
        If ViewShaded And .dragKind <> 1 And .dragKind <> 2 And Not .spinning And Docs(.slot).Count > 0 Then
            If Not .meshOk Then
                Dim t() As TTri, g() As Long, sErr As String
                FreeMesh p
                .triN = MeshDesign(Docs(.slot), t(), 32, sErr)
                If .triN > 0 Then
                    FaceGroups t(), .triN, g()
                    .tris = Allocate(.triN * SizeOf(TTri))
                    .faces = Allocate(.triN * SizeOf(Long))
                    For i = 0 To .triN - 1: .tris[i] = t(i): .faces[i] = g(i): Next
                End If
                .meshOk = True
            End If
            ' the background, now; the shaded picture, revealed over it
            SurfFromImage S, .viewImg
            DrawScene .v, vw, vh, .edges, 0
            SurfFromImage S, .shadeImg
            DrawScene .v, vw, vh, .edges, 0
            If .triN > 0 Then RenderShaded .v, .tris, .triN, .faces, Docs(.slot)
            ' sketches nothing is built on yet, drawn over the top
            For i = 0 To .edgeN - 1
                If .edges[i].Col = COL_SKETCH Or .edges[i].Col = COL_AXIS Then DrawEdge .v, vw, vh, .edges[i]
            Next
            Text 6, 4, "Shaded, " & .triN & " triangles", &hFF404040
            .revealing = True
            .revealStart = Timer
            .revealTotal = IIf(Turbo, 4.0, 1.5)
            .revealRows = 0
        Else
            .revealing = False
            SurfFromImage S, .viewImg
            DrawScene .v, vw, vh, .edges, .edgeN
            DrawLabel p
        End If
    End With
    NeedRedraw = True
End Sub

' Copies the rows that are due from the shaded picture into the view.
Sub PartRevealTick(ByVal p As Long)
    Const BAND = 6
    With Parts(p)
        If Not .revealing Then Exit Sub
        Dim As Double t = (Timer - .revealStart) / .revealTotal
        Dim As Long due = IIf(t >= 1, .imgH, CLng(Int(t * .imgH / BAND) * BAND))
        If due <= .revealRows Then Exit Sub
        Dim As Long w, h, bypp, pitch
        Dim As Any Ptr a, b
        ImageInfo .viewImg, w, h, bypp, pitch, a
        ImageInfo .shadeImg, w, h, bypp, pitch, b
        Dim As Long r
        For r = .revealRows To due - 1
            Dim As ULong Ptr pa = a + r * pitch, pb = b + r * pitch
            Dim As Long k
            For k = 0 To w - 1: pa[k] = pb[k]: Next
        Next
        .revealRows = due
        If due >= .imgH Then
            .revealing = False
            If Turbo Then
                SetStatus "Shaded at Turbo quality in " & FmtN(Timer - .revealStart, 1) & " seconds. Every pixel was rendered twice, to be sure."
            Else
                SetStatus "Shaded in " & FmtN(Timer - .revealStart, 1) & " seconds."
            End If
        Else
            SetStatus IIf(Turbo, "Rendering at Turbo quality... ", "Rendering... ") & Int(100 * due / .imgH) & "%"
        End If
        NeedRedraw = True
    End With
End Sub

' Regenerates the edges from the design, and redraws.
Sub PartRefreshAll(ByVal p As Long, ByVal bFit As Boolean)
    Dim e() As TEdge
    Dim As Long i
    With Parts(p)
        If .selected > Docs(.slot).Count Then .selected = 0
        Dim As Long n = Regenerate(Docs(.slot), e())
        If .edges Then Deallocate .edges
        .edges = Allocate((n + 1) * SizeOf(TEdge))
        For i = 0 To n - 1: .edges[i] = e(i): Next
        .edgeN = n
        FreeMesh p
        EnsureImages p
        If bFit Then FitView .v, .imgW, .imgH, .edges, .edgeN
    End With
    PartRedraw p
End Sub

Sub PartViewIso(ByVal p As Long)
    ResetView Parts(p).v
    FitView Parts(p).v, Parts(p).imgW, Parts(p).imgH, Parts(p).edges, Parts(p).edgeN
    PartRedraw p
    SetStatus "Isometric view."
End Sub

Sub PartZoomFit(ByVal p As Long)
    FitView Parts(p).v, Parts(p).imgW, Parts(p).imgH, Parts(p).edges, Parts(p).edgeN
    PartRedraw p
End Sub

Sub PartRegen(ByVal p As Long)
    If Not SolverConverges(Parts(p).regenTries) Then
        SetStatus "Regenerate: the solver did not converge (attempt " & Parts(p).regenTries & ")."
        Exit Sub
    End If
    PartRefreshAll p, False
    SetStatus "Regenerated " & Docs(Parts(p).slot).Count & " features, " & Parts(p).edgeN & " edges."
End Sub

Sub PartZoomBy(ByVal p As Long, ByVal k As Double)
    With Parts(p).v
        .Zoom *= k: .PanX *= k: .PanY *= k
    End With
    PartRedraw p
End Sub

' Opens a window for document slot. The first part fills the area; later
' ones cascade.
Function OpenPart(ByVal slot As Long) As Long
    Dim As Long p, i, n
    For p = 1 To MAX_DOCS
        If Not Parts(p).inUse Then Exit For
    Next
    If p > MAX_DOCS Then Return 0
    Dim blank As TPart
    Parts(p) = blank
    With Parts(p)
        .inUse = True: .slot = slot
        For i = 0 To MAX_FEATURES: .expanded(i) = True: Next
        ResetView .v
        n = ZCount
        If n = 0 Then
            .x = MdiX: .y = MdiY: .w = MdiW: .h = MdiH
        Else
            .x = MdiX + n * 24: .y = MdiY + n * 24: .w = MdiW * 85 \ 100: .h = MdiH * 85 \ 100
        End If
    End With
    ZOrder(ZCount) = p: ZCount += 1
    PartRefreshAll p, True
    Return p
End Function

Sub ClosePartWindow(ByVal p As Long)
    Dim As Long i, j
    With Parts(p)
        FreeMesh p
        If .edges Then Deallocate .edges: .edges = 0
        If .viewImg Then ImageDestroy .viewImg: .viewImg = 0
        If .shadeImg Then ImageDestroy .shadeImg: .shadeImg = 0
        FreeDocSlot .slot
        .inUse = False
    End With
    For i = 0 To ZCount - 1
        If ZOrder(i) = p Then
            For j = i To ZCount - 2: ZOrder(j) = ZOrder(j + 1): Next
            ZCount -= 1
            Exit For
        End If
    Next
    NeedRedraw = True
End Sub

' Asks before closing a part with unsaved changes. False: don't close.
Function PartQueryClose(ByVal p As Long) As Boolean
    Dim As Long s = Parts(p).slot
    If DocDirty(s) Then
        Select Case MsgBox("Save changes to " & Docs(s).Title & "?", MB_YESNOCANCEL Or MB_QUESTION)
        Case IDYES
            RunCommand "Save"
            If DocDirty(s) Then Return False
        Case IDCANCEL, 0
            Return False
        End Select
    End If
    Return True
End Function

' ---- the tree ----

Type TRow
    text As String
    level As Long
    key As Long          ' feature number, 0 root, -1 origin, -2 a plane
    hasKids As Boolean
    open As Boolean
End Type

Dim Shared TreeRows(0 To 200) As TRow
Dim Shared TreeRowN As Long

Sub AddRow(ByRef t As String, ByVal level As Long, ByVal key As Long, ByVal kids As Boolean, ByVal op As Boolean)
    If TreeRowN > 200 Then Exit Sub
    TreeRows(TreeRowN).text = t: TreeRows(TreeRowN).level = level: TreeRows(TreeRowN).key = key
    TreeRows(TreeRowN).hasKids = kids: TreeRows(TreeRowN).open = op
    TreeRowN += 1
End Sub

' The sketch an extrude or revolve uses hangs under it, the way people expect.
Function UsesSketch(ByRef d As TDesign, ByVal i As Long) As Long
    If d.F(i).Kind = FK_EXTRUDE Or d.F(i).Kind = FK_REVOLVE Then
        If d.F(i).Ref >= 1 And d.F(i).Ref < i AndAlso IsSketch(d.F(d.F(i).Ref).Kind) Then Return d.F(i).Ref
    End If
    Return 0
End Function

Function NodeText(ByRef d As TDesign, ByVal i As Long) As String
    Dim As String t = d.F(i).Name
    If Not RefOk(d, i) Then t &= " (!)"
    Return t
End Function

Sub BuildTree(ByVal p As Long)
    Dim As Long i, j
    TreeRowN = 0
    With Parts(p)
        Dim As TDesign Ptr d = @Docs(.slot)
        AddRow d->Title, 0, 0, True, True
        AddRow "Origin", 1, -1, True, .originOpen
        If .originOpen Then
            AddRow "Front Plane (XZ)", 2, -2, False, False
            AddRow "Top Plane (XY)", 2, -2, False, False
            AddRow "Right Plane (YZ)", 2, -2, False, False
        End If
        Dim used(0 To MAX_FEATURES) As Boolean
        For i = 1 To d->Count
            j = UsesSketch(*d, i)
            If j Then used(j) = True
        Next
        For i = 1 To d->Count
            If used(i) Then Continue For
            j = UsesSketch(*d, i)
            AddRow NodeText(*d, i), 1, i, j <> 0, .expanded(i)
            If j <> 0 And .expanded(i) Then AddRow NodeText(*d, j), 2, j, False, False
        Next
    End With
End Sub

Sub DrawTree(ByVal p As Long, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal active As Boolean)
    Dim As Long i, rows
    BuildTree p
    Bevel x, y, w, h, BEV_SUNKEN
    Fill x + 2, y + 2, w - 4, h - 4, C_WINDOW
    ClipTo x + 2, y + 2, w - 4, h - 4
    rows = (h - 4) \ ROW_H
    With Parts(p)
        If .treeTop > TreeRowN - rows Then .treeTop = TreeRowN - rows
        If .treeTop < 0 Then .treeTop = 0
        For i = .treeTop To TreeRowN - 1
            Dim As Long ry = y + 4 + (i - .treeTop) * ROW_H
            If ry > y + h Then Exit For
            Dim As Long lx = x + 22 + TreeRows(i).level * 19
            ' dotted lines to the parent
            If TreeRows(i).level > 0 Then
                DotH lx - 10, ry + 7, 10, C_SHADOW
                Dim As Long k
                For k = i - 1 To 0 Step -1
                    If TreeRows(k).level < TreeRows(i).level Then Exit For
                Next
                Dim As Long py0 = y + 4 + (k - .treeTop) * ROW_H + 12
                DotV lx - 10, py0, ry + 7 - py0, C_SHADOW
            End If
            If TreeRows(i).hasKids Then
                ' the +/- box
                Dim As Long bx = lx - 14, by = ry + 3
                Fill bx, by, 9, 9, C_WINDOW: Frame bx, by, 9, 9, C_SHADOW
                HLine bx + 2, by + 4, 5, C_DARK
                If Not TreeRows(i).open Then VLine bx + 4, by + 2, 5, C_DARK
            End If
            Dim As Long tw = TextW(TreeRows(i).text)
            Dim As Boolean sel = (TreeRows(i).key > 0 And TreeRows(i).key = .selected) Or (TreeRows(i).key = 0 And .selected = 0 And .focusTree)
            If sel Then
                Fill lx - 1, ry + 1, tw + 4, 14, IIf(active, C_SEL, C_FACE)
                Text lx + 1, ry + 3, TreeRows(i).text, IIf(active, C_SELTEXT, C_TEXT)
            Else
                Text lx + 1, ry + 3, TreeRows(i).text, C_TEXT
            End If
        Next
    End With
    NoClip
End Sub

' ---- the timeline ----

Dim Shared ColW(0 To 4) As Long = {33, 107, 120, 247, 140}
Dim Shared ColName(0 To 4) As ZString * 12 = {"#", "Feature", "Type", "Parameters", "Status"}

Function TimelineCell(ByRef d As TDesign, ByVal i As Long, ByVal col As Long) As String
    Select Case col
    Case 0: Return Str(i)
    Case 1: Return d.F(i).Name
    Case 2
        If d.F(i).Kind = FK_FOREIGN Then Return d.F(i).Info
        Return KindName(d.F(i).Kind)
    Case 3: Return Describe(d, i)
    Case 4
        If d.F(i).Kind = FK_FOREIGN Then Return "Requires SolidCraft 2000"
        If RefOk(d, i) Then Return "OK"
        Return "Rebuild error"
    End Select
    Return ""
End Function

Sub DrawTimeline(ByVal p As Long, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal active As Boolean)
    Dim As Long i, c, cx, rows
    Dim As TDesign Ptr d = @Docs(Parts(p).slot)
    Bevel x, y, w, h, BEV_SUNKEN
    Fill x + 2, y + 2, w - 4, h - 4, C_WINDOW
    rows = (h - 4 - LV_HEAD_H) \ LV_ROW_H
    Dim As Boolean scroll = d->Count > rows
    Dim As Long iw = w - 4 - IIf(scroll, 16, 0)
    ClipTo x + 2, y + 2, iw, h - 4
    ' the header: a row of buttons
    cx = x + 2
    For c = 0 To 4
        Dim As Long cw = IIf(c = 4, iw - (cx - x - 2), ColW(c))
        If c = 4 And cw < ColW(4) Then cw = ColW(4)
        Fill cx, y + 2, cw, LV_HEAD_H, C_FACE
        Bevel cx, y + 2, cw, LV_HEAD_H, BEV_BUTTON
        Text cx + IIf(c = 0, cw \ 2 - 2, 6), y + 6, ColName(c), C_TEXT
        cx += cw
    Next
    If cx < x + 2 + iw Then Fill cx, y + 2, x + 2 + iw - cx, LV_HEAD_H, C_FACE: Bevel cx, y + 2, x + 2 + iw - cx, LV_HEAD_H, BEV_BUTTON
    With Parts(p)
        If .listTop > d->Count - rows Then .listTop = d->Count - rows
        If .listTop < 0 Then .listTop = 0
        For i = .listTop + 1 To d->Count
            Dim As Long ry = y + 2 + LV_HEAD_H + (i - 1 - .listTop) * LV_ROW_H
            If ry > y + h - 4 Then Exit For
            Dim As Boolean sel = (i = .selected)
            If sel Then Fill x + 2, ry, iw, LV_ROW_H, IIf(active, C_SEL, C_FACE)
            cx = x + 2
            For c = 0 To 4
                Dim As Long cw = IIf(c = 4, iw - (cx - x - 2), ColW(c))
                Dim As String t = Ellipsize(TimelineCell(*d, i, c), cw - 10)
                Text cx + IIf(c = 0, 6, 6), ry + 2, t, IIf(sel And active, C_SELTEXT, C_TEXT)
                cx += cw
            Next
        Next
        ' grid lines
        For i = 0 To rows
            HLine x + 2, y + 2 + LV_HEAD_H + (i + 1) * LV_ROW_H - 1, iw, &hFFE0E0E0
        Next
        cx = x + 2
        For c = 0 To 3
            cx += ColW(c)
            VLine cx - 1, y + 2 + LV_HEAD_H, h - 4 - LV_HEAD_H, &hFFE0E0E0
        Next
    End With
    NoClip
    If scroll Then DrawScrollV x + w - 18, y + 2, h - 4, d->Count, rows, Parts(p).listTop
End Sub

' ---- the window ----

Sub DrawCaptionButton(ByVal x As Long, ByVal y As Long, ByVal kind As Long, ByVal disabled As Boolean)
    ' kind 0 minimise, 1 maximise, 2 close, 3 restore
    Dim As Long i
    Fill x, y, 16, 14, C_FACE: Bevel x, y, 16, 14, BEV_BUTTON
    Dim As ULong c = IIf(disabled, C_SHADOW, C_DARK)
    Select Case kind
    Case 0: Fill x + 4, y + 9, 6, 2, c
    Case 1: Frame x + 3, y + 2, 9, 9, c: HLine x + 3, y + 3, 9, c
    Case 2
        For i = 0 To 5
            Fill x + 4 + i, y + 3 + i, 2, 1, c: Fill x + 9 - i, y + 3 + i, 2, 1, c
        Next
    Case 3
        Frame x + 5, y + 2, 6, 5, c: HLine x + 5, y + 3, 6, c
        Frame x + 3, y + 5, 6, 5, c: HLine x + 3, y + 6, 6, c
    End Select
    If disabled Then
        ' embossed: a white copy one pixel down and right
    End If
End Sub

Sub DrawPartWindow(ByVal p As Long, ByVal active As Boolean)
    Dim As Long cx, cy, cw, ch, vx, vy, vw, vh
    With Parts(p)
        Dim As Long hh = IIf(.minimized, TITLE_H + 8, .h)
        Fill .x, .y, .w, hh, C_FACE
        Bevel .x, .y, .w, hh, BEV_RAISED
        GradientH .x + 4, .y + 4, .w - 8, TITLE_H, IIf(active, C_TITLE1, C_TITLEI1), IIf(active, C_TITLE2, C_TITLEI2)
        DrawIcon .x + 5, .y + 5, "App", 1
        ClipTo .x + 4, .y + 4, .w - 8 - 56, TITLE_H
        Text .x + 24, .y + 7, DocTitle(.slot), IIf(active, C_HILITE, &hFFD4D0C8), True
        NoClip
        Dim As Long bx = .x + .w - 4 - 2 - 16
        DrawCaptionButton bx, .y + 6, 2, False
        DrawCaptionButton bx - 18, .y + 6, IIf(.minimized, 3, 1), Not .minimized
        DrawCaptionButton bx - 34, .y + 6, 0, .minimized
        If .minimized Then Exit Sub
        ClientRect p, cx, cy, cw, ch
        DrawTree p, cx, cy, TREE_W, ch - TL_H - 4, active
        ViewRect p, vx, vy, vw, vh
        Bevel vx - 2, vy - 2, vw + 4, vh + 4, BEV_SUNKEN
        If .viewImg Then
            ' blit the view image
            Dim As Long iw, ih, bypp, pitch, r
            Dim As Any Ptr px
            ImageInfo .viewImg, iw, ih, bypp, pitch, px
            For r = 0 To ih - 1
                If vy + r < S.cy1 Or vy + r > S.cy2 Then Continue For
                Dim As ULong Ptr src = px + r * pitch, dst = S.px + (vy + r) * S.pitch + vx
                Dim As Long k
                For k = 0 To iw - 1
                    If vx + k >= S.cx1 And vx + k <= S.cx2 Then dst[k] = src[k]
                Next
            Next
        End If
        DrawTimeline p, cx, cy + ch - TL_H, cw, TL_H, active
        ' the size grip
        Dim As Long gx = .x + .w - 4, gy = .y + .h - 4, g
        For g = 0 To 2
            DrawLine gx - 3 - g * 4, gy - 1, gx - 1, gy - 3 - g * 4, C_HILITE
            DrawLine gx - 2 - g * 4, gy - 1, gx - 1, gy - 2 - g * 4, C_SHADOW
        Next
    End With
End Sub

' ---- input ----

Function PartHit(ByVal x As Long, ByVal y As Long) As Long
    Dim As Long i
    For i = ZCount - 1 To 0 Step -1
        Dim As Long p = ZOrder(i)
        With Parts(p)
            Dim As Long hh = IIf(.minimized, TITLE_H + 8, .h)
            If x >= .x And x < .x + .w And y >= .y And y < .y + hh Then Return p
        End With
    Next
    Return 0
End Function

Sub SelectFeature(ByVal p As Long, ByVal i As Long)
    With Parts(p)
        .selected = i
        If i > 0 Then
            Dim As TDesign Ptr d = @Docs(.slot)
            SetStatus FeatureName(*d, i) & ": " & Describe(*d, i)
            ' keep it in view in the timeline
            Dim As Long cx, cy, cw, ch, rows
            ClientRect p, cx, cy, cw, ch
            rows = (TL_H - 4 - LV_HEAD_H) \ LV_ROW_H
            If i - 1 < .listTop Then .listTop = i - 1
            If i - 1 >= .listTop + rows Then .listTop = i - rows
        End If
    End With
End Sub

Declare Sub PartMinimize(ByVal p As Long)

' Mouse down in part p. Returns True if it was used.
Sub PartMouseDown(ByVal p As Long, ByRef ev As UIEvent)
    Dim As Long cx, cy, cw, ch, vx, vy, vw, vh
    BringToFront p
    With Parts(p)
        ' the caption buttons
        Dim As Long bx = .x + .w - 4 - 2 - 16
        If ev.y >= .y + 6 And ev.y < .y + 20 Then
            If ev.x >= bx And ev.x < bx + 16 Then
                If PartQueryClose(p) Then ClosePartWindow p
                Exit Sub
            ElseIf ev.x >= bx - 18 And ev.x < bx - 2 Then
                If .minimized Then PartMinimize p
                Exit Sub
            ElseIf ev.x >= bx - 34 And ev.x < bx - 18 Then
                If Not .minimized Then PartMinimize p
                Exit Sub
            End If
        End If
        If ev.y < .y + 4 + TITLE_H Then
            If ev.dbl And .minimized Then PartMinimize p: Exit Sub
            .dragKind = 3: .dragX = ev.x - .x: .dragY = ev.y - .y
            Exit Sub
        End If
        If .minimized Then Exit Sub
        If ev.x >= .x + .w - 12 And ev.y >= .y + .h - 12 Then
            .dragKind = 4: .dragX = .x + .w - ev.x: .dragY = .y + .h - ev.y
            Exit Sub
        End If
        ClientRect p, cx, cy, cw, ch
        ViewRect p, vx, vy, vw, vh
        ' the view: orbit with the left button, pan with the right
        If ev.x >= vx And ev.x < vx + vw And ev.y >= vy And ev.y < vy + vh Then
            .dragKind = IIf(ev.btn = 2, 2, 1)
            .dragX = ev.x: .dragY = ev.y
            .moved = False
            .frames = 0: .frameStart = Timer
            Exit Sub
        End If
        ' the tree
        If ev.x >= cx And ev.x < cx + TREE_W And ev.y >= cy And ev.y < cy + ch - TL_H - 4 Then
            .focusTree = True
            BuildTree p
            Dim As Long r = .treeTop + (ev.y - (cy + 4)) \ ROW_H
            If r >= 0 And r < TreeRowN Then
                Dim As Long lx = cx + 22 + TreeRows(r).level * 19
                If TreeRows(r).hasKids And ev.x >= lx - 16 And ev.x < lx - 3 Then
                    If TreeRows(r).key = -1 Then .originOpen = Not .originOpen
                    If TreeRows(r).key > 0 Then .expanded(TreeRows(r).key) = Not .expanded(TreeRows(r).key)
                ElseIf TreeRows(r).key > 0 Then
                    SelectFeature p, TreeRows(r).key
                    If ev.dbl Then EditFeature p, .selected
                Else
                    .selected = 0
                    If ev.dbl And TreeRows(r).key = -1 Then .originOpen = Not .originOpen
                End If
            End If
            Exit Sub
        End If
        ' the timeline
        If ev.y >= cy + ch - TL_H Then
            .focusTree = False
            Dim As Long rows = (TL_H - 4 - LV_HEAD_H) \ LV_ROW_H, n = Docs(.slot).Count
            If n > rows And ev.x >= cx + cw - 18 Then
                If ev.y < cy + ch - TL_H + 2 + (TL_H - 4) \ 2 Then .listTop -= 1 Else .listTop += 1
                Exit Sub
            End If
            Dim As Long r = .listTop + 1 + (ev.y - (cy + ch - TL_H + 2 + LV_HEAD_H)) \ LV_ROW_H
            If ev.y >= cy + ch - TL_H + 2 + LV_HEAD_H And r >= 1 And r <= n Then
                SelectFeature p, r
                If ev.dbl Then EditFeature p, r
            End If
        End If
    End With
End Sub

Sub PartMouseMove(ByVal p As Long, ByRef ev As UIEvent)
    With Parts(p)
        Select Case .dragKind
        Case 1, 2
            If ev.x = .dragX And ev.y = .dragY Then Exit Sub
            If .dragKind = 1 Then
                .v.Yaw += (ev.x - .dragX) * 0.5
                .v.Pitch += (ev.y - .dragY) * 0.5
                If .v.Pitch > 90 Then .v.Pitch = 90
                If .v.Pitch < -90 Then .v.Pitch = -90
            Else
                .v.PanX += ev.x - .dragX
                .v.PanY += ev.y - .dragY
            End If
            .dragX = ev.x: .dragY = ev.y
            .moved = True
            ' Turbo caps orbit at 4 fps; the mouse keeps going, the picture catches up
            If Timer - .lastDraw < OrbitFrameInterval() Then Exit Sub
            .lastDraw = Timer
            PartRedraw p
            .frames += 1
            Dim As Double el = Timer - .frameStart
            If el > 0.5 Then
                If Turbo Then
                    SetFps Int(.frames / el) & " fps (Turbo)"
                    SetStatus "Orbit is limited to 4 fps while Turbo is on."
                Else
                    SetFps Int(.frames / el) & " fps"
                End If
                .frames = 0: .frameStart = Timer
            End If
        Case 3
            .x = ev.x - .dragX: .y = ev.y - .dragY
            If .y < MdiY Then .y = MdiY
            NeedRedraw = True
        Case 4
            .w = ev.x + .dragX - .x: .h = ev.y + .dragY - .y
            If .w < 420 Then .w = 420
            If .h < 300 Then .h = 300
            EnsureImages p
            FitView .v, .imgW, .imgH, .edges, .edgeN
            PartRedraw p
        End Select
    End With
End Sub

Sub PartMouseUp(ByVal p As Long, ByRef ev As UIEvent)
    With Parts(p)
        Dim As Long k = .dragKind
        .dragKind = 0
        ' the last position, in case Turbo skipped it; shaded again if it moved
        If (k = 1 Or k = 2) And (.moved Or Not ViewShaded) Then PartRedraw p
        If k = 4 Then PartRedraw p
    End With
End Sub

Sub PartWheel(ByVal p As Long, ByRef ev As UIEvent)
    PartZoomBy p, IIf(ev.wheel > 0, 1.25, 0.8)
End Sub

' Minimise to a title bar along the bottom, or back.
Dim Shared SavedRect(1 To MAX_DOCS, 0 To 3) As Long
Sub PartMinimize(ByVal p As Long)
    With Parts(p)
        If .minimized Then
            .minimized = False
            .x = SavedRect(p, 0): .y = SavedRect(p, 1): .w = SavedRect(p, 2): .h = SavedRect(p, 3)
        Else
            SavedRect(p, 0) = .x: SavedRect(p, 1) = .y: SavedRect(p, 2) = .w: SavedRect(p, 3) = .h
            .minimized = True
            Dim As Long n = 0, i
            For i = 1 To MAX_DOCS
                If Parts(i).inUse And Parts(i).minimized And i <> p Then n += 1
            Next
            .w = 160: .x = MdiX + n * 162: .y = MdiY + MdiH - (TITLE_H + 8)
        End If
    End With
    NeedRedraw = True
End Sub
