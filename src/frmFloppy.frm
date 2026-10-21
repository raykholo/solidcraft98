VERSION 5.00
Begin VB.Form frmFloppy
   BorderStyle     =   3  'Fixed Dialog
   Caption         =   "Copying..."
   ClientHeight    =   2160
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   5400
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.Timer tmrCopy
      Enabled         =   0   'False
      Interval        =   50
      Left            =   4800
      Top             =   120
   End
   Begin VB.PictureBox picDisk
      AutoRedraw      =   -1  'True
      BorderStyle     =   0  'None
      Height          =   720
      Left            =   240
      ScaleHeight     =   48
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   48
      TabIndex        =   3
      Top             =   240
      Width           =   720
   End
   Begin VB.PictureBox picBar
      AutoRedraw      =   -1  'True
      BackColor       =   &H00FFFFFF&
      Height          =   300
      Left            =   240
      ScaleHeight     =   16
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   324
      TabIndex        =   2
      Top             =   1140
      Width           =   4920
   End
   Begin VB.CommandButton cmdCancel
      Cancel          =   -1  'True
      Caption         =   "Cancel"
      Height          =   375
      Left            =   4080
      TabIndex        =   0
      Top             =   1620
      Width           =   1095
   End
   Begin VB.Label lblWhat
      Height          =   735
      Left            =   1140
      TabIndex        =   1
      Top             =   240
      Width           =   4035
   End
End
Attribute VB_Name = "frmFloppy"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmFloppy - "copying" a part to a stack of 1.44 MB floppies.
' Nothing is written anywhere from here: the part was already saved to the
' hard disk before this dialog opened. It's a progress bar and some MsgBoxes.
Option Explicit

Private mName As String
Private mTotal As Double
Private mDone As Double
Private mDisks As Integer
Private mDisk As Integer
Private mFinished As Boolean

' Shows the copy for sName, sBytes long. True if it got to the last disk.
Public Function Run(ByVal sName As String, ByVal nBytes As Double) As Boolean
    mName = sName
    mTotal = nBytes
    mDone = 0
    mDisks = -Int(-nBytes / FLOPPY_BYTES)
    mDisk = 1
    mFinished = False
    Show vbModal, frmMain
    Run = mFinished
End Function

Private Sub Form_Load()
    ClassicLook Me
    DrawDisk
    ShowWhat
    tmrCopy.Enabled = True
End Sub

Private Sub ShowWhat()
    lblWhat.Caption = "Copying " & mName & " to A:\" & vbCrLf & vbCrLf & _
        "Disk " & mDisk & " of " & mDisks & "   (" & Format$(mDone / 1024, "#,##0") & " KB of " & _
        Format$(mTotal / 1024, "#,##0") & " KB)"
End Sub

' A 3 1/2" disk, drawn: blue body, metal shutter, white label.
Private Sub DrawDisk()
    With picDisk
        .Line (0, 0)-(47, 47), &HC0C0C0, BF
        .Line (4, 2)-(44, 45), &H802000, BF
        .Line (14, 2)-(36, 16), &HC0C0C0, BF
        .Line (28, 4)-(32, 14), &H404040, BF
        .Line (9, 24)-(40, 45), &HFFFFFF, BF
        .Line (12, 29)-(36, 29), &HC0C0C0
        .Line (12, 34)-(36, 34), &HC0C0C0
        .Line (12, 39)-(30, 39), &HC0C0C0
        .Refresh
    End With
End Sub

Private Sub DrawBar()
    Dim f As Double, w As Long
    f = (mDone - (mDisk - 1) * CDbl(FLOPPY_BYTES)) / FLOPPY_BYTES
    If f > 1 Then f = 1
    picBar.Line (0, 0)-(picBar.ScaleWidth, picBar.ScaleHeight), &HFFFFFF, BF
    w = (picBar.ScaleWidth - 4) * f
    ' chunky blocks, like the progress bars of the time
    Dim x As Long
    For x = 2 To w Step 9
        picBar.Line (x, 2)-(x + 6, picBar.ScaleHeight - 3), &H800000, BF
    Next x
    picBar.Refresh
End Sub

Private Sub tmrCopy_Timer()
    Dim diskEnd As Double
    mDone = mDone + 23000 + Rnd * 9000    ' about 500 KB a second, which was fast
    diskEnd = CDbl(mDisk) * FLOPPY_BYTES
    If mDone >= mTotal Then
        mDone = mTotal
        DrawBar
        ShowWhat
        tmrCopy.Enabled = False
        mFinished = True
        Unload Me
        Exit Sub
    End If
    If mDone >= diskEnd Then
        mDone = diskEnd
        DrawBar
        ShowWhat
        tmrCopy.Enabled = False
        If MsgBox("Please insert disk " & (mDisk + 1) & " of " & mDisks & " into drive A:" & vbCrLf & vbCrLf & _
            "Label it """ & mName & " - Disk " & (mDisk + 1) & """ so you can find it later.", _
            vbOKCancel Or vbInformation, "Insert Disk") = vbCancel Then
            Unload Me
            Exit Sub
        End If
        mDisk = mDisk + 1
        tmrCopy.Enabled = True
    End If
    DrawBar
    ShowWhat
End Sub

Private Sub cmdCancel_Click()
    tmrCopy.Enabled = False
    Unload Me
End Sub
