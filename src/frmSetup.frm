VERSION 5.00
Begin VB.Form frmSetup
   BackColor       =   &H00800000&
   BorderStyle     =   3  'Fixed Dialog
   Caption         =   "SolidCraft 98 Setup"
   ClientHeight    =   3000
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   6000
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.Timer tmrCopy
      Enabled         =   0   'False
      Interval        =   60
      Left            =   5400
      Top             =   120
   End
   Begin VB.PictureBox picSetup
      AutoRedraw      =   -1  'True
      BorderStyle     =   0  'None
      Height          =   3000
      Left            =   0
      ScaleHeight     =   200
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   400
      TabIndex        =   0
      Top             =   0
      Width           =   6000
   End
End
Attribute VB_Name = "frmSetup"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmSetup - DLL Hell, re-enacted. Turbo on, Help > About, Shift-click the logo.
' A setup program "copies" MSCOMCTL.OCX over itself, gets to 112%, and asks
' for a restart. Nothing is copied, registered or restarted: it's a picture
' of a progress bar.
Option Explicit

Private mPct As Double
Private mStep As Integer

Private Sub Form_Load()
    mPct = 0
    mStep = 0
    Paint
    tmrCopy.Enabled = True
End Sub

Private Sub Paint()
    Dim p As PictureBox, w As Long, x As Long, sFile As String
    Set p = picSetup
    Gradient p, RGB(0, 0, 160), RGB(0, 0, 32)
    p.FontName = "Arial"
    p.FontBold = True
    p.FontSize = 11
    TextAt p, 16, 12, "SolidCraft 98 Setup", vbWhite
    p.FontBold = False
    p.FontSize = 9
    Select Case mStep
    Case 0: sFile = "Checking for a newer version of MSCOMCTL.OCX..."
    Case 1: sFile = "A newer version exists. Copying the older one over it anyway..."
    Case Else: sFile = "Copying more than all of it..."
    End Select
    TextAt p, 16, 44, sFile, RGB(255, 255, 192)
    TextAt p, 16, 66, "Source:       C:\WINDOWS\SYSTEM\MSCOMCTL.OCX", vbWhite
    TextAt p, 16, 82, "Destination:  C:\WINDOWS\SYSTEM\MSCOMCTL.OCX", vbWhite
    ' the bar: grey well, blue blocks, and a percentage that won't stop at 100
    p.Line (16, 112)-(384, 132), &HC0C0C0, BF
    Bevel p, 16, 112, 369, 21, &H808080, &HFFFFFF
    w = 364 * IIf(mPct > 100, 1, mPct / 100)
    For x = 19 To 16 + w Step 10
        p.Line (x, 115)-(x + 7, 129), &H800000, BF
    Next x
    If mPct > 100 Then
        For x = 19 To 381 Step 10
            p.Line (x, 115)-(x + 7, 129), &HFF&, BF
        Next x
    End If
    TextAt p, 190, 140, Format$(mPct, "0") & "%", vbWhite
    TextAt p, 16, 172, "Please do not turn off your computer.", RGB(192, 192, 192)
    p.Refresh
End Sub

Private Sub tmrCopy_Timer()
    mPct = mPct + 1 + Rnd * 2
    If mPct > 30 Then mStep = 1
    If mPct > 100 Then mStep = 2
    If mPct >= 112 Then
        mPct = 112
        tmrCopy.Enabled = False
        Paint
        MsgBox "Setup has updated your system files." & vbCrLf & vbCrLf & _
            "Please restart Windows to complete setup." & vbCrLf & _
            "(Excel may not start afterwards. That's normal.)", vbExclamation, "SolidCraft 98 Setup"
        MsgBox "Just kidding. Nothing was copied and nothing needs restarting." & vbCrLf & _
            "Your Excel is fine.", vbInformation, "SolidCraft 98 Setup"
        Unload Me
        Exit Sub
    End If
    Paint
End Sub
