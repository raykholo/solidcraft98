Attribute VB_Name = "modDoc"
' modDoc - the open parts. Forms can't hold a public Type, so the designs
' live here and each part window just remembers its slot number.
Option Explicit

Public Const MAX_DOCS As Integer = 16

Public Docs(1 To MAX_DOCS) As TDesign
Public DocPath(1 To MAX_DOCS) As String
Public DocDirty(1 To MAX_DOCS) As Boolean
Public DocInUse(1 To MAX_DOCS) As Boolean

Private mUntitled As Integer

' Takes a free slot and starts an empty part in it. Returns 0 if all 16 are open.
Public Function NewDocSlot() As Integer
    Dim i As Integer
    For i = 1 To MAX_DOCS
        If Not DocInUse(i) Then
            mUntitled = mUntitled + 1
            NewDesign Docs(i), "Part" & mUntitled
            DocPath(i) = ""
            DocDirty(i) = False
            DocInUse(i) = True
            NewDocSlot = i
            Exit Function
        End If
    Next i
End Function

Public Sub FreeDocSlot(ByVal i As Integer)
    If i >= 1 And i <= MAX_DOCS Then DocInUse(i) = False
End Sub

Public Function DocTitle(ByVal i As Integer) As String
    DocTitle = RTrim$(Docs(i).Title)
    If DocDirty(i) Then DocTitle = DocTitle & " *"
End Function

Public Function FileTitle(ByVal sPath As String) As String
    Dim p As Long
    p = InStrRev(sPath, "\")
    FileTitle = Mid$(sPath, p + 1)
    p = InStrRev(FileTitle, ".")
    If p > 1 Then FileTitle = Left$(FileTitle, p - 1)
End Function
