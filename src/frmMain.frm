VERSION 5.00
Begin VB.MDIForm frmMain
   BackColor       =   &H8000000C&
   Caption         =   "SolidCraft 98"
   ClientHeight    =   9600
   ClientLeft      =   165
   ClientTop       =   855
   ClientWidth     =   14400
   LinkTopic       =   "MDIForm1"
   StartUpPosition =   2  'CenterScreen
   Begin VB.Timer tmrHover
      Interval        =   100
      Left            =   120
      Top             =   1200
   End
   Begin VB.Timer tmrClock
      Interval        =   1000
      Left            =   600
      Top             =   1200
   End
   Begin VB.PictureBox picToolbar
      Align           =   1  'Align Top
      AutoRedraw      =   -1  'True
      BackColor       =   &H00C0C0C0&
      BorderStyle     =   0  'None
      Height          =   450
      Left            =   0
      ScaleHeight     =   30
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   800
      TabIndex        =   0
      TabStop         =   0   'False
      Top             =   0
      Width           =   12000
   End
   Begin VB.PictureBox picStatus
      Align           =   2  'Align Bottom
      AutoRedraw      =   -1  'True
      BackColor       =   &H00C0C0C0&
      BorderStyle     =   0  'None
      Height          =   330
      Left            =   0
      ScaleHeight     =   22
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   800
      TabIndex        =   1
      TabStop         =   0   'False
      Top             =   8070
      Width           =   12000
   End
   Begin VB.Menu mnuFile
      Caption         =   "&File"
      Begin VB.Menu mnuFileItem
         Caption         =   "&New Part"
         Index           =   0
         Shortcut        =   ^N
         Tag             =   "New"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "&Open..."
         Index           =   1
         Shortcut        =   ^O
         Tag             =   "Open"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "&Save"
         Index           =   2
         Shortcut        =   ^S
         Tag             =   "Save"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "Save &As..."
         Index           =   3
         Tag             =   "SaveAs"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "Sen&d To 3 1/2 Floppy (A:)..."
         Index           =   4
         Tag             =   "SaveFloppy"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "Publish to &Web..."
         Index           =   5
         Tag             =   "Publish"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "Export for &Rapid Prototyping (*.stl)..."
         Index           =   6
         Tag             =   "ExportStl"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "&Close"
         Index           =   7
         Tag             =   "Close"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "-"
         Index           =   8
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "E&xit"
         Index           =   9
         Tag             =   "Exit"
      End
   End
   Begin VB.Menu mnuEdit
      Caption         =   "&Edit"
      Begin VB.Menu mnuEditItem
         Caption         =   "&Undo Last Feature"
         Index           =   0
         Shortcut        =   ^Z
         Tag             =   "Undo"
      End
      Begin VB.Menu mnuEditItem
         Caption         =   "-"
         Index           =   1
      End
      Begin VB.Menu mnuEditItem
         Caption         =   "&Edit Feature..."
         Index           =   2
         Tag             =   "Edit"
      End
      Begin VB.Menu mnuEditItem
         Caption         =   "&Delete Feature"
         Index           =   3
         Shortcut        =   {DEL}
         Tag             =   "Delete"
      End
   End
   Begin VB.Menu mnuSketch
      Caption         =   "&Sketch"
      Begin VB.Menu mnuSketchItem
         Caption         =   "&Rectangle..."
         Index           =   0
         Tag             =   "SketchRect"
      End
      Begin VB.Menu mnuSketchItem
         Caption         =   "&Circle..."
         Index           =   1
         Tag             =   "SketchCircle"
      End
   End
   Begin VB.Menu mnuFeature
      Caption         =   "Fea&tures"
      Begin VB.Menu mnuFeatureItem
         Caption         =   "&Extrude..."
         Index           =   0
         Tag             =   "Extrude"
      End
      Begin VB.Menu mnuFeatureItem
         Caption         =   "Re&volve..."
         Index           =   1
         Tag             =   "Revolve"
      End
      Begin VB.Menu mnuFeatureItem
         Caption         =   "&Hole..."
         Index           =   2
         Tag             =   "Hole"
      End
   End
   Begin VB.Menu mnuView
      Caption         =   "&View"
      Begin VB.Menu mnuViewItem
         Caption         =   "&Isometric"
         Index           =   0
         Tag             =   "ViewIso"
      End
      Begin VB.Menu mnuViewItem
         Caption         =   "Zoom to &Fit"
         Index           =   1
         Tag             =   "ZoomFit"
      End
      Begin VB.Menu mnuViewItem
         Caption         =   "&Regenerate"
         Index           =   2
         Shortcut        =   {F5}
         Tag             =   "Regen"
      End
      Begin VB.Menu mnuViewItem
         Caption         =   "&Shaded"
         Index           =   3
         Tag             =   "Shaded"
      End
      Begin VB.Menu mnuViewItem
         Caption         =   "-"
         Index           =   4
      End
      Begin VB.Menu mnuViewItem
         Caption         =   "&Turbo"
         Index           =   5
         Tag             =   "Turbo"
      End
   End
   Begin VB.Menu mnuWindow
      Caption         =   "&Window"
      WindowList      =   -1  'True
      Begin VB.Menu mnuWindowItem
         Caption         =   "&Cascade"
         Index           =   0
         Tag             =   "Cascade"
      End
      Begin VB.Menu mnuWindowItem
         Caption         =   "Tile &Horizontally"
         Index           =   1
         Tag             =   "TileH"
      End
      Begin VB.Menu mnuWindowItem
         Caption         =   "Tile &Vertically"
         Index           =   2
         Tag             =   "TileV"
      End
   End
   Begin VB.Menu mnuHelp
      Caption         =   "&Help"
      Begin VB.Menu mnuHelpItem
         Caption         =   "&Contents"
         Index           =   0
         Shortcut        =   {F1}
         Tag             =   "Help"
      End
      Begin VB.Menu mnuHelpItem
         Caption         =   "-"
         Index           =   1
      End
      Begin VB.Menu mnuHelpItem
         Caption         =   "&About SolidCraft 98..."
         Index           =   2
         Tag             =   "About"
      End
   End
