VERSION 5.00
Begin VB.Form frmCalPin
   BackColor       =   &H00E1FFFF&
   BorderStyle     =   1  'Fixed Single
   ClientHeight    =   660
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   3600
   ControlBox      =   0   'False
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   Begin VB.CommandButton cmdClose
      Caption         =   "x"
      Height          =   240
      Left            =   3315
      TabIndex        =   0
      Top             =   45
      Width           =   240
   End
   Begin VB.Label lblTip
      BackStyle       =   0  'Transparent
      Caption         =   "Boxes want to be extruded. Press E."
      Height          =   255
      Left            =   90
      TabIndex        =   2
      Top             =   330
      Width           =   3420
   End
   Begin VB.Label lblTitle
      BackStyle       =   0  'Transparent
      Caption         =   "Cal's tip, pinned for you:"
      Height          =   255
      Left            =   90
      TabIndex        =   1
      Top             =   75
      Width           =   3180
   End
End
Attribute VB_Name = "frmCalPin"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmCalPin - with Turbo on, "Don't show me this tip again" doesn't hide
' Cal's tip: it pins it, a small note in the corner. The x really closes it.
' Nothing is saved; it's gone when SolidCraft 98 closes.
Option Explicit

Private Declare Function ShowWindow Lib "user32" (ByVal hWnd As Long, ByVal nCmdShow As Long) As Long
Private Declare Function SetWindowLong Lib "user32" Alias "SetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) As Long
Private Const SW_SHOWNOACTIVATE As Long = 4
Private Const GWL_HWNDPARENT As Long = -8

Private Sub Form_Load()
    ClassicLook Me
    lblTitle.FontBold = True
End Sub

' Pins the tip where Cal was: the bottom right of the main window.
Public Sub Pin()
    Load Me
    Move frmMain.Left + frmMain.Width - Width - 480, frmMain.Top + frmMain.Height - Height - 900
    ' Like Cal: on top of the main window, without taking the focus.
    SetWindowLong hWnd, GWL_HWNDPARENT, frmMain.hWnd
    ShowWindow hWnd, SW_SHOWNOACTIVATE
End Sub

Private Sub cmdClose_Click()
    Unload Me
    frmMain.SetStatus "Cal will remember."
End Sub
