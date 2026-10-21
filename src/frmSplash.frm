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
' frmSplash - the startup splash, all of it drawn in code once it's on screen.
Option Explicit

Public Sub Paint()
    Dim p As PictureBox
    Set p = picSplash
    Gradient p, RGB(0, 0, 128), RGB(0, 0, 0)
    DrawLogo p, 90, 70, 26, RGB(255, 255, 0)
    p.FontName = "Times New Roman"
    p.FontBold = True
    p.FontItalic = True
    p.FontSize = 30
    SayAt p, 190, 60, "SolidCraft", vbWhite
    p.FontSize = 40
    SayAt p, 330, 100, "98", RGB(255, 255, 0)
    p.FontName = "Arial"
    p.FontItalic = False
    p.FontBold = False
    p.FontSize = 9
    SayAt p, 192, 112, APP_EDITION, RGB(192, 192, 192)
    SayAt p, 16, 230, AppVersion() & "  " & APP_BUILD, RGB(192, 192, 192)
    SayAt p, 16, 246, "Copyright (C) 1998-1999 SolidCraft Software. Made with Line and Circle.", RGB(192, 192, 192)
    p.Line (0, 0)-(p.ScaleWidth - 1, p.ScaleHeight - 1), RGB(128, 128, 128), B
End Sub

Private Sub SayAt(ByVal p As PictureBox, ByVal x As Single, ByVal y As Single, ByVal s As String, ByVal c As Long)
    TextAt p, x, y, s, c
    p.Refresh
End Sub

' Shows a loading message and pauses just long enough to read it.
Public Sub Progress(ByVal s As String)
    Dim t As Single
    picSplash.Line (14, 206)-(430, 222), RGB(0, 0, 40), BF
    SayAt picSplash, 16, 207, s, vbWhite
    picSplash.Refresh
    t = Timer
    Do While Timer - t < 0.35 And Timer >= t
        DoEvents
    Loop
End Sub
