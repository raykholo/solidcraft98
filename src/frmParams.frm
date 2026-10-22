VERSION 5.00
Begin VB.Form frmParams
   BorderStyle     =   3  'Fixed Dialog
   Caption         =   "Parameters"
   ClientHeight    =   2760
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   4680
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   0
      Left            =   2880
      TabIndex        =   0
      Top             =   240
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   1
      Left            =   2880
      TabIndex        =   1
      Top             =   720
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   2
      Left            =   2880
      TabIndex        =   2
      Top             =   1200
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   3
      Left            =   2880
      TabIndex        =   3
      Top             =   1680
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   4
      Left            =   2880
      TabIndex        =   4
      Top             =   2160
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   5
      Left            =   2880
      TabIndex        =   5
      Top             =   2640
      Width           =   1560
   End
   Begin VB.TextBox txtP
      Height          =   315
      Index           =   6
      Left            =   2880
      TabIndex        =   6
      Top             =   3120
      Width           =   1560
   End
   Begin VB.CommandButton cmdOK
      Caption         =   "OK"
      Default         =   -1  'True
      Height          =   375
      Left            =   1080
      TabIndex        =   7
      Top             =   2220
      Width           =   1095
   End
   Begin VB.CommandButton cmdCancel
      Cancel          =   -1  'True
      Caption         =   "Cancel"
      Height          =   375
      Left            =   2280
      TabIndex        =   8
      Top             =   2220
      Width           =   1095
   End
   Begin VB.CommandButton cmdHelp
      Caption         =   "&Help"
      Height          =   375
      Left            =   3480
      TabIndex        =   9
      Top             =   2220
      Width           =   1095
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   0
      Left            =   240
      TabIndex        =   10
      Top             =   285
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   1
      Left            =   240
      TabIndex        =   11
      Top             =   765
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   2
      Left            =   240
      TabIndex        =   12
      Top             =   1245
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   3
      Left            =   240
      TabIndex        =   13
      Top             =   1725
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   4
      Left            =   240
      TabIndex        =   14
      Top             =   2205
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   5
      Left            =   240
      TabIndex        =   15
      Top             =   2685
      Width           =   2600
   End
   Begin VB.Label lblP
      Caption         =   "Value"
      Height          =   255
      Index           =   6
      Left            =   240
      TabIndex        =   16
      Top             =   3165
      Width           =   2600
   End
End
Attribute VB_Name = "frmParams"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
' frmParams - the one dialog every command uses for its numbers.
' Fixed size, OK and Cancel bottom right, and a Help button.
'
' The numbers go through CDbl with no validation first, so "20mm" raises a
' real run-time error 13. We catch it and show it exactly the way the VB
' runtime would have, then let you fix it. It's a joke, not a crash.
Option Explicit

Private mCount As Integer
Private Const MAX_FIELDS As Integer = 7
Private mValues(0 To MAX_FIELDS - 1) As Double
Private mOK As Boolean
Private mMismatches As Integer     ' Turbo: how many type mismatches in a row

Private Sub Form_Load()
    ClassicLook Me
End Sub

' Shows the dialog. Prompts and defaults are "|"-separated. True if OK.
Public Function Ask(ByVal sTitle As String, ByVal sPrompts As String, ByVal sDefaults As String) As Boolean
    Dim p() As String, d() As String, i As Integer
    p = Split(sPrompts, "|")
    d = Split(sDefaults, "|")
    mCount = UBound(p) + 1
    If mCount > MAX_FIELDS Then mCount = MAX_FIELDS
    Caption = sTitle
    For i = 0 To MAX_FIELDS - 1
        lblP(i).Visible = (i < mCount)
        txtP(i).Visible = (i < mCount)
        If i < mCount Then
            lblP(i).Caption = p(i)
            If i <= UBound(d) Then txtP(i).Text = d(i) Else txtP(i).Text = "0"
        End If
    Next i
    LayoutButtons
    mOK = False
    mMismatches = 0
    Show vbModal, frmMain
    Ask = mOK
