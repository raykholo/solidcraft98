Attribute VB_Name = "modCommands"
' modCommands - everything is a command.
'
' The toolbar, the menus and the keyboard all call RunCommand with the same
' key, so there is exactly one copy of each command. (The 1999 way was three
' copies, one per Click handler, all subtly different. See README.)
Option Explicit

Public Sub RunCommand(ByVal sCmd As String)
    Select Case sCmd
    Case "New": CmdNew
    Case "Open": CmdOpen
    Case "Save": CmdSave False
    Case "SaveAs": CmdSave True
    Case "Close": CmdClose
    Case "Exit": Unload frmMain

    Case "SketchRect": CmdSketchRect
    Case "SketchCircle": CmdSketchCircle
    Case "Extrude": CmdExtrude
    Case "Revolve": CmdRevolve
    Case "Hole": CmdHole
    Case "Undo": CmdUndo

    Case "Orbit", "ViewIso": WithPart "ViewIso"
    Case "ZoomFit": WithPart "ZoomFit"
    Case "Regen": WithPart "Regen"

    Case "Cascade": frmMain.Arrange vbCascade
    Case "TileH": frmMain.Arrange vbTileHorizontal
    Case "TileV": frmMain.Arrange vbTileVertical

    Case "Help": CmdHelp
    Case "About": frmAbout.Show vbModal, frmMain
    Case Else
        MsgBox "Command '" & sCmd & "' is not implemented yet." & vbCrLf & _
            "It is scheduled for SolidCraft 2000.", vbInformation, App.Title
    End Select
End Sub

' The part window in front, or Nothing.
Public Function ActivePart() As frmPart
    If frmMain.ActiveForm Is Nothing Then Exit Function
    If TypeOf frmMain.ActiveForm Is frmPart Then Set ActivePart = frmMain.ActiveForm
End Function

Private Function NeedPart(p As frmPart) As Boolean
    Set p = ActivePart()
    If p Is Nothing Then
        MsgBox "There is no part open." & vbCrLf & "Choose File, New Part first.", vbExclamation, App.Title
    Else
        NeedPart = True
    End If
End Function

Private Sub WithPart(ByVal sWhat As String)
    Dim p As frmPart
    If Not NeedPart(p) Then Exit Sub
    Select Case sWhat
    Case "ViewIso": p.ViewIso
    Case "ZoomFit": p.ZoomFit
    Case "Regen": p.Regen
    End Select
End Sub

Private Sub Status(ByVal s As String)
    frmMain.SetStatus s
End Sub

' ---- File ----

Private Sub CmdNew()
    Dim slot As Integer, p As frmPart
    slot = NewDocSlot()
    If slot = 0 Then
        MsgBox "Too many parts open. Sixteen ought to be enough for anybody.", vbExclamation, App.Title
        Exit Sub
    End If
    Set p = New frmPart
    p.Attach slot
    p.Show
    Status "New part created."
End Sub

Private Sub CmdOpen()
    Dim sPath As String, slot As Integer, p As frmPart
    sPath = frmMain.AskFileName(False, "")
    If Len(sPath) = 0 Then Exit Sub
    slot = NewDocSlot()
    If slot = 0 Then
        MsgBox "Too many parts open. Close one first.", vbExclamation, App.Title
        Exit Sub
    End If
    If Not LoadDesign(Docs(slot), sPath) Then
        FreeDocSlot slot
        Exit Sub
    End If
    DocPath(slot) = sPath
    Docs(slot).Title = FileTitle(sPath)
    Set p = New frmPart
    p.Attach slot
    p.Show
    p.ZoomFit
    Status "Opened " & sPath
End Sub

Private Sub CmdSave(ByVal bAs As Boolean)
    Dim p As frmPart, slot As Integer, sPath As String
    If Not NeedPart(p) Then Exit Sub
    slot = p.DocIndex
    sPath = DocPath(slot)
    If bAs Or Len(sPath) = 0 Then
        sPath = frmMain.AskFileName(True, RTrim$(Docs(slot).Title))
        If Len(sPath) = 0 Then Exit Sub
    End If
    If SaveDesign(Docs(slot), sPath) Then
        DocPath(slot) = sPath
        Docs(slot).Title = FileTitle(sPath)
        DocDirty(slot) = False
        p.RefreshAll False
        Status "Saved " & sPath & " (" & FileLen(sPath) & " bytes)"
    End If
End Sub

Private Sub CmdClose()
    Dim p As frmPart
    If Not NeedPart(p) Then Exit Sub
    Unload p
End Sub

' ---- Features ----

Private Function Commit(p As frmPart, f As TFeature) As Boolean
    Dim i As Integer
    i = AddFeature(Docs(p.DocIndex), f)
    If i = 0 Then
        MsgBox "Subscript out of range." & vbCrLf & vbCrLf & _
            "A part can have " & MAX_FEATURES & " features. Nobody will ever need more.", vbCritical, App.Title
        Exit Function
    End If
    DocDirty(p.DocIndex) = True
    p.RefreshAll True
    Status FeatureName(Docs(p.DocIndex), i) & " created: " & Describe(Docs(p.DocIndex), i)
    Commit = True
End Function

