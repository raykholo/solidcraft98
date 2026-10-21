Attribute VB_Name = "modClassic"
' modClassic - keeps the 1998 look on a modern PC.
'
' The list view needs version 6 of the common controls (see
' SolidCraft98.exe.manifest), and version 6 draws everything in the current
' Windows theme. Turning the theme off per window gives back flat grey
' buttons, sunken boxes and square headers.
' Also home to TextAt, because Print forgets ForeColor under twinBASIC.
' (On Error Resume Next lives in ClassicLook: the never-crash policy, for once correct.)
Option Explicit

Private Declare Function SetWindowTheme Lib "uxtheme" (ByVal hWnd As Long, ByVal pszSubAppName As Long, ByVal pszSubIdList As Long) As Long
Private Declare Function SendMessage Lib "user32" Alias "SendMessageA" (ByVal hWnd As Long, ByVal wMsg As Long, ByVal wParam As Long, ByVal lParam As Long) As Long
Private Declare Function SetTextColor Lib "gdi32" (ByVal hdc As Long, ByVal crColor As Long) As Long
Private Declare Function SetBkMode Lib "gdi32" (ByVal hdc As Long, ByVal nBkMode As Long) As Long
Private Declare Function TextOut Lib "gdi32" Alias "TextOutA" (ByVal hdc As Long, ByVal x As Long, ByVal y As Long, ByVal lpString As String, ByVal nCount As Long) As Long
Private Declare Function RedrawWindow Lib "user32" (ByVal hWnd As Long, ByVal lprcUpdate As Long, ByVal hrgnUpdate As Long, ByVal fuRedraw As Long) As Long

Private Const LVM_GETHEADER As Long = &H101F
Private Const BK_TRANSPARENT As Long = 1
Private Const RDW_INVALIDATE As Long = &H1
Private Const RDW_ERASE As Long = &H4
Private Const RDW_UPDATENOW As Long = &H100

Private mBlank As String

' Strips the theme from every control on a form.
Public Sub ClassicLook(ByVal frm As Object)
    Dim c As Object
    On Error Resume Next
    mBlank = " " & vbNullChar
    For Each c In frm.Controls
        Unthemed c.hWnd
        If TypeOf c Is ListView Then Unthemed SendMessage(c.hWnd, LVM_GETHEADER, 0, 0)
    Next c
End Sub

' A list view's column headers lose the first letter or two of each title
' when its window comes to the front from behind another; paint them again.
Public Sub RepaintHeaders(ByVal lvw As Object)
    Dim h As Long
    On Error Resume Next
    h = SendMessage(lvw.hWnd, LVM_GETHEADER, 0, 0)
    If h <> 0 Then RedrawWindow h, 0, 0, RDW_INVALIDATE Or RDW_ERASE Or RDW_UPDATENOW
End Sub

Private Sub Unthemed(ByVal hWnd As Long)
    If hWnd = 0 Then Exit Sub
    SetWindowTheme hWnd, StrPtr(mBlank), StrPtr(mBlank)
End Sub

' Text in colour, at (x, y) in pixels, in the picture's current font.
' The picture should have ScaleMode = vbPixels. Call pic.Refresh when done.
Public Sub TextAt(ByVal pic As PictureBox, ByVal x As Single, ByVal y As Single, ByVal s As String, ByVal c As Long)
    SetBkMode pic.hDC, BK_TRANSPARENT
    SetTextColor pic.hDC, c
    TextOut pic.hDC, x, y, s, Len(s)
End Sub
