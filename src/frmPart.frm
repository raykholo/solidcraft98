VERSION 5.00
Object = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}#2.0#0"; "MSCOMCTL.OCX"
Begin VB.Form frmPart
   Caption         =   "Part"
   ClientHeight    =   6000
   ClientLeft      =   60
   ClientTop       =   345
   ClientWidth     =   9000
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MDIChild        =   -1  'True
   Begin MSComctlLib.TreeView tvwTree
      Height          =   4200
      Left            =   0
      TabIndex        =   0
      Top             =   0
      Width           =   2400
      _ExtentX        =   4233
      _ExtentY        =   7408
      _Version        =   393217
      HideSelection   =   0   'False
      Indentation     =   353
      LabelEdit       =   1
      LineStyle       =   1
      Style           =   6
      Appearance      =   1
   End
   Begin VB.PictureBox picView
      AutoRedraw      =   -1  'True
      BackColor       =   &H00E0E0E0&
      Height          =   4200
      Left            =   2460
      MousePointer    =   15  'Size All
      ScaleHeight     =   276
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   432
      TabIndex        =   1
      Top             =   0
      Width           =   6540
   End
   Begin MSComctlLib.ListView lvwTimeline
      Height          =   1740
      Left            =   0
      TabIndex        =   2
      Top             =   4260
      Width           =   9000
      _ExtentX        =   15875
      _ExtentY        =   3069
      View            =   3
      LabelEdit       =   1
      LabelWrap       =   -1  'True
      HideSelection   =   0   'False
      FullRowSelect   =   -1  'True
      GridLines       =   -1  'True
      _Version        =   393217
      Appearance      =   1
   End
End
Attribute VB_Name = "frmPart"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmPart - one part: feature tree on the left, wireframe viewport on the
' right, timeline along the bottom. The design itself lives in modDoc.
Option Explicit

Public DocIndex As Integer

Private mView As TView
Private mEdges() As TEdge
Private mEdgeCount As Long
Private mDragging As Boolean
Private mDragX As Single, mDragY As Single
Private mDragButton As Integer
Private mFrames As Long, mFrameStart As Single
Private mLastDraw As Single
Private mRegenTries As Integer
Private mKonami As Integer
Private mSelected As Integer      ' feature picked in the tree or timeline

Private Const GAP As Single = 60

Public Sub Attach(ByVal slot As Integer)
    Dim n As Integer, i As Integer
    DocIndex = slot
    ResetView mView
    ' The first part fills the frame. (Not maximised: a maximised MDI child
    ' loses the menus under twinBASIC, so there's no Maximize button.)
    ' Later ones cascade, like Window > Cascade would.
    For i = 1 To MAX_DOCS
        If DocInUse(i) And i <> slot Then n = n + 1
    Next i
    If n = 0 Then
        Move 0, 0, frmMain.ScaleWidth, frmMain.ScaleHeight
    Else
        Move n * 360, n * 360, frmMain.ScaleWidth * 0.85, frmMain.ScaleHeight * 0.85
    End If
    RefreshAll True
End Sub

Private Sub Form_Load()
    ClassicLook Me
    ReDim mEdges(0 To 0)
    With lvwTimeline.ColumnHeaders
        .Add , , "#", 500
        .Add , , "Feature", 1600
        .Add , , "Type", 1800
        .Add , , "Parameters", 3700
        .Add , , "Status", 2100
    End With
End Sub

' The header captions can go missing when the list is first moved, so put them back.
Private Sub ColumnTitles()
    Dim t() As String, i As Integer
    t = Split("#|Feature|Type|Parameters|Status", "|")
    For i = 0 To UBound(t)
        If i + 1 <= lvwTimeline.ColumnHeaders.Count Then
            If lvwTimeline.ColumnHeaders(i + 1).Text <> t(i) Then lvwTimeline.ColumnHeaders(i + 1).Text = t(i)
        End If
    Next i
End Sub

' Rebuilds the tree, the timeline and the picture from the design.
Public Sub RefreshAll(ByVal bFit As Boolean)
    Dim d As Integer
    d = DocIndex
    If d = 0 Then Exit Sub
    Caption = DocTitle(d)
    If mSelected > Docs(d).Count Then mSelected = 0
    FillTree
    FillTimeline
    mEdgeCount = Regenerate(Docs(d), mEdges)
    If bFit Then FitView mView, picView, mEdges, mEdgeCount
    Redraw
End Sub

Private Sub FillTree()
    Dim i As Integer, n As Node, sKey As String, sParent As String
    tvwTree.Nodes.Clear
    Set n = tvwTree.Nodes.Add(, , "root", RTrim$(Docs(DocIndex).Title))
    n.Expanded = True
    tvwTree.Nodes.Add "root", tvwChild, "origin", "Origin"
    tvwTree.Nodes.Add "origin", tvwChild, , "Front Plane (XZ)"
    tvwTree.Nodes.Add "origin", tvwChild, , "Top Plane (XY)"
    tvwTree.Nodes.Add "origin", tvwChild, , "Right Plane (YZ)"
    For i = 1 To Docs(DocIndex).Count
        sKey = "f" & i
        ' Sketches hang under the feature that uses them, the way people expect.
        sParent = "root"
        Set n = tvwTree.Nodes.Add(sParent, tvwChild, sKey, FeatureName(Docs(DocIndex), i))
        If Docs(DocIndex).Features(i).Kind = FK_EXTRUDE Or Docs(DocIndex).Features(i).Kind = FK_REVOLVE Then
            MoveUnder Docs(DocIndex).Features(i).Ref, i
        End If
        If Not RefOk(Docs(DocIndex), i) Then n.Text = n.Text & " (!)"
    Next i
