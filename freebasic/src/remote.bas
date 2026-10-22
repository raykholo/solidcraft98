' remote.bas - remote control. Another program drives SolidCraft 98 over a
' pipe, the way Unix programs have always been scripted (see Expect), and
' reads the screen back as text, the way a screen reader does.
'
'   sc98 --remote [--headless]
'
' One command per line on standard input; each answer on standard output
' ends with a line holding a single ".". Commands:
'
'   look                      the screen, as text
'   click <name>              click what's on screen by its name: a button,
'   click <x> <y>             a menu, a field, a feature, a toolbar button
'   dblclick <name>|<x> <y>   (a feature: double-click edits it)
'   rclick <name>|<x> <y>
'   drag <x1> <y1> <x2> <y2> [right]
'   menu <title> > <item>     e.g. "menu File > Save As..."
'   key <keys>                e.g. "key e", "key ctrl+s", "key enter"
'   type <text>
'   wait <ms>
'   shot <file.bmp>           a screenshot
'   help                      this list
'   quit                      ends SolidCraft 98 at once, nothing saved
'
' Actions answer "ok" once the screen has settled; "error: ..." if not.

Type TPollFd
    fd As Long
    events As Short
    revents As Short
End Type
Declare Function c_poll Cdecl Alias "poll" (ByVal fds As TPollFd Ptr, ByVal n As UInteger, ByVal ms As Long) As Long
Declare Function c_read Cdecl Alias "read" (ByVal fd As Long, ByVal buf As Any Ptr, ByVal n As UInteger) As Integer
Declare Function c_write Cdecl Alias "write" (ByVal fd As Long, ByVal buf As Any Ptr, ByVal n As UInteger) As Integer

Const POLLIN = 1
Const SETTLE_TIME = 0.25           ' seconds the screen gets to catch up

Dim Shared RemoteIn As String       ' read but not yet run
Dim Shared RemoteEOF As Boolean
Dim Shared RemoteAnswerDue As Boolean
Dim Shared RemoteSettle As Double
Dim Shared RemoteWaitUntil As Double

' ---- the pipe ----

Sub RemoteSay(ByRef t As String)
    ' every line, then the "." that ends the answer; a line that starts
    ' with "." gets another, as in SMTP
    Dim As String s, rest = t
    Do While Right(rest, 1) = Chr(10)
        rest = Left(rest, Len(rest) - 1)
    Loop
    rest &= Chr(10)
    Do While Len(rest)
        Dim As Long p = InStr(rest, Chr(10))
        Dim As String ln = Left(rest, p - 1)
        rest = Mid(rest, p + 1)
        If Left(ln, 1) = "." Then ln = "." & ln
        s &= ln & Chr(10)
    Loop
    s &= "." & Chr(10)
    Dim As Long sent = 0
    Do While sent < Len(s)
        Dim As Integer n = c_write(1, StrPtr(s) + sent, Len(s) - sent)
        If n <= 0 Then Exit Do
        sent += n
    Loop
End Sub

Sub RemoteRead()
    If RemoteEOF Then Exit Sub
    Dim pf As TPollFd
    pf.fd = 0: pf.events = POLLIN
    Do While c_poll(@pf, 1, 0) > 0
        Dim buf As ZString * 1025
        Dim As Integer n = c_read(0, @buf, 1024)
        If n <= 0 Then RemoteEOF = True: Exit Do
        buf[n] = 0
        RemoteIn &= buf
    Loop
End Sub

Function NextRemoteLine(ByRef l As String) As Boolean
    Dim As Long p = InStr(RemoteIn, Chr(10))
    If p = 0 Then Return False
    l = Trim(Left(RemoteIn, p - 1), Any " " & Chr(9) & Chr(13))
    RemoteIn = Mid(RemoteIn, p + 1)
    Return True
End Function

' ---- what's on screen, and where ----

Type TTarget
    nm As String
    x As Long
    y As Long
End Type
Dim Shared Tg(0 To 399) As TTarget
Dim Shared TgN As Long