Private Sub CmdSketchRect()
    Dim p As frmPart, f As TFeature
    If Not NeedPart(p) Then Exit Sub
    If Not frmParams.Ask("Sketch Rectangle", "Width (mm)|Height (mm)|Corner X (mm)|Corner Y (mm)", "40|30|0|0") Then Exit Sub
    f.Kind = FK_SKETCH_RECT
    f.P1 = frmParams.Value(0): f.P2 = frmParams.Value(1)
    f.X = frmParams.Value(2): f.Y = frmParams.Value(3)
    If f.P1 <= 0 Or f.P2 <= 0 Then
        MsgBox "Width and height must be more than zero.", vbExclamation, App.Title
        Exit Sub
    End If
    Commit p, f
End Sub

Private Sub CmdSketchCircle()
    Dim p As frmPart, f As TFeature
    If Not NeedPart(p) Then Exit Sub
    If Not frmParams.Ask("Sketch Circle", "Radius (mm)|Centre X (mm)|Centre Y (mm)", "15|0|0") Then Exit Sub
    f.Kind = FK_SKETCH_CIRCLE
    f.P1 = frmParams.Value(0)
    f.X = frmParams.Value(1): f.Y = frmParams.Value(2)
    If f.P1 <= 0 Then
        MsgBox "The radius must be more than zero.", vbExclamation, App.Title
        Exit Sub
    End If
    Commit p, f
End Sub

Private Sub CmdExtrude()
    Dim p As frmPart, f As TFeature, s As Integer
    If Not NeedPart(p) Then Exit Sub
    s = LastFreeSketch(Docs(p.DocIndex))
    If s = 0 Then
        MsgBox "Extrude needs a sketch to extrude." & vbCrLf & "Sketch a rectangle or a circle first.", vbExclamation, App.Title
        Exit Sub
    End If
    If Not frmParams.Ask("Extrude " & FeatureName(Docs(p.DocIndex), s), "Depth (mm)", "20") Then Exit Sub
    f.Kind = FK_EXTRUDE
    f.Ref = s
    f.P1 = frmParams.Value(0)
    If f.P1 <= 0 Then
        MsgBox "The depth must be more than zero.", vbExclamation, App.Title
        Exit Sub
    End If
    Commit p, f
End Sub

Private Sub CmdRevolve()
    Dim p As frmPart, f As TFeature, s As Integer
    If Not NeedPart(p) Then Exit Sub
    s = LastFreeSketch(Docs(p.DocIndex))
    If s = 0 Then
        MsgBox "Revolve needs a sketch to revolve." & vbCrLf & "Sketch a rectangle or a circle first.", vbExclamation, App.Title
        Exit Sub
    End If
    If Not frmParams.Ask("Revolve " & FeatureName(Docs(p.DocIndex), s) & " about Y", "Angle (degrees)", "360") Then Exit Sub
    f.Kind = FK_REVOLVE
    f.Ref = s
    f.P1 = frmParams.Value(0)
    If f.P1 = 0 Or Abs(f.P1) > 360 Then
        MsgBox "The angle must be between 1 and 360 degrees.", vbExclamation, App.Title
        Exit Sub
    End If
    Commit p, f
End Sub

Private Sub CmdHole()
    Dim p As frmPart, f As TFeature, b As Integer, s As TFeature, d As Double
    If Not NeedPart(p) Then Exit Sub
    b = LastBox(Docs(p.DocIndex))
    If b = 0 Then
        MsgBox "Hole goes on the top face of a box." & vbCrLf & "Extrude a rectangle first.", vbExclamation, App.Title
        Exit Sub
    End If
    s = Docs(p.DocIndex).Features(Docs(p.DocIndex).Features(b).Ref)
    If Not frmParams.Ask("Hole on top face of " & FeatureName(Docs(p.DocIndex), b), _
        "Diameter (mm)|Depth (mm, 0 = through all)|Centre X (mm)|Centre Y (mm)", _
        "8|0|" & Fmt(s.X + s.P1 / 2) & "|" & Fmt(s.Y + s.P2 / 2)) Then Exit Sub
    f.Kind = FK_HOLE
    f.Ref = b
    f.P1 = frmParams.Value(0): f.P2 = frmParams.Value(1)
    f.X = frmParams.Value(2): f.Y = frmParams.Value(3)
    If f.P1 <= 0 Then
        MsgBox "The diameter must be more than zero.", vbExclamation, App.Title
        Exit Sub
    End If
    d = f.P1 / 2
    If f.X - d < s.X Or f.X + d > s.X + s.P1 Or f.Y - d < s.Y Or f.Y + d > s.Y + s.P2 Then
        MsgBox "That hole doesn't fit on the face. It would fall off the edge.", vbExclamation, App.Title
        Exit Sub
    End If
    Commit p, f
End Sub

Private Sub CmdUndo()
    Dim p As frmPart, slot As Integer, i As Integer
    If Not NeedPart(p) Then Exit Sub
    slot = p.DocIndex
    i = Docs(slot).Count
    If i = 0 Then
        Status "Nothing to undo."
        Exit Sub
    End If
    ' Features only ever build on earlier ones, so the last one is always safe to drop.
    Status "Removed " & FeatureName(Docs(slot), i) & "."
    Docs(slot).Features(i).Kind = FK_NONE
    Docs(slot).Count = i - 1
    DocDirty(slot) = True
    p.RefreshAll False
End Sub

Private Sub CmdHelp()
    MsgBox "Cannot find the file 'SOLIDCRAFT.HLP' (or one of its components)." & vbCrLf & vbCrLf & _
        "Make sure the path and filename are correct and that all required libraries are available.", _
        vbExclamation, "WinHelp"
End Sub