End Sub

' Re-adds sketch nSketch as the child of feature nFeature.
Private Sub MoveUnder(ByVal nSketch As Integer, ByVal nFeature As Integer)
    On Error Resume Next   ' a missing sketch is shown with (!) anyway
    Dim t As String
    t = tvwTree.Nodes("f" & nSketch).Text
    tvwTree.Nodes.Remove "f" & nSketch
    tvwTree.Nodes.Add "f" & nFeature, tvwChild, "f" & nSketch, t
End Sub

Private Sub FillTimeline()
    Dim i As Integer, li As ListItem
    lvwTimeline.ListItems.Clear
    For i = 1 To Docs(DocIndex).Count
        Set li = lvwTimeline.ListItems.Add(, "t" & i, CStr(i))
        li.SubItems(1) = FeatureName(Docs(DocIndex), i)
        li.SubItems(2) = KindName(Docs(DocIndex).Features(i).Kind)
        li.SubItems(3) = Describe(Docs(DocIndex), i)
        If Docs(DocIndex).Features(i).Kind = FK_FOREIGN Then
            li.SubItems(2) = RTrim$(Docs(DocIndex).Features(i).Info)
            li.SubItems(4) = "Requires SolidCraft 2000"
        ElseIf RefOk(Docs(DocIndex), i) Then
            li.SubItems(4) = "OK"
        Else
            li.SubItems(4) = "Rebuild error"
        End If
    Next i
End Sub

Public Sub Redraw()
    DrawScene mView, picView, mEdges, mEdgeCount
    If Docs(DocIndex).Count = 0 Then
        TextAt picView, 6, 4, "Empty part. Sketch a rectangle (R) or a circle (C) to begin.", &H404040
    Else
        TextAt picView, 6, 4, mEdgeCount & " edges", &H404040
    End If
    picView.Refresh
End Sub

Public Sub ViewIso()
    ResetView mView
    FitView mView, picView, mEdges, mEdgeCount
    Redraw
    frmMain.SetStatus "Isometric view."
End Sub

Public Sub ZoomFit()
    FitView mView, picView, mEdges, mEdgeCount
    Redraw
End Sub

Public Property Get ViewPicture() As PictureBox
    Set ViewPicture = picView
End Property

Public Sub Regen()
    If Not SolverConverges(mRegenTries) Then
        frmMain.SetStatus "Regenerate: the solver did not converge (attempt " & mRegenTries & ")."
        Exit Sub
    End If
    RefreshAll False
    frmMain.SetStatus "Regenerated " & Docs(DocIndex).Count & " features, " & mEdgeCount & " edges."
End Sub

Private Sub Form_Activate()
    frmMain.SetFps ""
End Sub

Private Sub Form_Resize()
    Dim w As Single, h As Single, treeW As Single, tlH As Single
    If WindowState = vbMinimized Then Exit Sub
    w = ScaleWidth: h = ScaleHeight
    treeW = 2400: tlH = 1740
    If w < treeW + 600 Or h < tlH + 600 Then Exit Sub
    tvwTree.Move 0, 0, treeW, h - tlH - GAP
    picView.Move treeW + GAP, 0, w - treeW - GAP, h - tlH - GAP
    lvwTimeline.Move 0, h - tlH, w, tlH
    ColumnTitles
    If DocIndex <> 0 Then Redraw
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If DocIndex = 0 Then Exit Sub
    If DocDirty(DocIndex) Then
        Select Case MsgBox("Save changes to " & RTrim$(Docs(DocIndex).Title) & "?", vbQuestion Or vbYesNoCancel, App.Title)
        Case vbYes
            RunCommand "Save"
            If DocDirty(DocIndex) Then Cancel = 1
        Case vbCancel
            Cancel = 1
        End Select
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    FreeDocSlot DocIndex
    DocIndex = 0
End Sub

' Single-key shortcuts. Ctrl+N/O/S/Z and F1/F5 live on the menus.
Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim sCmd As String
    If KonamiKey(KeyCode) Then
        KeyCode = 0
        Exit Sub
    End If
    If Shift <> 0 Then Exit Sub
    Select Case KeyCode
    Case vbKeyR: sCmd = "SketchRect"
    Case vbKeyC: sCmd = "SketchCircle"
    Case vbKeyE: sCmd = "Extrude"
    Case vbKeyV: sCmd = "Revolve"
    Case vbKeyH: sCmd = "Hole"
    Case vbKeyI: sCmd = "ViewIso"
    Case vbKeyF: sCmd = "ZoomFit"
    Case vbKeyDelete: sCmd = "Delete"
    Case vbKeyReturn: sCmd = "Edit"
    Case vbKeyAdd, 187: ZoomBy 1.25: KeyCode = 0
    Case vbKeySubtract, 189: ZoomBy 0.8: KeyCode = 0
    End Select
    If Len(sCmd) > 0 Then
        KeyCode = 0
        RunCommand sCmd
    End If