End Function

Public Function Value(ByVal i As Integer) As Double
    Value = mValues(i)
End Function

Private Sub LayoutButtons()
    Dim y As Single
    y = txtP(mCount - 1).Top + txtP(mCount - 1).Height + 300
    cmdOK.Top = y: cmdCancel.Top = y: cmdHelp.Top = y
    Height = (Height - ScaleHeight) + y + cmdOK.Height + 240
End Sub

Private Sub Form_Activate()
    txtP(0).SetFocus
    txtP(0).SelStart = 0
    txtP(0).SelLength = Len(txtP(0).Text)
End Sub

' Tabbing into a box selects what's in it, so typing replaces it.
Private Sub txtP_GotFocus(Index As Integer)
    txtP(Index).SelStart = 0
    txtP(Index).SelLength = Len(txtP(Index).Text)
End Sub

Private Sub cmdOK_Click()
    Dim i As Integer
    On Error GoTo BadNumber
    For i = 0 To mCount - 1
        mValues(i) = Evaluate(txtP(i).Text)
    Next i
    mMismatches = 0
    mOK = True
    Hide
    Exit Sub
BadNumber:
    If Err.Number = 11 Then
        DivideByZero i
    Else
        TypeMismatch i
    End If
End Sub

Private Sub SelectBox(ByVal i As Integer)
    txtP(i).SetFocus
    txtP(i).SelStart = 0
    txtP(i).SelLength = Len(txtP(i).Text)
End Sub

Private Sub DivideByZero(ByVal i As Integer)
    If Turbo Then
        frmFatal.Show vbModal
    Else
        MsgBox "Run-time error '11':" & vbCrLf & vbCrLf & "Division by zero", vbCritical, App.Title
    End If
    SelectBox i
End Sub

' What VB itself would have said. Then point at the box that caused it.
' With Turbo on it gets more personal each time, and on the fifth try it
' gives up and does what you meant.
Private Sub TypeMismatch(ByVal i As Integer)
    Dim t As String
    t = txtP(i).Text
    If Not Turbo Then
        MsgBox "Run-time error '13':" & vbCrLf & vbCrLf & "Type mismatch", vbCritical, App.Title
        SelectBox i
        Exit Sub
    End If
    mMismatches = mMismatches + 1
    Select Case mMismatches
    Case 1
        MsgBox "Run-time error '13':" & vbCrLf & vbCrLf & "Type mismatch", vbCritical, App.Title
    Case 2
        MsgBox "Run-time error '13':" & vbCrLf & vbCrLf & "Still a type mismatch", vbCritical, App.Title
    Case 3
        MsgBox "Run-time error '13':" & vbCrLf & vbCrLf & "It's a TextBox, not a mind reader.", vbCritical, App.Title
    Case 4
        MsgBox "Did you know?" & vbCrLf & vbCrLf & _
            "Val(""" & t & """) returns " & Val(t) & ". Val reads digits until it meets" & vbCrLf & _
            "something it doesn't understand, then stops and pretends" & vbCrLf & _
            "that's all you typed." & vbCrLf & vbCrLf & _
            "CDbl(""" & t & """) is stricter. It raises error 13. We use CDbl." & vbCrLf & _
            "Usually.", vbInformation, "Tip of the Day"
    Case Else
        MsgBox "Fine. " & Val(t) & " it is.", vbInformation, App.Title
        txtP(i).Text = CStr(Val(t))
        mMismatches = 0
        cmdOK_Click
        Exit Sub
    End Select
    SelectBox i
End Sub

Private Sub cmdCancel_Click()
    mOK = False
    Hide
End Sub

Private Sub cmdHelp_Click()
    RunCommand "Help"
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If UnloadMode = vbFormControlMenu Then
        Cancel = 1
        cmdCancel_Click
    End If
End Sub
