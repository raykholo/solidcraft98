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

Private Declare Function GetFileAttributes Lib "kernel32" Alias "GetFileAttributesA" (ByVal lpFileName As String) As Long
Private Const INVALID_FILE_ATTRIBUTES As Long = -1
Private Const FILE_ATTRIBUTE_DIRECTORY As Long = &H10

Private Const OFN_HIDEREADONLY As Long = &H4
Private Const OFN_OVERWRITEPROMPT As Long = &H2
Private Const OFN_PATHMUSTEXIST As Long = &H800
Private Const OFN_FILEMUSTEXIST As Long = &H1000

Public Const PART_EXT As String = "sc98"

' sFilter is "Description|*.ext", sExt the default extension. Both default to parts.
' Whether a file or folder is there. GetFileAttributes, rather than Dir$,
' because it works the same on every Windows since NT, and on ReactOS.
Public Function FileExists(ByVal sPath As String) As Boolean
    Dim a As Long
    a = GetFileAttributes(sPath)
    FileExists = (a <> INVALID_FILE_ATTRIBUTES) And ((a And FILE_ATTRIBUTE_DIRECTORY) = 0)
End Function

Public Function FolderExists(ByVal sPath As String) As Boolean
    Dim a As Long
    a = GetFileAttributes(sPath)
    FolderExists = (a <> INVALID_FILE_ATTRIBUTES) And ((a And FILE_ATTRIBUTE_DIRECTORY) <> 0)
End Function

' Where dialogs start: the user's documents folder, not wherever the
' program was started from (which may be a CD).
Private Function MyDocuments() As String
    Dim s As String
    s = Environ$("USERPROFILE")
    If Len(s) = 0 Then Exit Function
    If FolderExists(s & "\Documents") Then
        MyDocuments = s & "\Documents"
    ElseIf FolderExists(s & "\My Documents") Then
        MyDocuments = s & "\My Documents"
    Else
        MyDocuments = s
    End If
End Function

Public Function FileDialog(ByVal hOwner As Long, ByVal bSave As Boolean, ByVal sDefault As String, _
                           Optional ByVal sFilter As String = "", Optional ByVal sExt As String = "") As String
    Dim ofn As OPENFILENAME, r As Long, p As Long
    If Len(sFilter) = 0 Then sFilter = "SolidCraft 98 Parts (*." & PART_EXT & ")|*." & PART_EXT
    If Len(sExt) = 0 Then sExt = PART_EXT
    ofn.lStructSize = Len(ofn)
    ofn.hwndOwner = hOwner
    ofn.lpstrFilter = Replace(sFilter, "|", vbNullChar) & vbNullChar & _
                      "All Files (*.*)" & vbNullChar & "*.*" & vbNullChar & vbNullChar
    ofn.nFilterIndex = 1
    ofn.lpstrInitialDir = MyDocuments()
    ofn.lpstrFile = sDefault & String$(260 - Len(sDefault), vbNullChar)
    ofn.nMaxFile = 260
    ofn.lpstrDefExt = sExt
    ofn.Flags = OFN_HIDEREADONLY Or OFN_PATHMUSTEXIST
    If bSave Then
        If sExt = PART_EXT Then ofn.lpstrTitle = "Save Part As" Else ofn.lpstrTitle = "Save As"
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