End
Attribute VB_Name = "frmMain"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmMain - the battleship-grey MDI frame: menus, toolbar, status bar.
' Every menu item and toolbar button carries a command key (in its Tag, or
' its toolbar key) and hands it to RunCommand. Nothing else happens here.
Option Explicit

Private Type POINTAPI
    X As Long
    Y As Long
End Type

Private Type RECT
    Left As Long
    Top As Long
    Right As Long
    Bottom As Long
End Type

Private Declare Function GetCursorPos Lib "user32" (lpPoint As POINTAPI) As Long
Private Declare Function GetWindowRect Lib "user32" (ByVal hWnd As Long, lpRect As RECT) As Long

Private mLastMsg As String

Private Sub MDIForm_Load()
    ' On an 800 x 600 screen the frame doesn't fit, so take the whole screen.
    If Width > Screen.Width * 0.95 Or Height > Screen.Height * 0.9 Then WindowState = vbMaximized
    ' single-key shortcuts, shown the way the menu editor can't
    mnuSketchItem(0).Caption = "&Rectangle..." & vbTab & "R"
    mnuSketchItem(1).Caption = "&Circle..." & vbTab & "C"
    mnuFeatureItem(0).Caption = "&Extrude..." & vbTab & "E"
    mnuFeatureItem(1).Caption = "Re&volve..." & vbTab & "V"
    mnuFeatureItem(2).Caption = "&Hole..." & vbTab & "H"
    mnuViewItem(0).Caption = "&Isometric" & vbTab & "I"
    mnuViewItem(1).Caption = "Zoom to &Fit" & vbTab & "F"
    mnuViewItem(3).Caption = "&Shaded" & vbTab & "S"
    mnuEditItem(2).Caption = "&Edit Feature..." & vbTab & "Enter"
    BuildToolbar
    BuildStatusBar
    ToolbarDraw picToolbar
    DrawLed picToolbar, ToolbarRight() + 6, LedDigits()
    StatusDraw picStatus
    SetStatus "Ready"
End Sub

Private Sub BuildToolbar()
    ToolbarClear
    ToolbarAdd "New", "New Part (Ctrl+N)"
    ToolbarAdd "Open", "Open Part (Ctrl+O)"
    ToolbarAdd "Save", "Save Part (Ctrl+S)"
    ToolbarAdd "", ""
    ToolbarAdd "SketchRect", "Sketch Rectangle (R)"
    ToolbarAdd "SketchCircle", "Sketch Circle (C)"
    ToolbarAdd "", ""
    ToolbarAdd "Extrude", "Extrude (E)"
    ToolbarAdd "Revolve", "Revolve (V)"
    ToolbarAdd "Hole", "Hole (H)"
    ToolbarAdd "", ""
    ToolbarAdd "Orbit", "Isometric View (I). Drag in the viewport to orbit."
    ToolbarAdd "Shaded", "Shaded (S). Rendered in software, properly."
    ToolbarAdd "ZoomFit", "Zoom to Fit (F)"
    ToolbarAdd "Regen", "Regenerate (F5)"
    ToolbarAdd "", ""
    ToolbarAdd "Turbo", "Turbo. Makes everything faster. (It doesn't.)"
End Sub

