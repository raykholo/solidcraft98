VERSION 5.00
Begin VB.Form frmCredits
   BackColor       =   &H00000000&
   BorderStyle     =   0  'None
   ClientHeight    =   6000
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   8400
   ControlBox      =   0   'False
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.Timer tmrFrame
      Enabled         =   0   'False
      Interval        =   33
      Left            =   120
      Top             =   120
   End
   Begin VB.PictureBox picDemo
      AutoRedraw      =   -1  'True
      BackColor       =   &H00000000&
      BorderStyle     =   0  'None
      Height          =   6000
      Left            =   0
      ScaleHeight     =   400
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   560
      TabIndex        =   0
      Top             =   0
      Width           =   8400
   End
End
Attribute VB_Name = "frmCredits"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmCredits - type WIN98 in the About box. A starfield, a sine scroller,
' copper bars, and credits for people who never existed. Any key leaves.
Option Explicit

Private Const STARS As Integer = 90
Private mSx(1 To STARS) As Single
Private mSy(1 To STARS) As Single
Private mSz(1 To STARS) As Single
Private mT As Long
Private mScroll As Single
Private mLines() As String
Private mMsg As String

Private Sub Form_Load()
    Dim i As Integer
    Randomize
    For i = 1 To STARS
        mSx(i) = Rnd * 2 - 1: mSy(i) = Rnd * 2 - 1: mSz(i) = Rnd
    Next i
    mLines = Split( _
        "SOLIDCRAFT 98|THE PROFESSIONAL EDITION||" & _
        "A FORTY-THOUSAND-LINE PRODUCTION||" & _
        "GEOMETRY KERNEL|MODKERNEL.BAS (ALL OF IT)||" & _
        "CONSTRAINT SOLVER|THE VARIANT SQUAD||" & _
        "CHIEF REGENERATE CLICKER|PRESS F5 THREE TIMES||" & _
        "ICONS|16 COLOURS, NO UNDO||" & _
        "FILE FORMAT|PUT #1, , DESIGN||" & _
        "QUALITY ASSURANCE|THE MACHINE SHOP||" & _
        "SOUND|THE HARD DISK, SEEKING||" & _
        "SPECIAL THANKS|THE ONE PC NOBODY IS ALLOWED TO UPDATE||" & _
        "NO PARTS WERE HARMED IN THE MAKING OF THIS SOFTWARE||||" & _
        "PRESS ANY KEY", "|")
    mMsg = "   GREETINGS TO EVERYONE STILL RUNNING WINDOWS 98 SE ...  " & _
           "TURBO OFF IS FASTER THAN TURBO ON ...  BEST VIEWED AT 800 X 600 ...  "
    mScroll = picDemo.ScaleHeight
    tmrFrame.Enabled = True
End Sub

Private Sub tmrFrame_Timer()
    Dim p As PictureBox, i As Integer, x As Single, y As Single, c As Long
    Dim cx As Single, cy As Single, k As Integer, ch As String, yy As Single
    Set p = picDemo
    mT = mT + 1
    p.Line (0, 0)-(p.ScaleWidth, p.ScaleHeight), 0, BF
    cx = p.ScaleWidth / 2: cy = p.ScaleHeight / 2

    ' copper bars
    For k = 0 To 2
        yy = cy + Sin((mT + k * 25) / 15) * 120
        For i = 0 To 7
            c = RGB(40 + i * 25, 0, 120 - i * 10)
            If k = 1 Then c = RGB(0, 40 + i * 25, 100)
            If k = 2 Then c = RGB(40 + i * 25, 40 + i * 25, 0)
            p.Line (0, yy - 8 + i)-(p.ScaleWidth, yy - 8 + i), c
            p.Line (0, yy + 8 - i)-(p.ScaleWidth, yy + 8 - i), c
        Next i
    Next k

    ' starfield
    For i = 1 To STARS
        mSz(i) = mSz(i) - 0.01
        If mSz(i) <= 0.02 Then mSx(i) = Rnd * 2 - 1: mSy(i) = Rnd * 2 - 1: mSz(i) = 1
        x = cx + mSx(i) / mSz(i) * cx * 0.5
        y = cy + mSy(i) / mSz(i) * cy * 0.5
        c = RGB(255 * (1 - mSz(i)), 255 * (1 - mSz(i)), 255 * (1 - mSz(i)))
        p.PSet (x, y), c
        If mSz(i) < 0.3 Then p.PSet (x + 1, y), c
    Next i

    ' the credits, rolling up
    p.FontName = "Courier New"
    p.FontBold = True
    p.FontSize = 12
    mScroll = mScroll - 1.2
    For i = 0 To UBound(mLines)
        y = mScroll + i * 22
        If y > -20 And y < p.ScaleHeight Then
            x = (p.ScaleWidth - p.TextWidth(mLines(i))) / 2
            If i Mod 3 = 0 Then c = RGB(255, 255, 0) Else c = RGB(0, 255, 255)
            TextAt p, x, y, mLines(i), c
        End If
    Next i
    If mScroll < -(UBound(mLines) + 1) * 22 Then mScroll = p.ScaleHeight

    ' the sine scroller along the bottom
    p.FontSize = 14
    x = p.ScaleWidth - ((mT * 4) Mod (p.TextWidth(mMsg) + p.ScaleWidth))
    For k = 1 To Len(mMsg)
        ch = Mid$(mMsg, k, 1)
        If x > -20 And x < p.ScaleWidth Then
            TextAt p, x, p.ScaleHeight - 40 + Sin((x + mT * 6) / 30) * 10, ch, RGB(255, 128 + 127 * Sin((k + mT) / 6), 64)
        End If
        x = x + p.TextWidth(ch)
    Next k
    p.Refresh
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    tmrFrame.Enabled = False
    Unload Me
End Sub

Private Sub picDemo_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    tmrFrame.Enabled = False
    Unload Me
End Sub
