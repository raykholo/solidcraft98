VERSION 5.00
Object = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}#2.0#0"; "MSCOMCTL.OCX"
Begin VB.MDIForm frmMain
   BackColor       =   &H8000000C&
   Caption         =   "SolidCraft 98"
   ClientHeight    =   8400
   ClientLeft      =   165
   ClientTop       =   855
   ClientWidth     =   12000
   LinkTopic       =   "MDIForm1"
   StartUpPosition =   2  'CenterScreen
   Begin VB.PictureBox picIcon
      Align           =   1  'Align Top
      AutoRedraw      =   -1  'True
      BorderStyle     =   0  'None
      Height          =   240
      Left            =   0
      ScaleHeight     =   16
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   800
      TabIndex        =   2
      Top             =   0
      Visible         =   0   'False
      Width           =   12000
   End
   Begin MSComctlLib.Toolbar tbMain
      Align           =   1  'Align Top
      Height          =   420
      Left            =   0
      TabIndex        =   0
      Top             =   240
      Width           =   12000
      _ExtentX        =   21167
      _ExtentY        =   741
      ButtonWidth     =   609
      ButtonHeight    =   582
      Appearance      =   1
      _Version        =   393216
   End
   Begin MSComctlLib.StatusBar sbMain
      Align           =   2  'Align Bottom
      Height          =   315
      Left            =   0
      TabIndex        =   1
      Top             =   8085
      Width           =   12000
      _ExtentX        =   21167
      _ExtentY        =   556
      _Version        =   393216
   End
   Begin MSComctlLib.ImageList ilTools
      Left            =   120
      Top             =   720
      _ExtentX        =   1005
      _ExtentY        =   1005
      BackColor       =   -2147483643
      ImageWidth      =   16
      ImageHeight     =   16
      MaskColor       =   16711935
      _Version        =   393216
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
         Caption         =   "&Close"
         Index           =   4
         Tag             =   "Close"
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "-"
         Index           =   5
      End
      Begin VB.Menu mnuFileItem
         Caption         =   "E&xit"
         Index           =   6
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
' Every menu item and toolbar button carries a command key in its Tag or
' Key and hands it to RunCommand. Nothing else happens in here.
Option Explicit

Private Sub MDIForm_Load()
    BuildToolbar
    BuildStatusBar
    SetStatus "Ready"
End Sub

Private Sub BuildToolbar()
    Dim keys() As String, i As Integer, img As ListImage
    keys = Split(IconKeys(), " ")
    picIcon.Width = ScaleX(16, vbPixels, ScaleMode)
    picIcon.Height = ScaleY(16, vbPixels, ScaleMode)
    For i = 0 To UBound(keys)
        picIcon.Cls
        PaintIcon picIcon, keys(i), 0, 0
        Set img = ilTools.ListImages.Add(, keys(i), picIcon.Image)
    Next i
    Set tbMain.ImageList = ilTools

    AddButton "New", "New Part (Ctrl+N)"
    AddButton "Open", "Open (Ctrl+O)"
    AddButton "Save", "Save (Ctrl+S)"
    AddSeparator
    AddButton "SketchRect", "Sketch Rectangle (R)"
    AddButton "SketchCircle", "Sketch Circle (C)"
    AddSeparator
    AddButton "Extrude", "Extrude (E)"
    AddButton "Revolve", "Revolve (V)"
    AddButton "Hole", "Hole (H)"
    AddSeparator
    AddButton "Orbit", "Isometric (I). Drag in the viewport to orbit."
    AddButton "ZoomFit", "Zoom to Fit (F)"
    AddButton "Regen", "Regenerate (F5)"
End Sub

Private Sub AddButton(ByVal sKey As String, ByVal sTip As String)
    Dim b As MSComctlLib.Button
    Set b = tbMain.Buttons.Add(, sKey, , tbrDefault, sKey)
    b.ToolTipText = sTip
End Sub

Private Sub AddSeparator()
    tbMain.Buttons.Add , , , tbrSeparator
End Sub

Private Sub BuildStatusBar()
    Dim p As MSComctlLib.Panel
    sbMain.Panels.Clear
    Set p = sbMain.Panels.Add(, "msg", "Ready")
    p.AutoSize = sbrSpring
    Set p = sbMain.Panels.Add(, "units", "mm")
    p.AutoSize = sbrContents
    p.MinWidth = 600
    Set p = sbMain.Panels.Add(, "fps", "")
    p.AutoSize = sbrContents
    p.MinWidth = 1200
End Sub

Public Sub SetStatus(ByVal s As String)
    sbMain.Panels("msg").Text = s
End Sub

Public Sub SetFps(ByVal s As String)
    sbMain.Panels("fps").Text = s
End Sub

Private Sub tbMain_ButtonClick(ByVal Button As MSComctlLib.Button)
    RunCommand Button.Key
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

' Open and Save As dialogs. Returns "" on Cancel.
Public Function AskFileName(ByVal bSave As Boolean, ByVal sDefault As String) As String
    AskFileName = FileDialog(Me.hWnd, bSave, sDefault)
End Function

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