' The Turbo button stays pushed in while Turbo is on; the LED shows the "speed".
Public Sub TurboChanged()
    ToolbarSetChecked picToolbar, "Turbo", Turbo
    DrawLed picToolbar, ToolbarRight() + 6, LedDigits()
    mnuViewItem(5).Checked = Turbo
End Sub

' The Shaded button stays pushed in while the view is shaded.
Public Sub ShadedChanged()
    ToolbarSetChecked picToolbar, "Shaded", ViewShaded
    mnuViewItem(3).Checked = ViewShaded
End Sub

Private Sub BuildStatusBar()
    StatusClear
    StatusAdd "msg", "Ready", 0
    StatusAdd "units", "mm", 40
    StatusAdd "fps", "", 110
    StatusAdd "clock", "", 70
End Sub

Public Sub SetStatus(ByVal s As String)
    mLastMsg = s
    StatusSet picStatus, "msg", s
End Sub

Public Sub SetFps(ByVal s As String)
    StatusSet picStatus, "fps", s
End Sub

' Open and Save As dialogs. Returns "" on Cancel.
Public Function AskFileName(ByVal bSave As Boolean, ByVal sDefault As String, _
                            Optional ByVal sFilter As String = "", Optional ByVal sExt As String = "") As String
    AskFileName = FileDialog(Me.hWnd, bSave, sDefault, sFilter, sExt)
End Function

Private Sub picToolbar_Resize()
    ToolbarDraw picToolbar
    DrawLed picToolbar, ToolbarRight() + 6, LedDigits()
End Sub

Private Sub tmrClock_Timer()
    ClockTick
    StatusSet picStatus, "clock", Format$(ClockNow(), "h:nn AM/PM")
End Sub

Private Sub picStatus_Resize()
    StatusDraw picStatus
End Sub

Private Sub picToolbar_MouseMove(Button As Integer, Shift As Integer, X As Single, Y As Single)
    Dim sTip As String
    sTip = ToolbarMouseMove(picToolbar, X, Y)
    If picToolbar.ToolTipText <> sTip Then picToolbar.ToolTipText = sTip
    If Len(sTip) > 0 Then
        StatusSet picStatus, "msg", sTip
    Else
        StatusSet picStatus, "msg", mLastMsg
    End If
End Sub

Private Sub picToolbar_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    If Button = vbLeftButton Then ToolbarMouseDown picToolbar, X, Y
End Sub

Private Sub picToolbar_MouseUp(Button As Integer, Shift As Integer, X As Single, Y As Single)
    Dim sKey As String
    If Button <> vbLeftButton Then Exit Sub
    sKey = ToolbarMouseUp(picToolbar, X, Y)
    If Len(sKey) > 0 Then RunCommand sKey
End Sub

' VB has no MouseLeave, so a Timer checks whether the mouse is still there.
Private Sub tmrHover_Timer()
    Dim pt As POINTAPI, rc As RECT
    GetCursorPos pt
    GetWindowRect picToolbar.hWnd, rc
    If pt.X < rc.Left Or pt.X >= rc.Right Or pt.Y < rc.Top Or pt.Y >= rc.Bottom Then
        ToolbarMouseLeave picToolbar
        StatusSet picStatus, "msg", mLastMsg
    End If
End Sub

Private Sub mnuFileItem_Click(Index As Integer)
    RunCommand mnuFileItem(Index).Tag
End Sub

Private Sub mnuEditItem_Click(Index As Integer)
    RunCommand mnuEditItem(Index).Tag
End Sub

Private Sub mnuSketchItem_Click(Index As Integer)
    RunCommand mnuSketchItem(Index).Tag
End Sub

Private Sub mnuFeatureItem_Click(Index As Integer)
    RunCommand mnuFeatureItem(Index).Tag
End Sub

Private Sub mnuViewItem_Click(Index As Integer)
    RunCommand mnuViewItem(Index).Tag
End Sub

Private Sub mnuWindowItem_Click(Index As Integer)
    RunCommand mnuWindowItem(Index).Tag
End Sub

Private Sub mnuHelpItem_Click(Index As Integer)
    RunCommand mnuHelpItem(Index).Tag
End Sub

Private Sub MDIForm_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    Dim i As Integer, n As Integer
    For i = 1 To MAX_DOCS
        If DocInUse(i) And DocDirty(i) Then n = n + 1
    Next i
    If n > 0 Then
        If MsgBox(n & " part(s) have unsaved changes." & vbCrLf & vbCrLf & _
            "Exit SolidCraft 98 anyway?", vbQuestion Or vbYesNo Or vbDefaultButton2, App.Title) = vbNo Then
            Cancel = 1
        End If
    End If
End Sub
