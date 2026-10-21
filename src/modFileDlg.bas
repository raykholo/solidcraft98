Attribute VB_Name = "modFileDlg"
' modFileDlg - Open and Save As through comdlg32, no OCX needed.
Option Explicit

Private Type OPENFILENAME
    lStructSize As Long
    hwndOwner As Long
    hInstance As Long
    lpstrFilter As String
    lpstrCustomFilter As String
    nMaxCustFilter As Long
    nFilterIndex As Long
    lpstrFile As String
    nMaxFile As Long
    lpstrFileTitle As String
    nMaxFileTitle As Long
    lpstrInitialDir As String
    lpstrTitle As String
    Flags As Long
    nFileOffset As Integer
    nFileExtension As Integer
    lpstrDefExt As String
    lCustData As Long
    lpfnHook As Long
    lpTemplateName As String
End Type

Private Declare Function GetOpenFileName Lib "comdlg32.dll" Alias "GetOpenFileNameA" (pOpenfilename As OPENFILENAME) As Long
Private Declare Function GetSaveFileName Lib "comdlg32.dll" Alias "GetSaveFileNameA" (pOpenfilename As OPENFILENAME) As Long

Private Const OFN_HIDEREADONLY As Long = &H4
Private Const OFN_OVERWRITEPROMPT As Long = &H2
Private Const OFN_PATHMUSTEXIST As Long = &H800
Private Const OFN_FILEMUSTEXIST As Long = &H1000

Public Const PART_EXT As String = "sc98"

Public Function FileDialog(ByVal hOwner As Long, ByVal bSave As Boolean, ByVal sDefault As String) As String
    Dim ofn As OPENFILENAME, r As Long, p As Long
    ofn.lStructSize = Len(ofn)
    ofn.hwndOwner = hOwner
    ofn.lpstrFilter = "SolidCraft 98 Parts (*." & PART_EXT & ")" & vbNullChar & "*." & PART_EXT & vbNullChar & _
                      "All Files (*.*)" & vbNullChar & "*.*" & vbNullChar & vbNullChar
    ofn.nFilterIndex = 1
    ofn.lpstrFile = sDefault & String$(260 - Len(sDefault), vbNullChar)
    ofn.nMaxFile = 260
    ofn.lpstrDefExt = PART_EXT
    ofn.Flags = OFN_HIDEREADONLY Or OFN_PATHMUSTEXIST
    If bSave Then
        ofn.lpstrTitle = "Save Part As"
        ofn.Flags = ofn.Flags Or OFN_OVERWRITEPROMPT
        r = GetSaveFileName(ofn)
    Else
        ofn.lpstrTitle = "Open Part"
        ofn.Flags = ofn.Flags Or OFN_FILEMUSTEXIST
        r = GetOpenFileName(ofn)
    End If
    If r = 0 Then Exit Function
    p = InStr(ofn.lpstrFile, vbNullChar)
    If p > 0 Then FileDialog = Left$(ofn.lpstrFile, p - 1) Else FileDialog = ofn.lpstrFile
End Function
