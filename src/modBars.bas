Attribute VB_Name = "modBars"
' modBars - a toolbar and a status bar drawn in PictureBoxes.
'
' MSCOMCTL.OCX isn't on every PC (it isn't on Windows 11 at all), so we
' draw our own, which is what half the shareware of 1998 did anyway.
' Flat buttons that pop up when the mouse is over them, Office 97 style.
Option Explicit

Private Type TButton
    Key As String
    Tip As String
    Left As Long
    Width As Long
    IsSep As Boolean
    Checked As Boolean
End Type

Private Type TPanel
    Key As String
    Text As String
    Width As Long        ' 0 = takes whatever is left
End Type

Public Const BAR_FACE As Long = &HC0C0C0
Public Const BAR_LIGHT As Long = &HFFFFFF
Public Const BAR_SHADOW As Long = &H808080
Public Const BAR_DARK As Long = &H0&

Private Const BTN_W As Long = 24
Private Const BTN_H As Long = 23
Private Const SEP_W As Long = 8
Private Const BAR_TOP As Long = 3

Private mButtons() As TButton
Private mCount As Integer
Private mHot As Integer
Private mDown As Integer
Private mPanels() As TPanel
Private mPanelCount As Integer

' ---- Toolbar ----

Public Sub ToolbarClear()
    mCount = 0
    mHot = 0
    mDown = 0
    ReDim mButtons(1 To 32)
End Sub

Public Sub ToolbarAdd(ByVal sKey As String, ByVal sTip As String)
    Dim x As Long
    mCount = mCount + 1
    If mCount > 1 Then x = mButtons(mCount - 1).Left + mButtons(mCount - 1).Width Else x = 4
    mButtons(mCount).Key = sKey
    mButtons(mCount).Tip = sTip
    mButtons(mCount).Left = x
    If Len(sKey) = 0 Then
        mButtons(mCount).IsSep = True
        mButtons(mCount).Width = SEP_W
    Else
        mButtons(mCount).Width = BTN_W
    End If
End Sub

' A latched button (like Turbo) stays pushed in while Checked.
Public Sub ToolbarSetChecked(ByVal pic As PictureBox, ByVal sKey As String, ByVal bChecked As Boolean)
    Dim i As Integer
    For i = 1 To mCount
        If mButtons(i).Key = sKey Then
            mButtons(i).Checked = bChecked
            DrawButton pic, i
            pic.Refresh
        End If
    Next i
End Sub

' For the remote control's read-out: button i (1 to ToolbarCount); False for
' a separator.
Public Function ToolbarCount() As Integer
    ToolbarCount = mCount
End Function

Public Function ToolbarButton(ByVal i As Integer, sKey As String, sTip As String, nLeft As Long, nWidth As Long, bChecked As Boolean) As Boolean
    If i < 1 Or i > mCount Then Exit Function
    If mButtons(i).IsSep Then Exit Function
    sKey = mButtons(i).Key: sTip = mButtons(i).Tip
    nLeft = mButtons(i).Left: nWidth = mButtons(i).Width: bChecked = mButtons(i).Checked
    ToolbarButton = True
End Function

Public Function ToolbarButtonTop() As Long
    ToolbarButtonTop = BAR_TOP
End Function

Public Function StatusText(ByVal sKey As String) As String
    Dim i As Integer
    For i = 1 To mPanelCount
        If mPanels(i).Key = sKey Then StatusText = mPanels(i).Text: Exit Function
    Next i
End Function

' Where the toolbar's buttons end, for things drawn after them.
Public Function ToolbarRight() As Long
    If mCount > 0 Then ToolbarRight = mButtons(mCount).Left + mButtons(mCount).Width
End Function

Public Sub ToolbarDraw(ByVal pic As PictureBox)
    Dim i As Integer
    pic.Line (0, 0)-(pic.ScaleWidth, pic.ScaleHeight), BAR_FACE, BF
    pic.Line (0, 0)-(pic.ScaleWidth, 0), BAR_LIGHT
    pic.Line (0, pic.ScaleHeight - 1)-(pic.ScaleWidth, pic.ScaleHeight - 1), BAR_SHADOW
    For i = 1 To mCount
        DrawButton pic, i
    Next i
End Sub

Private Sub DrawButton(ByVal pic As PictureBox, ByVal i As Integer)
    Dim x As Long, y As Long, w As Long, h As Long, off As Long
    x = mButtons(i).Left: y = BAR_TOP: w = mButtons(i).Width: h = BTN_H
    pic.Line (x, y)-(x + w - 1, y + h - 1), BAR_FACE, BF
    If mButtons(i).IsSep Then
        pic.Line (x + 3, y + 1)-(x + 3, y + h - 1), BAR_SHADOW
        pic.Line (x + 4, y + 1)-(x + 4, y + h - 1), BAR_LIGHT
        Exit Sub
    End If
    If (i = mDown And i = mHot) Or mButtons(i).Checked Then
        Bevel pic, x, y, w, h, BAR_SHADOW, BAR_LIGHT
        off = 1
    ElseIf i = mHot Then
        Bevel pic, x, y, w, h, BAR_LIGHT, BAR_SHADOW
    End If
    PaintIcon pic, mButtons(i).Key, x + (w - 16) \ 2 + off, y + (h - 16) \ 2 + off, True
End Sub

Public Sub Bevel(ByVal pic As PictureBox, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, _
                 ByVal cTopLeft As Long, ByVal cBottomRight As Long)
    pic.Line (x, y + h - 1)-(x, y), cTopLeft
    pic.Line (x, y)-(x + w - 1, y), cTopLeft
    pic.Line (x + w - 1, y)-(x + w - 1, y + h - 1), cBottomRight
    pic.Line (x + w - 1, y + h - 1)-(x - 1, y + h - 1), cBottomRight
End Sub

Private Function HitTest(ByVal x As Single, ByVal y As Single) As Integer
    Dim i As Integer
    If y < BAR_TOP Or y >= BAR_TOP + BTN_H Then Exit Function
    For i = 1 To mCount
        If Not mButtons(i).IsSep Then
            If x >= mButtons(i).Left And x < mButtons(i).Left + mButtons(i).Width Then
                HitTest = i
                Exit Function
            End If
        End If
    Next i
End Function

' Mouse moved over the toolbar. Returns the tooltip to show ("" if none).
Public Function ToolbarMouseMove(ByVal pic As PictureBox, ByVal x As Single, ByVal y As Single) As String
    Dim h As Integer, old As Integer
    h = HitTest(x, y)
    If h <> mHot Then
        old = mHot
        mHot = h
        If old > 0 Then DrawButton pic, old
        If h > 0 Then DrawButton pic, h
        pic.Refresh
    End If
    If h > 0 Then ToolbarMouseMove = mButtons(h).Tip
End Function

Public Sub ToolbarMouseDown(ByVal pic As PictureBox, ByVal x As Single, ByVal y As Single)
    mDown = HitTest(x, y)
    mHot = mDown
    If mDown > 0 Then
        DrawButton pic, mDown
        pic.Refresh
    End If
End Sub

' Returns the key of the button that was clicked, or "".
Public Function ToolbarMouseUp(ByVal pic As PictureBox, ByVal x As Single, ByVal y As Single) As String
    Dim was As Integer
    was = mDown
    mDown = 0
    If was > 0 Then
        DrawButton pic, was
        pic.Refresh
        If HitTest(x, y) = was Then ToolbarMouseUp = mButtons(was).Key
    End If
End Function

' The mouse left the toolbar: un-pop the hot button.
Public Sub ToolbarMouseLeave(ByVal pic As PictureBox)
    Dim old As Integer
    If mHot = 0 Then Exit Sub
    old = mHot
    mHot = 0
    DrawButton pic, old
    pic.Refresh
End Sub

' ---- The turbo LED: two red seven-segment digits and "MHz" ----

Public Sub DrawLed(ByVal pic As PictureBox, ByVal x As Long, ByVal sDigits As String)
    Dim i As Integer, y As Long
    y = BAR_TOP + 1
    pic.Line (x, y)-(x + 50, y + BTN_H - 3), BAR_FACE, BF
    Bevel pic, x, y, 32, BTN_H - 2, BAR_SHADOW, BAR_LIGHT
    pic.Line (x + 1, y + 1)-(x + 30, y + BTN_H - 4), RGB(24, 0, 0), BF
    For i = 1 To Len(sDigits)
        SevenSeg pic, x + 4 + (i - 1) * 13, y + 3, Mid$(sDigits, i, 1)
    Next i
    TextAt pic, x + 35, y + 4, "MHz", vbBlack
    pic.Refresh
End Sub

' One digit, 10 x 15 pixels. Unlit segments glow a little, like the real thing.
Private Sub SevenSeg(ByVal pic As PictureBox, ByVal x As Long, ByVal y As Long, ByVal d As String)
    Dim lit As String, segs As String, k As Integer, c As Long
    ' segments a b c d e f g, for 0-9
    Select Case d
    Case "0": lit = "1111110"
    Case "1": lit = "0110000"
    Case "2": lit = "1101101"
    Case "3": lit = "1111001"
    Case "4": lit = "0110011"
    Case "5": lit = "1011011"
    Case "6": lit = "1011111"
    Case "7": lit = "1110000"
    Case "8": lit = "1111111"
    Case "9": lit = "1111011"
    Case Else: lit = "0000001"
    End Select
    For k = 1 To 7
        If Mid$(lit, k, 1) = "1" Then c = RGB(255, 32, 0) Else c = RGB(64, 0, 0)
        Select Case k
        Case 1: pic.Line (x + 2, y)-(x + 8, y + 2), c, BF
        Case 2: pic.Line (x + 8, y + 1)-(x + 10, y + 7), c, BF
        Case 3: pic.Line (x + 8, y + 8)-(x + 10, y + 14), c, BF
        Case 4: pic.Line (x + 2, y + 13)-(x + 8, y + 15), c, BF
        Case 5: pic.Line (x, y + 8)-(x + 2, y + 14), c, BF
        Case 6: pic.Line (x, y + 1)-(x + 2, y + 7), c, BF
        Case 7: pic.Line (x + 2, y + 7)-(x + 8, y + 8), c, BF
        End Select
    Next k
End Sub

' ---- Status bar ----

Public Sub StatusClear()
    mPanelCount = 0
    ReDim mPanels(1 To 8)
End Sub

Public Sub StatusAdd(ByVal sKey As String, ByVal sText As String, ByVal nWidth As Long)
    mPanelCount = mPanelCount + 1
    mPanels(mPanelCount).Key = sKey
    mPanels(mPanelCount).Text = sText
    mPanels(mPanelCount).Width = nWidth
End Sub

Public Sub StatusSet(ByVal pic As PictureBox, ByVal sKey As String, ByVal sText As String)
    Dim i As Integer
    For i = 1 To mPanelCount
        If mPanels(i).Key = sKey Then
            If mPanels(i).Text <> sText Then
                mPanels(i).Text = sText
                StatusDraw pic
            End If
            Exit Sub
        End If
    Next i
End Sub

Public Sub StatusDraw(ByVal pic As PictureBox)
    Dim i As Integer, x As Long, w As Long, fixed As Long, h As Long
    h = pic.ScaleHeight
    pic.Line (0, 0)-(pic.ScaleWidth, h), BAR_FACE, BF
    For i = 1 To mPanelCount
        fixed = fixed + mPanels(i).Width + 2
    Next i
    x = 2
    For i = 1 To mPanelCount
        w = mPanels(i).Width
        If w = 0 Then w = pic.ScaleWidth - fixed - 4 - 14
        If w < 20 Then w = 20
        Bevel pic, x, 2, w, h - 3, BAR_SHADOW, BAR_LIGHT
        TextAt pic, x + 3, (h - pic.TextHeight("Xy")) / 2, ClipText(pic, mPanels(i).Text, w - 6), vbBlack
        x = x + w + 2
    Next i
    ' the size grip, three diagonal ridges
    For i = 0 To 2
        pic.Line (pic.ScaleWidth - 3 - i * 4, h - 2)-(pic.ScaleWidth - 1, h - 4 - i * 4), BAR_LIGHT
        pic.Line (pic.ScaleWidth - 2 - i * 4, h - 2)-(pic.ScaleWidth - 1, h - 3 - i * 4), BAR_SHADOW
    Next i
    pic.Refresh
End Sub

Private Function ClipText(ByVal pic As PictureBox, ByVal s As String, ByVal w As Long) As String
    ClipText = s
    Do While Len(ClipText) > 0 And pic.TextWidth(ClipText) > w
        ClipText = Left$(ClipText, Len(ClipText) - 1)
    Loop
End Function
