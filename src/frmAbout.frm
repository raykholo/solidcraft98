VERSION 5.00
Begin VB.Form frmAbout
   BorderStyle     =   3  'Fixed Dialog
   Caption         =   "About SolidCraft 98"
   ClientHeight    =   3480
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   5760
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.PictureBox picLogo
      AutoRedraw      =   -1  'True
      BackColor       =   &H00800000&
      Height          =   1440
      Left            =   240
      ScaleHeight     =   92
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   92
      TabIndex        =   1
      Top             =   240
      Width           =   1440
   End
   Begin VB.CommandButton cmdOK
      Cancel          =   -1  'True
      Caption         =   "OK"
      Default         =   -1  'True
      Height          =   375
      Left            =   4440
      TabIndex        =   0
      Top             =   2940
      Width           =   1095
   End
   Begin VB.Label lblInfo
      Height          =   1335
      Left            =   1920
      TabIndex        =   3
      Top             =   1080
      Width           =   3615
   End
   Begin VB.Label lblTitle
      Caption         =   "SolidCraft 98"
      BeginProperty Font
         Name            =   "Arial"
         Size            =   14.25
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   375
      Left            =   1920
      TabIndex        =   2
      Top             =   240
      Width           =   3615
   End
   Begin VB.Label lblVersion
      Height          =   255
      Left            =   1920
      TabIndex        =   4
      Top             =   660
      Width           =   3615
   End
   Begin VB.Line linSep
      BorderColor     =   &H00808080&
      X1              =   240
      X2              =   5520
      Y1              =   2700
      Y2              =   2700
   End
   Begin VB.Label lblWarn
      Caption         =   "Warning: this computer program is protected by a sense of humour."
      Height          =   495
      Left            =   240
      TabIndex        =   5
      Top             =   2880
      Width           =   3975
   End
End
Attribute VB_Name = "frmAbout"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmAbout - Help, About. Fixed size, logo top left, OK bottom right.
Option Explicit

Private Type MEMORYSTATUSEX
    dwLength As Long
    dwMemoryLoad As Long
    ullTotalPhysLo As Long
    ullTotalPhysHi As Long
    ullAvailPhysLo As Long
    ullAvailPhysHi As Long
    ullTotalPageFileLo As Long
    ullTotalPageFileHi As Long
    ullAvailPageFileLo As Long
    ullAvailPageFileHi As Long
    ullTotalVirtualLo As Long
    ullTotalVirtualHi As Long
    ullAvailVirtualLo As Long
    ullAvailVirtualHi As Long
    ullAvailExtendedVirtualLo As Long
    ullAvailExtendedVirtualHi As Long
End Type

Private Declare Function GlobalMemoryStatusEx Lib "kernel32" (lpBuffer As MEMORYSTATUSEX) As Long

Private Sub Form_Load()
    Gradient picLogo, RGB(0, 0, 160), RGB(0, 0, 0)
    DrawLogo picLogo, 46, 24, 11, RGB(255, 255, 0)
    lblVersion.Caption = AppVersion() & "  (" & APP_BUILD & ")"
    lblInfo.Caption = APP_EDITION & vbCrLf & vbCrLf & _
        "This product is licensed to:" & vbCrLf & _
        "    Machine Shop, Back Office PC" & vbCrLf & vbCrLf & _
        "Physical memory available to Windows: " & MemoryKB() & " KB"
End Sub

' The real figure, formatted like it's still impressive.
Private Function MemoryKB() As String
    Dim m As MEMORYSTATUSEX, kb As Double
    m.dwLength = Len(m)
    If GlobalMemoryStatusEx(m) = 0 Then
        MemoryKB = "65,536"
        Exit Function
    End If
    kb = (ULong(m.ullTotalPhysHi) * 4294967296# + ULong(m.ullTotalPhysLo)) / 1024
    MemoryKB = Format$(kb, "#,##0")
End Function

Private Function ULong(ByVal v As Long) As Double
    If v < 0 Then ULong = v + 4294967296# Else ULong = v
End Function

Private Sub cmdOK_Click()
    Unload Me
End Sub