' Names compare without "&", "...", a trailing ":" or case.
Function NormName(ByRef s As String) As String
    Dim As String t = LCase(Trim(AmpStrip(s)))
    If Right(t, 3) = "..." Then t = RTrim(Left(t, Len(t) - 3))
    If Right(t, 1) = ":" Then t = RTrim(Left(t, Len(t) - 1))
    If Left(t, 1) = """" And Right(t, 1) = """" And Len(t) >= 2 Then t = Trim(Mid(t, 2, Len(t) - 2))
    If Left(t, 1) = "[" And Right(t, 1) = "]" And Len(t) >= 2 Then t = Trim(Mid(t, 2, Len(t) - 2))
    Return t
End Function

Sub AddTarget(ByRef nm As String, ByVal x As Long, ByVal y As Long)
    If TgN > UBound(Tg) Or Len(NormName(nm)) = 0 Then Exit Sub
    Tg(TgN).nm = NormName(nm): Tg(TgN).x = x: Tg(TgN).y = y
    TgN += 1
End Sub

' The first exact name wins, then the first that starts with it.
Function FindTarget(ByRef nm As String, ByRef x As Long, ByRef y As Long) As Boolean
    Dim As String want = NormName(nm)
    Dim i As Long
    For i = 0 To TgN - 1
        If Tg(i).nm = want Then x = Tg(i).x: y = Tg(i).y: Return True
    Next
    For i = 0 To TgN - 1
        If Left(Tg(i).nm, Len(want)) = want Then x = Tg(i).x: y = Tg(i).y: Return True
    Next
    Return False
End Function

' Lines joined with " / ", blank ones left out.
Function OneLine(ByRef t As String) As String
    Dim As String s, rest = t & Chr(10)
    Do While Len(rest)
        Dim As Long p = InStr(rest, Chr(10))
        Dim As String ln = Trim(Left(rest, p - 1))
        rest = Mid(rest, p + 1)
        If Len(ln) Then s &= IIf(Len(s), " / ", "") & ln
    Loop
    Return AmpStrip(s)
End Function

' "Turbo. Makes everything faster." and "New Part (Ctrl+N)": the name is
' the part before the first "(" or ".".
Function ToolName(ByRef tip As String) As String
    Dim As Long a = InStr(tip, " ("), b = InStr(tip, ". ")
    If a = 0 OrElse (b > 0 And b < a) Then a = b
    If a = 0 Then Return tip
    Return Left(tip, a - 1)
End Function

' "Width (mm):" -> "Width (mm)"
Function NormLabel(ByRef s As String) As String
    Dim As String t = Trim(AmpStrip(s))
    If Right(t, 1) = ":" Then t = Left(t, Len(t) - 1)
    Return t
End Function

