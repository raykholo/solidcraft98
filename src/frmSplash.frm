VERSION 5.00
Begin VB.Form frmSplash
   BorderStyle     =   0  'None
   ClientHeight    =   4200
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   6600
   ControlBox      =   0   'False
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   2  'CenterScreen
   Begin VB.PictureBox picSplash
      AutoRedraw      =   -1  'True
      BorderStyle     =   0  'None
      Height          =   4200
      Left            =   0
      ScaleHeight     =   280
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   440
      TabIndex        =   0
      Top             =   0
      Width           =   6600
   End
End
Attribute VB_Name = "frmSplash"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmSplash - the startup splash. All of it drawn in Form_Load.
Option Explicit

Private Sub Form_Load()
    Dim p As PictureBox
    Set p = picSplash
    Gradient p, RGB(0, 0, 128), RGB(0, 0, 0)
    DrawLogo p, 90, 70, 26, RGB(255, 255, 0)
    p.ForeColor = vbWhite
    p.FontName = "Times New Roman"
    p.FontBold = True
    p.FontItalic = True
    p.FontSize = 30
    p.CurrentX = 190: p.CurrentY = 60
    p.Print "SolidCraft"
    p.ForeColor = RGB(255, 255, 0)
    p.FontSize = 40
    p.CurrentX = 330: p.CurrentY = 100
    p.Print "98"
    p.FontName = "Arial"
    p.FontItalic = False
    p.FontBold = False
    p.FontSize = 9
    p.ForeColor = RGB(192, 192, 192)
    p.CurrentX = 192: p.CurrentY = 112
    p.Print APP_EDITION
    p.CurrentX = 16: p.CurrentY = 230
    p.Print AppVersion() & "  " & APP_BUILD
    p.CurrentX = 16: p.CurrentY = 246
    p.Print "Copyright (C) 1998-1999 SolidCraft Software. Made with Line and Circle."
    p.Line (0, 0)-(p.ScaleWidth - 1, p.ScaleHeight - 1), RGB(128, 128, 128), B
End Sub

' Shows a loading message and pauses just long enough to read it.
Public Sub Progress(ByVal s As String)
    Dim t As Single
    picSplash.Line (14, 206)-(430, 222), RGB(0, 0, 40), BF
    picSplash.ForeColor = vbWhite
    picSplash.CurrentX = 16: picSplash.CurrentY = 207
    picSplash.Print s
    picSplash.Refresh
    t = Timer
    Do While Timer - t < 0.35 And Timer >= t
        DoEvents
    Loop
End Sub
