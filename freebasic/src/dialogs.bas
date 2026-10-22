' dialogs.bas - the number dialog every command uses, and the Open/Save
' dialog, in the Windows 98 style.

Declare Sub RunCommand(ByRef sCmd As String)
Declare Sub ShowFatal()
Dim Shared Turbo As Boolean

' ---- the number dialog (frmParams) ----

Const MAX_FIELDS = 7
Dim Shared ParamValue(0 To MAX_FIELDS - 1) As Double
Dim Shared ParamCount As Long
Dim Shared ParamMismatches As Long         ' Turbo: how many type mismatches in a row

Function ParamsClick(ByVal dp As Any Ptr, ByVal ci As Long) As Boolean
    Dim As TDlg Ptr d = dp
    Dim As Long i
    Select Case d->c(ci).id
    Case IDOK
        For i = 0 To ParamCount - 1
            ParamValue(i) = Evaluate(d->c(i * 2 + 1).text)
            If exErr Then Exit For
        Next
        If exErr = 0 Then
            ParamMismatches = 0
            d->result = IDOK
            Return True
        End If
        Dim As Long box = i * 2 + 1
        Dim As String t = d->c(box).text
        If exErr = 11 Then
            If Turbo Then ShowFatal Else MsgBox "Run-time error '11':" & Chr(10) & Chr(10) & "Division by zero", MB_CRITICAL
        ElseIf Not Turbo Then
            MsgBox "Run-time error '13':" & Chr(10) & Chr(10) & "Type mismatch", MB_CRITICAL
        Else
            ' with Turbo on it gets more personal each time, and on the fifth
            ' try it gives up and does what you meant
            ParamMismatches += 1
            Select Case ParamMismatches
            Case 1: MsgBox "Run-time error '13':" & Chr(10) & Chr(10) & "Type mismatch", MB_CRITICAL
            Case 2: MsgBox "Run-time error '13':" & Chr(10) & Chr(10) & "Still a type mismatch", MB_CRITICAL
            Case 3: MsgBox "Run-time error '13':" & Chr(10) & Chr(10) & "It's a TextBox, not a mind reader.", MB_CRITICAL
            Case 4
                MsgBox "Did you know?" & Chr(10) & Chr(10) & _
                    "Val(""" & t & """) returns " & Val(t) & ". Val reads digits until it meets" & Chr(10) & _
                    "something it doesn't understand, then stops and pretends" & Chr(10) & _
                    "that's all you typed." & Chr(10) & Chr(10) & _
                    "CDbl(""" & t & """) is stricter. It raises error 13. We use CDbl." & Chr(10) & _
                    "Usually.", MB_INFO, "Tip of the Day"
            Case Else
                MsgBox "Fine. " & Val(t) & " it is.", MB_INFO
                d->c(box).text = Str(Val(t))
                ParamMismatches = 0
                Return ParamsClick(dp, ci)
            End Select
        End If
        SetFocus *d, box
        Return False
    Case IDCANCEL
        d->result = IDCANCEL
        Return True
    Case Else          ' Help
        RunCommand "Help"
        Return False
    End Select
End Function

' Shows the dialog. Prompts and defaults are "|"-separated. True if OK;
' the numbers are in ParamValue().
Function AskParams(ByRef sTitle As String, ByRef sPrompts As String, ByRef sDefaults As String) As Boolean
    Dim d As TDlg
    Dim As String p = sPrompts & "|", df = sDefaults & "|"
    Dim As Long i, y = 16
    ParamCount = 0
    Do While Len(p) And ParamCount < MAX_FIELDS
        Dim As Long a = InStr(p, "|"), b = InStr(df, "|")
        Dim As String pr = Left(p, a - 1), dv = IIf(b > 0, Left(df, b - 1), "0")
        p = Mid(p, a + 1)
        If b > 0 Then df = Mid(df, b + 1) Else df = ""
        AddCtl d, CT_LABEL, 16, y + 4, 173, 13, pr
        Dim As Long e = AddCtl(d, CT_EDIT, 192, y, 104, 21, dv)
        y += 32
        ParamCount += 1
    Loop
    y += 4
    i = AddCtl(d, CT_BUTTON, 59, y, 75, 23, "OK", IDOK): d.c(i).isDefault = True
    i = AddCtl(d, CT_BUTTON, 140, y, 75, 23, "Cancel", IDCANCEL): d.c(i).isCancel = True
    AddCtl d, CT_BUTTON, 221, y, 75, 23, "&Help", 9
    d.title = sTitle
    d.w = 312 + 6
    d.h = y + 23 + 16 + 3 + DLG_TITLE_H + 1 + 3
    CenterDialog d
    d.clickFn = @ParamsClick
    ParamMismatches = 0
    SetFocus d, 1
    LogLine "params: " & sTitle
    Return RunDialog(d) = IDOK
End Function

' ---- the Open and Save dialog ----

Dim Shared FileDir As String                 ' the folder it shows; remembered between uses
Dim Shared FileFilters(0 To 7) As String     ' "Description|*.a;*.b"
Dim Shared FileFilterCount As Long
Dim Shared FileFilterSel As Long
Dim Shared FileIsSave As Boolean
Dim Shared FileDefExt As String
Dim Shared FileResult As String

Const FD_LIST = 3, FD_NAME = 5, FD_TYPE = 7, FD_OK = 8, FD_CANCEL = 9, FD_UP = 10, FD_LOOKIN = 1

Function HomeDir() As String
    Dim As String h = Environ("HOME")
    If Len(h) = 0 Then h = "/"
    Return h
End Function

Function IsDir(ByRef p As String) As Boolean
    Dim As Long attr
    If p = "/" Then Return True
    Dim As String n = Dir(p, fbDirectory Or fbHidden Or fbSystem Or fbReadOnly Or fbArchive, attr)
    Return Len(n) > 0 And (attr And fbDirectory) <> 0
End Function

Function IsFile(ByRef p As String) As Boolean
    Dim As Long attr
    Dim As String n = Dir(p, fbNormal Or fbHidden Or fbReadOnly Or fbArchive Or fbSystem, attr)
    Return Len(n) > 0 And (attr And fbDirectory) = 0
End Function

Function JoinPath(ByRef a As String, ByRef b As String) As String
    If Right(a, 1) = "/" Then Return a & b
    Return a & "/" & b
End Function

Function ParentDir(ByRef p As String) As String
    Dim As Long k = InStrRev(p, "/")
    If k <= 1 Then Return "/"
    Return Left(p, k - 1)
End Function

Function MatchesPattern(ByRef nm As String, ByRef pats As String) As Boolean
    ' pats like "*.sc98;*.solidcraft" or "*.*"
    Dim As String rest = pats & ";", one
    Do While Len(rest)
        Dim As Long k = InStr(rest, ";")
        one = Trim(Left(rest, k - 1)): rest = Mid(rest, k + 1)
        If one = "*.*" Or one = "*" Then Return True
        If Left(one, 2) = "*." Then
            Dim As String ext = LCase(Mid(one, 2))
            If LCase(Right(nm, Len(ext))) = ext Then Return True
        End If
    Loop
    Return False
End Function

Sub SortRows(ByVal a As Long, ByVal b As Long)
    Dim As Long i, j
    For i = a + 1 To b
        Dim As String v = ListRows(i)
        j = i - 1
        Do While j >= a AndAlso LCase(ListRows(j)) > LCase(v)
            ListRows(j + 1) = ListRows(j)
            j -= 1
        Loop
        ListRows(j + 1) = v
    Next
End Sub

' Rows are "D<name>" for a folder, "F<name>" for a file.
Sub FillFileList(ByRef d As TDlg)
    Dim As Long attr, nd
    Dim As String n, pats = Mid(FileFilters(FileFilterSel), InStr(FileFilters(FileFilterSel), "|") + 1)
    ListCount = 0
    ReDim ListRows(0 To 255)
    n = Dir(JoinPath(FileDir, "*"), fbDirectory Or fbReadOnly Or fbArchive, attr)
    Do While Len(n)
        If Left(n, 1) <> "." Then
            If ListCount > UBound(ListRows) Then ReDim Preserve ListRows(0 To ListCount * 2)
            If attr And fbDirectory Then
                ListRows(ListCount) = "D" & n: ListCount += 1
            ElseIf MatchesPattern(n, pats) Then
                ListRows(ListCount) = "F" & n: ListCount += 1
            End If
        End If
        n = Dir(attr)
    Loop
    ' folders first, each lot in order
    Dim As Long i, w = 0
    For i = 0 To ListCount - 1
        If Left(ListRows(i), 1) = "D" Then Swap ListRows(i), ListRows(w): w += 1
    Next
    nd = w
    SortRows 0, nd - 1
    SortRows nd, ListCount - 1
    d.c(FD_LIST).sel = -1: d.c(FD_LIST).top = 0
    Dim As String shown = Mid(FileDir, InStrRev(FileDir, "/") + 1)
    If Len(shown) = 0 Then shown = "/"
    d.c(2).text = shown
End Sub

' Accepts what's in the name box. True closes the dialog.
Function FileAccept(ByVal d As TDlg Ptr) As Boolean
    Dim As String nm = Trim(d->c(FD_NAME).text), full
    If Len(nm) = 0 Then Return False
    If Left(nm, 1) = "~" Then nm = HomeDir() & Mid(nm, 2)
    If Left(nm, 1) = "/" Then full = nm Else full = JoinPath(FileDir, nm)
    If nm = ".." Then full = ParentDir(FileDir)
    If IsDir(full) Then
        FileDir = full
        d->c(FD_NAME).text = ""
        FillFileList *d
        Return False
    End If
    If InStr(nm, "*") Then
        FileFilters(FileFilterSel) = "Custom|" & nm      ' a pattern: show what matches it
        d->c(FD_TYPE).text = nm
        FillFileList *d
        Return False
    End If
    If FileIsSave Then
        If InStr(Mid(full, InStrRev(full, "/") + 1), ".") = 0 And Len(FileDefExt) Then full &= "." & FileDefExt
        If IsFile(full) Then
            If MsgBox(full & " already exists." & Chr(10) & "Do you want to replace it?", MB_YESNO Or MB_EXCLAMATION, IIf(FileIsSave, "Save As", "Open")) <> IDYES Then Return False
        End If
    Else
        If Not IsFile(full) Then
            If IsFile(full & "." & FileDefExt) Then
                full &= "." & FileDefExt
            Else
                MsgBox nm & Chr(10) & "File not found." & Chr(10) & "Please verify the correct file name was given.", MB_EXCLAMATION, "Open"
                Return False
            End If
        End If
    End If
    FileDir = ParentDir(full)
    FileResult = full
    d->result = IDOK
    Return True
End Function

Function FileClick(ByVal dp As Any Ptr, ByVal ci As Long) As Boolean
    Dim As TDlg Ptr d = dp
    Select Case ci
    Case FD_LIST
        Dim As Long r = d->c(FD_LIST).sel
        If r < 0 Or r >= ListCount Then Return False
        Dim As String it = ListRows(r)
        If Left(it, 1) = "F" Then d->c(FD_NAME).text = Mid(it, 2)
        If d->c(FD_LIST).tag = 2 Then           ' double-click (or Enter)
            If Left(it, 1) = "D" Then
                FileDir = JoinPath(FileDir, Mid(it, 2))
                FillFileList *d
                Return False
            End If
            Return FileAccept(d)
        End If
        Return False
    Case FD_TYPE
        FileFilterSel = (FileFilterSel + 1) Mod FileFilterCount
        d->c(FD_TYPE).text = Left(FileFilters(FileFilterSel), InStr(FileFilters(FileFilterSel), "|") - 1)
        FillFileList *d
        Return False
    Case FD_UP
        FileDir = ParentDir(FileDir)
        FillFileList *d
        Return False
    Case FD_OK
        Return FileAccept(d)
    Case FD_CANCEL
        d->result = IDCANCEL
        Return True
    End Select
    Return False
End Function

Sub FileDraw(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    ' the "up one level" button: a folder with an arrow
    Dim As Long x = ClientX(*d) + d->c(FD_UP).x, y = ClientY(*d) + d->c(FD_UP).y, i
    Fill x, y, 23, 22, C_FACE
    Bevel x, y, 23, 22, IIf(d->c(FD_UP).pressed, BEV_PRESSED, BEV_BUTTON)
    DrawIcon x + 4, y + 3, "Open"
    For i = 0 To 3
        HLine x + 15 - i, y + 4 + i, 1 + i * 2, C_DARK
    Next
    Fill x + 15, y + 8, 1, 6, C_DARK
End Sub

' Open or Save As. filter: "Description|*.a;*.b|Other|*.c". "" if cancelled.
Function FileDialog(ByVal isSave As Boolean, ByRef sDefault As String, ByRef sFilter As String, ByRef sExt As String) As String
    Dim d As TDlg
    Dim As String f = sFilter & "|"
    Dim As Long i
    FileFilterCount = 0
    Do While Len(f) > 1 And FileFilterCount < 7
        Dim As Long a = InStr(f, "|")
        Dim As Long b = InStr(a + 1, f, "|")
        FileFilters(FileFilterCount) = Left(f, b - 1)
        FileFilterCount += 1
        f = Mid(f, b + 1)
    Loop
    FileFilters(FileFilterCount) = "All Files (*.*)|*.*": FileFilterCount += 1
    FileFilterSel = 0
    FileIsSave = isSave: FileDefExt = sExt: FileResult = ""
    If Len(FileDir) = 0 OrElse Not IsDir(FileDir) Then
        FileDir = JoinPath(HomeDir(), "Documents")
        If Not IsDir(FileDir) Then FileDir = HomeDir()
    End If
    d.title = IIf(isSave, "Save As", "Open")
    d.w = 430: d.h = 290
    CenterDialog d
    AddCtl d, CT_LABEL, 10, 14, 60, 13, IIf(isSave, "Save &in:", "Look &in:")    ' 0
    AddCtl d, CT_LABEL, 0, 0, 0, 0, ""                                         ' 1 (unused)
    i = AddCtl(d, CT_COMBO, 70, 9, 260, 22, "")                                ' 2 the folder
    i = AddCtl(d, CT_LIST, 10, 40, d.w - 26, 150)                             ' 3 FD_LIST
    AddCtl d, CT_LABEL, 10, 204, 70, 13, "File &name:"                        ' 4
    i = AddCtl(d, CT_EDIT, 90, 199, 230, 21, sDefault)                        ' 5 FD_NAME
    AddCtl d, CT_LABEL, 10, 232, 80, 13, "Files of &type:"                    ' 6
    i = AddCtl(d, CT_COMBO, 90, 227, 230, 22, Left(FileFilters(0), InStr(FileFilters(0), "|") - 1))   ' 7 FD_TYPE
    i = AddCtl(d, CT_BUTTON, 330, 198, 75, 23, IIf(isSave, "&Save", "&Open"), IDOK): d.c(i).isDefault = True   ' 8
    i = AddCtl(d, CT_BUTTON, 330, 227, 75, 23, "Cancel", IDCANCEL): d.c(i).isCancel = True                   ' 9
    i = AddCtl(d, CT_CUSTOM, 336, 9, 23, 22)                                  ' 10 FD_UP
    d.c(2).disabled = False
    d.clickFn = @FileClick
    d.drawFn = @FileDraw
    FillFileList d
    SetFocus d, FD_NAME
    LogLine "file dialog: " & d.title & " in " & FileDir
    If RunDialog(d) = IDOK Then Return FileResult
    Return ""
End Function

' The folder part and the name part of a path.
Function FileTitle(ByRef sPath As String) As String
    Dim As String t = Mid(sPath, InStrRev(sPath, "/") + 1)
    Dim As Long p = InStrRev(t, ".")
    If p > 1 Then t = Left(t, p - 1)
    Return t
End Function