Function DescribeDialog(ByVal d As TDlg Ptr, ByVal isTop As Boolean) As String
    Dim As String r
    Dim As Long ox = ClientX(*d), oy = ClientY(*d), i
    Dim As String nm = d->title
    If Len(nm) = 0 Then nm = "(no title)"
    r = "Dialog """ & nm & """" & IIf(isTop, ", on top: it takes every click and key until it closes", ", under the one above") & Chr(10)
    If Not isTop Then Return r
    If d->readOutFn <> 0 Then r &= "  " & d->readOutFn(d) & Chr(10)
    Dim As String pending      ' a label waiting for the field after it
    Dim As Long fieldNo = 0
    For i = 0 To d->nCtl - 1
        With d->c(i)
            If .hidden Then Continue For
            Dim As Long cx = ox + .x + .w \ 2, cy = oy + .y + .h \ 2
            Dim As String foc = IIf(i = d->focus, " (has the focus)", "")
            Select Case .kind
            Case CT_LABEL
                If Len(pending) Then r &= "  " & OneLine(pending) & Chr(10)
                pending = .text
                ' a label right before a field names it; otherwise it's text
                Dim As Long nx = i + 1
                Do While nx < d->nCtl AndAlso (d->c(nx).hidden Or (d->c(nx).kind = CT_LABEL And Len(d->c(nx).text) = 0))
                    nx += 1
                Loop
                If nx >= d->nCtl OrElse (d->c(nx).kind <> CT_EDIT And d->c(nx).kind <> CT_COMBO) Then
                    If Len(Trim(.text)) Then r &= "  " & OneLine(.text) & Chr(10)
                    pending = ""
                End If
            Case CT_EDIT, CT_COMBO
                fieldNo += 1
                Dim As String lb = OneLine(pending)
                If Len(lb) = 0 Then lb = "field " & fieldNo
                Dim As String sel = ""
                If i = d->focus And .kind = CT_EDIT And Abs(.caret - .selStart) = Len(.text) And Len(.text) > 0 Then sel = ", all selected: typing replaces it"
                r &= "  field """ & NormLabel(lb) & """: [" & .text & "]" & IIf(.kind = CT_COMBO, " (a drop-down)", "") & foc & sel & Chr(10)
                AddTarget lb, cx, cy
                AddTarget "field " & fieldNo, cx, cy
                pending = ""
            Case CT_BUTTON
                r &= "  button [" & AmpStrip(.text) & "]" & IIf(.isDefault, " (default: Enter presses it)", "") & IIf(.isCancel, " (Esc presses it)", "") & IIf(.disabled, " (greyed out)", "") & foc & Chr(10)
                AddTarget .text, cx, cy
            Case CT_LIST
                r &= "  list" & foc & ":" & Chr(10)
                Dim As Long k, rows = (.h - 4) \ LIST_ROW_H
                For k = .top To .top + rows - 1
                    If k >= ListCount Then Exit For
                    Dim As String it = Mid(ListRows(k), 2)
                    r &= "    " & IIf(Left(ListRows(k), 1) = "D", "[folder] ", "") & it & IIf(k = .sel, "  (selected)", "") & Chr(10)
                    AddTarget it, ox + .x + 24 + TextW(it) \ 2, oy + .y + 2 + (k - .top) * LIST_ROW_H + 8
                Next
                If ListCount > .top + rows Then r &= "    (" & (ListCount - .top - rows) & " more below)" & Chr(10)
                If ListCount = 0 Then r &= "    (empty)" & Chr(10)
            Case CT_CUSTOM
                If Len(.text) Then r &= "  button [" & .text & "]" & foc & Chr(10): AddTarget .text, cx, cy
            End Select
        End With
    Next
    If Len(pending) Then r &= "  " & OneLine(pending) & Chr(10)
    If Not d->noFrame Then
        r &= "  title bar close box [x]" & Chr(10)
        AddTarget "x", d->x + d->w - 13, d->y + 12
        AddTarget "close box", d->x + d->w - 13, d->y + 12
        AddTarget "close", d->x + d->w - 13, d->y + 12
    End If
    Return r
End Function

Function DescribePart(ByVal p As Long, ByVal isActive As Boolean) As String
    Dim As String r
    With Parts(p)
        Dim As TDesign Ptr d = @Docs(.slot)
        Dim As String t = DocTitle(.slot)
        r = "Part window """ & t & """" & IIf(isActive, " (the active one)", "") & IIf(.minimized, ", minimised to its title bar", "") & Chr(10)
        AddTarget t, .x + 24 + TextW(t, True) \ 2, .y + 4 + TITLE_H \ 2
        Dim As Long bx = .x + .w - 4 - 2 - 16
        AddTarget t & " close", bx + 8, .y + 13
        AddTarget t & IIf(.minimized, " restore", " minimise"), bx - IIf(.minimized, 10, 26), .y + 13
        If .minimized Or Not isActive Then Return r
        Dim As Long cx, cy, cw, ch, vx, vy, vw, vh, i
        ClientRect p, cx, cy, cw, ch
        ViewRect p, vx, vy, vw, vh
        ' the feature tree, as rows
        BuildTree p
        r &= "  Feature tree:" & Chr(10)
        For i = 0 To TreeRowN - 1
            r &= "    " & String(TreeRows(i).level * 2, " ") & TreeRows(i).text & IIf(TreeRows(i).key > 0 And TreeRows(i).key = .selected, "   <- selected", "") & Chr(10)
        Next
        ' the timeline
        Dim As Long rows = (TL_H - 4 - LV_HEAD_H) \ LV_ROW_H
        If d->Count = 0 Then
            r &= "  Timeline: empty. Nothing has been made yet." & Chr(10)
        Else
            r &= "  Timeline (# | Feature | Type | Parameters | Status):" & Chr(10)
            For i = 1 To d->Count
                Dim As String row = "    " & i & " | " & TimelineCell(*d, i, 1) & " | " & TimelineCell(*d, i, 2) & " | " & _
                    TimelineCell(*d, i, 3) & " | " & TimelineCell(*d, i, 4)
                If i = .selected Then row &= "   <- selected"
                If i - 1 >= .listTop And i - 1 < .listTop + rows Then
                    AddTarget d->F(i).Name, cx + 2 + ColW(0) + 30, cy + ch - TL_H + 2 + LV_HEAD_H + (i - 1 - .listTop) * LV_ROW_H + 7
                Else
                    row &= "   (scrolled out of view)"
                End If
                r &= row & Chr(10)
            Next
        End If
        ' the view
        r &= "  View (x " & vx & " to " & vx + vw - 1 & ", y " & vy & " to " & vy + vh - 1 & "; drag in it to orbit, right-drag to pan): "
        If .revealing Then
            r &= "shading, " & Int(.revealRows * 100 / IIf(.imgH > 0, .imgH, 1)) & "% drawn"
        ElseIf ViewShaded Then
            r &= "shaded, " & .triN & " triangles"
        ElseIf .edgeN > 0 Then
            r &= "wireframe, " & .edgeN & " edges"
        Else
            r &= "an empty grid"
        End If
        r &= ". Seen from yaw " & Int(.v.Yaw) & ", pitch " & Int(.v.Pitch) & Chr(10)
        AddTarget "view", vx + vw \ 2, vy + vh \ 2
    End With
    Return r
End Function

Function DescribeScreen() As String
    Dim As String r
    Dim As Long i, x, y, w, h
    TgN = 0
    r = APP_NAME & ", " & ScrW & " x " & ScrH & ". Turbo " & IIf(Turbo, "ON (the LED says 33 MHz)", "off (the LED says 66 MHz)") & "." & Chr(10)
    ' dialogs first: the top one is all that takes input
    If DlgTop >= 0 Then
        r &= DescribeDialog(DlgStack(DlgTop), True)
        For i = DlgTop - 1 To 0 Step -1
            r &= DescribeDialog(DlgStack(i), False)
        Next
        r &= "Underneath: the main window, which can't be used until the dialog closes." & Chr(10)
        r &= "Status bar: " & StatusMsg & Chr(10)
        Return r
    End If
    ' the menu bar, and the open menu
    r &= "Menu bar:"
    For i = 0 To 6
        r &= IIf(i = 0, " ", ", ") & AmpStrip(MenuTitles(i))
        AddTarget MenuTitles(i), (MenuX(i) + MenuX(i + 1)) \ 2, TitleH + MENU_H \ 2
    Next
    r &= Chr(10)
    If OpenMenu >= 0 Then
        DropRect OpenMenu, x, y, w, h
        r &= "The " & AmpStrip(MenuTitles(OpenMenu)) & " menu is open:" & Chr(10)
        Dim As Long iy = y + 3
        For i = 0 To ItemsIn(OpenMenu) - 1
            Dim it As TMenuItem = MenuItemAt(OpenMenu, i)
            If it.caption = "-" Then iy += 8: Continue For
            r &= "  " & IIf(MenuChecked(it.cmd), "[x] ", "") & AmpStrip(it.caption) & IIf(Len(it.shortcut), "   (" & it.shortcut & ")", "") & Chr(10)
            AddTarget it.caption, x + 20 + TextW(AmpStrip(it.caption)) \ 2, iy + 8
            iy += 17
        Next
    End If
    ' the toolbar
    r &= "Toolbar buttons:"
    Dim As Boolean first = True
    For i = 0 To ButtonCount - 1
        If Len(Buttons(i).key) = 0 Then Continue For
        Dim As String nm = ToolName(Buttons(i).tip)
        r &= IIf(first, " ", ", ") & nm & IIf(MenuChecked(Buttons(i).key), " (pressed in)", "")
        first = False
        ' a menu item of the same name comes first, so it's added after
        AddTarget nm, Buttons(i).x + Buttons(i).w \ 2, ToolTop() + 3 + 11
    Next
    r &= Chr(10)
    ' the part windows, front to back
    If ZCount = 0 Then r &= "No part windows are open." & Chr(10)
    For i = ZCount - 1 To 0 Step -1
        r &= DescribePart(ZOrder(i), i = ZCount - 1)
    Next
    ' Cal, and the note Cal pinned
    If CalVisible Then
        r &= "Cal, the caliper assistant, is in the corner. It says: " & OneLine(CalText) & Chr(10)
        Dim As Long b, bx, by, bw
        For b = 0 To 2
            If b = 0 And CalStage = 1 Then Continue For
            CalButtonRect b, bx, by, bw
            r &= "  button [" & AmpStrip(CalButtonText(b)) & "]" & Chr(10)
            AddTarget CalButtonText(b), bx + bw \ 2, by + 10
        Next
    ElseIf CalPinned Then
        r &= "A note is pinned in the corner: ""Cal's tip, pinned for you: Boxes want to be extruded. Press E."" It has a close box [x]." & Chr(10)
        Dim As Long bx, by
        PinCloseRect bx, by
        AddTarget "close note", bx + 8, by + 7
    End If
    r &= "Status bar: " & StatusMsg & IIf(Len(StatusFps), "   (" & StatusFps & ")", "") & "   Clock: " & ClockText & Chr(10)
    Return r
End Function

' ---- running commands ----

Function RemoteHelp() As String
    Return "Commands: look | click <name> or <x> <y> | dblclick <name> or <x> <y> | rclick <name> or <x> <y>" & Chr(10) & _
        "drag <x1> <y1> <x2> <y2> [right] | menu <title> > <item> | key <keys> (e, ctrl+s, enter, esc, tab, f5)" & Chr(10) & _
        "type <text> | wait <ms> | shot <file.bmp> | help | quit"
End Function

' click/dblclick/rclick take a name, or x and y.
Function TargetXY(ByRef arg As String, ByRef x As Long, ByRef y As Long, ByRef errMsg As String) As Boolean
    Dim As String a = Trim(arg)
    Dim As Long sp = InStr(a, " ")
    If sp > 0 AndAlso Str(Val(Left(a, sp - 1))) = Left(a, sp - 1) AndAlso Str(Val(Mid(a, sp + 1))) = Trim(Mid(a, sp + 1)) Then
        x = Val(Left(a, sp - 1)): y = Val(Mid(a, sp + 1))
        Return True
    End If
    DescribeScreen                ' fills in the targets
    If FindTarget(a, x, y) Then Return True
    errMsg = "error: there's nothing called """ & a & """ on the screen. ""look"" lists what's there."
    Return False
End Function

Sub RemoteClick(ByVal x As Long, ByVal y As Long, ByVal btn As Long, ByVal dbl As Boolean)
    QueueMouse EV_MOVE, x, y, 0
    QueueMouse EV_DOWN, x, y, btn: QueueMouse EV_UP, x, y, btn
    If dbl Then QueueMouse EV_DOWN, x, y, btn, True: QueueMouse EV_UP, x, y, btn
End Sub

Sub RemoteDo(ByRef l As String)
    Dim As String rest = l
    Dim As String cmd = LCase(NextWord(rest))
    Dim As Long x, y
    Dim As String e
    LogLine "remote: " & l
    Select Case cmd
    Case ""
        Exit Sub
    Case "look"
        RemoteSay DescribeScreen()
        Exit Sub
    Case "help"
        RemoteSay RemoteHelp()
        Exit Sub
    Case "click", "dblclick", "rclick"
        If Len(Trim(rest)) = 0 Then RemoteSay "error: " & cmd & " what?": Exit Sub
        If Not TargetXY(rest, x, y, e) Then RemoteSay e: Exit Sub
        RemoteClick x, y, IIf(cmd = "rclick", 2, 1), cmd = "dblclick"
    Case "drag"
        Dim As Long x1 = Val(NextWord(rest)), y1 = Val(NextWord(rest)), x2 = Val(NextWord(rest)), y2 = Val(NextWord(rest)), i
        Dim As Long b = IIf(LCase(NextWord(rest)) = "right", 2, 1)
        QueueMouse EV_MOVE, x1, y1, 0: QueueMouse EV_DOWN, x1, y1, b
        For i = 1 To 10
            QueueMouse EV_MOVE, x1 + (x2 - x1) * i \ 10, y1 + (y2 - y1) * i \ 10, b
        Next
        QueueMouse EV_UP, x2, y2, b
    Case "menu"
        If DlgTop >= 0 Then RemoteSay "error: a dialog is open, and it has to close before the menus work.": Exit Sub
        Dim As Long gt = InStr(rest, ">")
        If gt = 0 Then RemoteSay "error: say ""menu <title> > <item>"", e.g. ""menu File > Open..."".": Exit Sub
        Dim As String tName = NormName(Left(rest, gt - 1)), iName = NormName(Mid(rest, gt + 1))
        Dim As Long m = -1, k
        For k = 0 To 6
            If NormName(MenuTitles(k)) = tName Then m = k
        Next
        If m < 0 Then RemoteSay "error: there's no menu called """ & Trim(Left(rest, gt - 1)) & """.": Exit Sub
        Dim As Long dx, dy, dw, dh, iy, hit = -1
        DropRect m, dx, dy, dw, dh
        iy = dy + 3
        For k = 0 To ItemsIn(m) - 1
            Dim it As TMenuItem = MenuItemAt(m, k)
            If it.caption = "-" Then iy += 8: Continue For
            If hit < 0 AndAlso Left(NormName(it.caption), Len(iName)) = iName Then hit = k: x = dx + 20: y = iy + 8
            iy += 17
        Next
        If hit < 0 Then RemoteSay "error: the " & AmpStrip(MenuTitles(m)) & " menu has no """ & Trim(Mid(rest, gt + 1)) & """.": Exit Sub
        If OpenMenu >= 0 Then QueueKeyCombo "esc"
        RemoteClick (MenuX(m) + MenuX(m + 1)) \ 2, TitleH + MENU_H \ 2, 1, False
        RemoteClick x, y, 1, False
    Case "key"
        If Len(Trim(rest)) = 0 Then RemoteSay "error: key what? e.g. ""key enter"".": Exit Sub
        Dim As String one
        Do
            one = NextWord(rest)
            If Len(one) = 0 Then Exit Do
            QueueKeyCombo one
        Loop
    Case "type"
        QueueType rest
    Case "wait"
        RemoteWaitUntil = Timer + Val(rest) / 1000
    Case "shot"
        ShotRequested = Trim(rest)
    Case "quit"
        RemoteSay "bye"
        End 0
    Case Else
        RemoteSay "error: """ & cmd & """ isn't a command. " & RemoteHelp()
        Exit Sub
    End Select
    RemoteAnswerDue = True
    RemoteSettle = Timer + SETTLE_TIME
End Sub

' Called on every turn of the event loop, inside dialogs too.
Sub RemoteStep()
    RemoteRead
    If EvHead <> EvTail Then Exit Sub
    If Timer < RemoteWaitUntil Then Exit Sub
    If RemoteAnswerDue Then
        If Timer < RemoteSettle Or Len(ShotRequested) > 0 Then Exit Sub
        RemoteAnswerDue = False
        RemoteSay "ok"
    End If
    Dim As String l
    If NextRemoteLine(l) Then
        RemoteDo l
    ElseIf RemoteEOF And Len(RemoteIn) = 0 Then
        ' the other end went away: headless, that's the end; on screen, the
        ' person at the keyboard carries on
        If HeadlessMode Then End 0
        RemoteMode = False
    End If
End Sub