End Sub

' Up, up, down, down, left, right, left, right, B, A. Returns True when it completes.
Private Function KonamiKey(ByVal KeyCode As Integer) As Boolean
    Dim seq As Variant
    seq = Array(vbKeyUp, vbKeyUp, vbKeyDown, vbKeyDown, vbKeyLeft, vbKeyRight, vbKeyLeft, vbKeyRight, vbKeyB, vbKeyA)
    If KeyCode = seq(mKonami) Then
        mKonami = mKonami + 1
        If mKonami > UBound(seq) Then
            mKonami = 0
            KonamiSpin
            KonamiKey = True
        End If
    ElseIf KeyCode = seq(0) Then
        mKonami = 1
    Else
        mKonami = 0
    End If
End Function

' Three seconds of full-speed spin. The frame counter is decorative.
Private Sub KonamiSpin()
    Dim t As Single, y0 As Double
    t = Timer
    y0 = mView.Yaw
    frmMain.SetFps "60 fps (lying)"
    frmMain.SetStatus "Cheat activated. Full speed for three seconds."
    Do While Timer - t < 3 And Timer >= t
        mView.Yaw = y0 + (Timer - t) * 240
        Redraw
        DoEvents
    Loop
    mView.Yaw = y0
    Redraw
    frmMain.SetFps "60 fps (lying)"
End Sub

Private Sub ZoomBy(ByVal k As Double)
    mView.Zoom = mView.Zoom * k
    mView.PanX = mView.PanX * k
    mView.PanY = mView.PanY * k
    Redraw
End Sub

' ---- Orbit: left drag. Pan: right drag. ----

Private Sub picView_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    mDragging = True
    mDragButton = Button
    mDragX = X: mDragY = Y
    mFrames = 0: mFrameStart = Timer
End Sub

Private Sub picView_MouseMove(Button As Integer, Shift As Integer, X As Single, Y As Single)
    Dim el As Single
    If Not mDragging Then Exit Sub
    If mDragButton = vbLeftButton Then
        mView.Yaw = mView.Yaw - (X - mDragX) * 0.5
        mView.Pitch = mView.Pitch + (Y - mDragY) * 0.5
        If mView.Pitch > 90 Then mView.Pitch = 90
        If mView.Pitch < -90 Then mView.Pitch = -90
    Else
        mView.PanX = mView.PanX + (X - mDragX)
        mView.PanY = mView.PanY + (Y - mDragY)
    End If
    mDragX = X: mDragY = Y
    ' Turbo caps orbit at 4 fps; the mouse keeps going, the picture catches up
    If Timer - mLastDraw < OrbitFrameInterval() And Timer >= mLastDraw Then Exit Sub
    mLastDraw = Timer
    Redraw
    mFrames = mFrames + 1
    el = Timer - mFrameStart
    If el > 0.5 Then
        If Turbo Then
            frmMain.SetFps Format$(mFrames / el, "0") & " fps (Turbo)"
            frmMain.SetStatus "Orbit is limited to 4 fps while Turbo is on."
        Else
            frmMain.SetFps Format$(mFrames / el, "0") & " fps"
        End If
        mFrames = 0: mFrameStart = Timer
    End If
End Sub

Private Sub picView_MouseUp(Button As Integer, Shift As Integer, X As Single, Y As Single)
    mDragging = False
    Redraw          ' the last position, in case Turbo skipped it
End Sub

' The feature selected in the tree or the timeline, whichever was used last. 0 if none.
Public Function SelectedFeature() As Integer
    SelectedFeature = mSelected
End Function

Private Sub tvwTree_DblClick()
    If mSelected > 0 Then EditFeature Me, mSelected
End Sub

Private Sub lvwTimeline_ItemClick(ByVal Item As MSComctlLib.ListItem)
    mSelected = Val(Mid$(Item.Key, 2))
    frmMain.SetStatus FeatureName(Docs(DocIndex), mSelected) & ": " & Describe(Docs(DocIndex), mSelected)
End Sub

Private Sub lvwTimeline_DblClick()
    If mSelected > 0 Then EditFeature Me, mSelected
End Sub

Private Sub tvwTree_NodeClick(ByVal Node As MSComctlLib.Node)
    Dim i As Integer
    If Left$(Node.Key, 1) <> "f" Then
        mSelected = 0
        Exit Sub
    End If
    i = Val(Mid$(Node.Key, 2))
    mSelected = i
    If i >= 1 And i <= lvwTimeline.ListItems.Count Then
        lvwTimeline.ListItems(i).Selected = True
        lvwTimeline.ListItems(i).EnsureVisible
        frmMain.SetStatus FeatureName(Docs(DocIndex), i) & ": " & Describe(Docs(DocIndex), i)
    End If
End Sub
