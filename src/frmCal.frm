VERSION 5.00
Begin VB.Form frmCal
   BackColor       =   &H00E1FFFF&
   BorderStyle     =   1  'Fixed Single
   ClientHeight    =   2520
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4200
   ControlBox      =   0   'False
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   Begin VB.PictureBox picCal
      AutoRedraw      =   -1  'True
      BackColor       =   &H00E1FFFF&
      BorderStyle     =   0  'None
      Height          =   720
      Left            =   120
      ScaleHeight     =   48
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   48
      TabIndex        =   4
      Top             =   120
      Width           =   720
   End
   Begin VB.CommandButton cmdHelp
      Caption         =   "&Get help with drawing the box"
      Height          =   375
      Left            =   960
      TabIndex        =   0
      Top             =   1140
      Width           =   3075
   End
   Begin VB.CommandButton cmdNoHelp
      Caption         =   "&Just draw the box without help"
      Height          =   375
      Left            =   960
      TabIndex        =   1
      Top             =   1560
      Width           =   3075
   End
   Begin VB.CommandButton cmdNever
      Caption         =   "&Don't show me this tip again"
      Height          =   375
      Left            =   960
      TabIndex        =   2
      Top             =   1980
      Width           =   3075
   End
   Begin VB.Label lblSay
      BackStyle       =   0  'Transparent
      Caption         =   "It looks like you're drawing a box."
      Height          =   915
      Left            =   960
      TabIndex        =   3
      Top             =   180
      Width           =   3075
   End
End
Attribute VB_Name = "frmCal"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmCal - Cal, the office-assistant caliper. Our own pixel art.
' Pops up the first time you sketch a rectangle in a run. Turbo on or off.
Option Explicit

Public Silenced As Boolean
Private mShown As Boolean        ' once per run is plenty

Private Declare Function ShowWindow Lib "user32" (ByVal hWnd As Long, ByVal nCmdShow As Long) As Long
Private Declare Function SetWindowLong Lib "user32" Alias "SetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) As Long
Private Const SW_SHOWNOACTIVATE As Long = 4
Private Const GWL_HWNDPARENT As Long = -8

Private Sub Form_Load()
    ClassicLook Me
    picCal.Cls
    PaintIconScaled picCal, "Cal", 0, 0, 3
    picCal.Refresh
End Sub

' Shows Cal near the bottom right of the main window.
Public Sub Pop(ByVal sSay As String)
    If Silenced Or mShown Then Exit Sub
    mShown = True
    Load Me
    lblSay.Caption = sSay & vbCrLf & vbCrLf & "Would you like help?"
    cmdHelp.Visible = True
    cmdNoHelp.Caption = "&Just draw the box without help"
    Move frmMain.Left + frmMain.Width - Width - 480, frmMain.Top + frmMain.Height - Height - 900
    ' Owned by the main window so it stays on top of it, but shown without
    ' taking the focus: you can keep typing while Cal watches.
    SetWindowLong hWnd, GWL_HWNDPARENT, frmMain.hWnd
    ShowWindow hWnd, SW_SHOWNOACTIVATE
End Sub

Private Sub cmdHelp_Click()
    lblSay.Caption = "Here's a tip: boxes usually want to be extruded." & vbCrLf & _
        "Press E. If that doesn't work, press E harder."
    cmdHelp.Visible = False
    cmdNoHelp.Caption = "&Thanks, Cal"
End Sub

Private Sub cmdNoHelp_Click()
    Unload Me
End Sub

Private Sub cmdNever_Click()
    Silenced = True
    Unload Me
    ' Turbo: the authentic 1999 reading of "don't show this again"
    If Turbo Then
        frmCalPin.Pin
    Else
        MsgBox "OK. Cal won't show this tip again." & vbCrLf & "(Until you restart SolidCraft 98.)", vbInformation, "Cal"
    End If
End Sub

Private Sub picCal_Click()
    lblSay.Caption = "Did you know? Every SolidCraft 98 file is also a perfectly good door stop, if you print it out."
End Sub
