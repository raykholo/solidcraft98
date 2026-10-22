' gui.bas - events, modal dialogs, message boxes, the number dialog and the
' file dialog, all drawn in the Windows 98 style.
'
' Dialogs are modal the VB way: MsgBox and friends run their own event loop
' and return when they close, so the ported code reads like the original
' ("If MsgBox(...) = IDYES Then"). The main window keeps ticking underneath.
'
' A script (--script file) can drive everything instead of the mouse and
' keyboard, and take screenshots: that is how the port is tested.

' ---- events ----

Enum
    EV_NONE
    EV_DOWN
    EV_UP
    EV_MOVE
    EV_WHEEL
    EV_KEY
    EV_CLOSE
End Enum

Enum
    K_BACK = 8
    K_TAB = 9
    K_ENTER = 13
    K_ESC = 27
    K_SPACE = 32
    K_UP = 1001
    K_DOWN
    K_LEFT
    K_RIGHT
    K_HOME
    K_END
    K_PGUP
    K_PGDN
    K_DEL
    K_INS
    K_F1 = 1101
End Enum

Type UIEvent
    kind As Long
    x As Long
    y As Long
    btn As Long          ' 1 left, 2 right, 4 middle
    dbl As Boolean       ' this press is the second of a double-click
    wheel As Long
    key As Long          ' K_* or the upper-case character code
    ch As String         ' the character typed, if any
    shift As Boolean
    ctrl As Boolean
    alt As Boolean
End Type

Dim Shared ScrW As Long = 800, ScrH As Long = 600
Dim Shared MouseX As Long = 400, MouseY As Long = 300, MouseBtn As Long
Dim Shared NeedRedraw As Boolean = True
Dim Shared Busy As Boolean                  ' draw the hourglass
Dim Shared HeadlessMode As Boolean          ' null driver: scripted test run
Dim Shared QuitRequested As Boolean

Declare Sub AppRender()
Declare Sub AppEvent(ByRef ev As UIEvent)
Declare Sub AppTick()

' ---- the script: clicks, keys and screenshots from a file ----

Dim Shared ScriptLines() As String
Dim Shared ScriptPos As Long
Dim Shared ScriptCount As Long
Dim Shared ScriptWaitUntil As Double
Dim Shared EvQueue(0 To 255) As UIEvent
Dim Shared EvHead As Long, EvTail As Long
Dim Shared ShotRequested As String
Dim Shared LogFile As Long

Sub LogLine(ByRef t As String)
    If LogFile Then Print #LogFile, t
End Sub

Sub QueueEvent(ByRef ev As UIEvent)
    EvQueue(EvTail) = ev
    EvTail = (EvTail + 1) And 255
End Sub

Sub QueueMouse(ByVal kind As Long, ByVal x As Long, ByVal y As Long, ByVal btn As Long = 1, ByVal dbl As Boolean = False)
    Dim ev As UIEvent
    ev.kind = kind: ev.x = x: ev.y = y: ev.btn = btn: ev.dbl = dbl
    QueueEvent ev
End Sub

Function KeyFromName(ByRef nm As String) As Long
    Select Case UCase(nm)
    Case "ENTER", "RETURN": Return K_ENTER
    Case "ESC", "ESCAPE": Return K_ESC
    Case "TAB": Return K_TAB
    Case "BACK", "BACKSPACE": Return K_BACK
    Case "SPACE": Return K_SPACE
    Case "UP": Return K_UP
    Case "DOWN": Return K_DOWN
    Case "LEFT": Return K_LEFT
    Case "RIGHT": Return K_RIGHT
    Case "HOME": Return K_HOME
    Case "END": Return K_END
    Case "PGUP": Return K_PGUP
    Case "PGDN": Return K_PGDN
    Case "DEL", "DELETE": Return K_DEL
    End Select
    If Left(UCase(nm), 1) = "F" And Len(nm) > 1 AndAlso Val(Mid(nm, 2)) > 0 Then Return K_F1 + Val(Mid(nm, 2)) - 1
    If Len(nm) = 1 Then Return Asc(UCase(nm))
    Return 0
End Function

' "key ctrl+s", "key enter", "key shift+tab"
Sub QueueKeyCombo(ByRef combo As String)
    Dim ev As UIEvent
    Dim As String rest = combo, part
    Do
        Dim As Long p = InStr(rest, "+")
        If p = 0 Or Len(rest) = 1 Then part = rest: rest = "" Else part = Left(rest, p - 1): rest = Mid(rest, p + 1)
        Select Case LCase(part)
        Case "ctrl": ev.ctrl = True
        Case "shift": ev.shift = True
        Case "alt": ev.alt = True
        Case Else
            ev.key = KeyFromName(part)
            If Len(part) = 1 And Not ev.ctrl And Not ev.alt Then ev.ch = IIf(ev.shift, UCase(part), LCase(part))
            If ev.key = K_SPACE Then ev.ch = " "
        End Select
    Loop While Len(rest)
    ev.kind = EV_KEY
    QueueEvent ev
End Sub

Sub QueueType(ByRef t As String)
    Dim i As Long
    For i = 1 To Len(t)
        Dim ev As UIEvent
        ev.kind = EV_KEY: ev.ch = Mid(t, i, 1): ev.key = Asc(UCase(ev.ch))
        QueueEvent ev
    Next i
End Sub

Sub LoadScript(ByRef path As String)
    Dim As Long fh = FreeFile, n
    Dim As String l
    If Open(path For Input As #fh) <> 0 Then Exit Sub
    ReDim ScriptLines(0 To 63)
    Do Until EOF(fh)
        Line Input #fh, l
        If n > UBound(ScriptLines) Then ReDim Preserve ScriptLines(0 To n * 2)
        ScriptLines(n) = l: n += 1
    Loop
    Close #fh
    ScriptCount = n: ScriptPos = 0
End Sub

Function NextWord(ByRef s As String) As String
    s = LTrim(s)
    Dim As Long p = InStr(s, " ")
    Dim As String w
    If p = 0 Then w = s: s = "" Else w = Left(s, p - 1): s = Mid(s, p + 1)
    Return w
End Function

' Runs script lines until one has to wait for the screen to catch up.
Sub ScriptStep()
    If ScriptPos >= ScriptCount Then Exit Sub
    If Timer < ScriptWaitUntil Then Exit Sub
    If EvHead <> EvTail Then Exit Sub
    Do While ScriptPos < ScriptCount
        Dim As String l = Trim(ScriptLines(ScriptPos)), cmd
        ScriptPos += 1
        If Len(l) = 0 OrElse Left(l, 1) = "#" Then Continue Do
        cmd = LCase(NextWord(l))
        Select Case cmd
        Case "click"
            Dim As Long x = Val(NextWord(l)), y = Val(NextWord(l))
            Dim As String md = LCase(NextWord(l))
            Dim As Long b = IIf(md = "right", 2, 1)
            QueueMouse EV_MOVE, x, y, 0
            Dim ev As UIEvent
            ev.kind = EV_DOWN: ev.x = x: ev.y = y: ev.btn = b: ev.shift = (md = "shift")
            QueueEvent ev
            QueueMouse EV_UP, x, y, b
        Case "dblclick"
            Dim As Long x = Val(NextWord(l)), y = Val(NextWord(l))
            QueueMouse EV_MOVE, x, y, 0
            QueueMouse EV_DOWN, x, y, 1: QueueMouse EV_UP, x, y, 1
            QueueMouse EV_DOWN, x, y, 1, True: QueueMouse EV_UP, x, y, 1
        Case "move"
            Dim As Long x = Val(NextWord(l)), y = Val(NextWord(l))
            QueueMouse EV_MOVE, x, y, 0
        Case "drag"
            Dim As Long x1 = Val(NextWord(l)), y1 = Val(NextWord(l)), x2 = Val(NextWord(l)), y2 = Val(NextWord(l))
            Dim As Long b = IIf(LCase(NextWord(l)) = "right", 2, 1), i
            QueueMouse EV_MOVE, x1, y1, 0: QueueMouse EV_DOWN, x1, y1, b
            For i = 1 To 10
                QueueMouse EV_MOVE, x1 + (x2 - x1) * i \ 10, y1 + (y2 - y1) * i \ 10, b
            Next i
            QueueMouse EV_UP, x2, y2, b
        Case "key"
            QueueKeyCombo NextWord(l)
        Case "type"
            QueueType l
        Case "wait"
            ScriptWaitUntil = Timer + Val(NextWord(l)) / 1000
            Exit Do
        Case "shot"
            ShotRequested = NextWord(l)
            Exit Do
        Case "log"
            LogLine l
        Case "quit"
            QuitRequested = True
            Exit Do
        End Select
        If EvHead <> EvTail Then Exit Do
    Loop
End Sub

' ---- real input ----

Dim Shared LastDownTime As Double, LastDownX As Long, LastDownY As Long

Function ScanToKey(ByVal sc As Long) As Long
    Select Case sc
    Case FB.SC_ESCAPE: Return K_ESC
    Case FB.SC_ENTER: Return K_ENTER
    Case FB.SC_TAB: Return K_TAB
    Case FB.SC_BACKSPACE: Return K_BACK
    Case FB.SC_UP: Return K_UP
    Case FB.SC_DOWN: Return K_DOWN
    Case FB.SC_LEFT: Return K_LEFT
    Case FB.SC_RIGHT: Return K_RIGHT
    Case FB.SC_HOME: Return K_HOME
    Case FB.SC_END: Return K_END
    Case FB.SC_PAGEUP: Return K_PGUP
    Case FB.SC_PAGEDOWN: Return K_PGDN
    Case FB.SC_DELETE: Return K_DEL
    Case FB.SC_INSERT: Return K_INS
    Case FB.SC_F1 To FB.SC_F10: Return K_F1 + sc - FB.SC_F1
    Case FB.SC_F11: Return K_F1 + 10
    Case FB.SC_F12: Return K_F1 + 11
    Case FB.SC_SPACE: Return K_SPACE
    End Select
    Return 0
End Function

Function PollEvent(ByRef ev As UIEvent) As Boolean
    Dim blank As UIEvent
    ev = blank
    If EvHead <> EvTail Then
        ev = EvQueue(EvHead)
        EvHead = (EvHead + 1) And 255
    ElseIf Not HeadlessMode Then
        Dim e As FB.EVENT
        Static lastZ As Long
        ' Where the pointer is, read directly: some X servers send presses
        ' but no motion. A change becomes a move event of our own.
        Dim As Long gx, gy, gz, gb
        If GetMouse(gx, gy, gz, gb) = 0 AndAlso (gx <> MouseX Or gy <> MouseY) AndAlso gx >= 0 Then
            ev.kind = EV_MOVE: ev.x = gx: ev.y = gy
            MouseX = gx: MouseY = gy
            Return True
        End If
        If ScreenEvent(@e) = 0 Then Return False
        Select Case e.type
        Case FB.EVENT_MOUSE_MOVE
            ev.kind = EV_MOVE: ev.x = e.x: ev.y = e.y
            If ev.x = MouseX And ev.y = MouseY Then Return False
        Case FB.EVENT_MOUSE_BUTTON_PRESS, FB.EVENT_MOUSE_DOUBLE_CLICK
            ev.kind = EV_DOWN: ev.x = MouseX: ev.y = MouseY
            ev.btn = IIf(e.button = FB.BUTTON_RIGHT, 2, IIf(e.button = FB.BUTTON_MIDDLE, 4, 1))
            ev.dbl = (e.type = FB.EVENT_MOUSE_DOUBLE_CLICK)
        Case FB.EVENT_MOUSE_BUTTON_RELEASE
            ev.kind = EV_UP: ev.x = MouseX: ev.y = MouseY
            ev.btn = IIf(e.button = FB.BUTTON_RIGHT, 2, IIf(e.button = FB.BUTTON_MIDDLE, 4, 1))
        Case FB.EVENT_MOUSE_WHEEL
            ev.kind = EV_WHEEL: ev.x = MouseX: ev.y = MouseY: ev.wheel = e.z - lastZ: lastZ = e.z
        Case FB.EVENT_KEY_PRESS, FB.EVENT_KEY_REPEAT
            ev.kind = EV_KEY
            ev.key = ScanToKey(e.scancode)
            Dim As Long a = e.ascii
            If a >= 32 And a < 256 And a <> 127 Then ev.ch = Chr(a)
            If ev.key = 0 Then
                If a >= 1 And a <= 26 Then
                    ev.key = Asc("A") + a - 1          ' Ctrl+letter arrives as a control code
                ElseIf a >= 32 Then
                    ev.key = Asc(UCase(Chr(a)))
                End If
            End If
            If ev.key = 0 Then Return False
        Case FB.EVENT_WINDOW_CLOSE
            ev.kind = EV_CLOSE
        Case Else
            Return False
        End Select
        ev.shift = MultiKey(FB.SC_LSHIFT) Or MultiKey(FB.SC_RSHIFT)
        ev.ctrl = MultiKey(FB.SC_CONTROL)
        ev.alt = MultiKey(FB.SC_ALT)
        If ev.ctrl And ev.kind = EV_KEY Then ev.ch = ""
    Else
        Return False
    End If
    If ev.kind = EV_MOVE Or ev.kind = EV_DOWN Or ev.kind = EV_UP Then MouseX = ev.x: MouseY = ev.y
    If ev.kind = EV_DOWN Then MouseBtn Or= ev.btn
    If ev.kind = EV_UP Then MouseBtn And= Not ev.btn
    ' our own double-click detection, the same everywhere
    If ev.kind = EV_DOWN And ev.btn = 1 And Not ev.dbl Then
        If Timer - LastDownTime < 0.45 And Abs(ev.x - LastDownX) < 4 And Abs(ev.y - LastDownY) < 4 Then
            ev.dbl = True
            LastDownTime = 0
        Else
            LastDownTime = Timer: LastDownX = ev.x: LastDownY = ev.y
        End If
    End If
    Return True
End Function

' ---- dialogs ----

Enum
    CT_LABEL = 1
    CT_BUTTON
    CT_EDIT
    CT_ICON
    CT_LIST
    CT_COMBO
    CT_CUSTOM
End Enum

Const MB_OK = 0, MB_OKCANCEL = 1, MB_YESNOCANCEL = 3, MB_YESNO = 4
Const MB_CRITICAL = 16, MB_QUESTION = 32, MB_EXCLAMATION = 48, MB_INFO = 64
Const MB_DEFBUTTON2 = 256
Const IDOK = 1, IDCANCEL = 2, IDYES = 6, IDNO = 7

Type TCtl
    kind As Long
    x As Long
    y As Long
    w As Long
    h As Long
    text As String
    id As Long
    isDefault As Boolean
    isCancel As Boolean
    hidden As Boolean
    disabled As Boolean
    pressed As Boolean
    selStart As Long        ' edit: selection anchor
    caret As Long           ' edit: caret position (selection is anchor..caret)
    scrollX As Long
    sel As Long             ' list: selected row
    top As Long             ' list: first row shown
    tag As Long
End Type

Const MAX_CTL = 40

Type TDlg
    title As String
    x As Long
    y As Long
    w As Long
    h As Long
    nCtl As Long
    c(0 To MAX_CTL - 1) As TCtl
    focus As Long
    result As Long
    done As Boolean
    noFrame As Boolean      ' draws everything itself (the blue screen)
    drawFn As Sub(ByVal d As Any Ptr)                             ' extra drawing
    clickFn As Function(ByVal d As Any Ptr, ByVal ci As Long) As Boolean   ' a button: True closes
    tickFn As Sub(ByVal d As Any Ptr)
    keyFn As Function(ByVal d As Any Ptr, ByRef ev As UIEvent) As Boolean   ' True: handled
    mouseFn As Function(ByVal d As Any Ptr, ByRef ev As UIEvent) As Boolean
    user As Any Ptr
    capture As Long         ' control the mouse went down on
    dragTitle As Boolean
    dragDX As Long
    dragDY As Long
End Type

Dim Shared DlgStack(0 To 7) As TDlg Ptr
Dim Shared DlgTop As Long = -1
Dim Shared ListRows() As String                ' the list control's rows (one list at a time)
Dim Shared ListCount As Long

Const DLG_TITLE_H = 18

Function AddCtl(ByRef d As TDlg, ByVal kind As Long, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, _
                ByRef t As String = "", ByVal id As Long = 0) As Long
    Dim i As Long = d.nCtl
    d.c(i).kind = kind: d.c(i).x = x: d.c(i).y = y: d.c(i).w = w: d.c(i).h = h
    d.c(i).text = t: d.c(i).id = id
    d.nCtl += 1
    Return i
End Function

Function ClientX(ByRef d As TDlg) As Long
    Return d.x + IIf(d.noFrame, 0, 3)
End Function
Function ClientY(ByRef d As TDlg) As Long
    Return d.y + IIf(d.noFrame, 0, 3 + DLG_TITLE_H + 1)
End Function

Sub CenterDialog(ByRef d As TDlg)
    d.x = (ScrW - d.w) \ 2
    d.y = (ScrH - d.h) \ 2
End Sub

' Message box icons, 32 x 32, drawn from shapes (our own art).
Sub DrawMsgIcon(ByVal x As Long, ByVal y As Long, ByVal kind As Long)
    Dim As Long i, j
    Select Case kind
    Case MB_CRITICAL
        For j = 0 To 31: For i = 0 To 31
            Dim As Double r = Sqr((i - 15.5) ^ 2 + (j - 15.5) ^ 2)
            If r <= 14.5 Then PSetC x + i, y + j, IIf(r > 13.5, &hFF800000, &hFFFF0000)
        Next: Next
        For i = -6 To 6
            Fill x + 15 + i, y + 15 + i, 3, 2, C_HILITE
            Fill x + 15 + i, y + 15 - i, 3, 2, C_HILITE
        Next
    Case MB_EXCLAMATION
        For j = 2 To 29
            Dim As Long half = (j - 2) * 15 \ 27
            HLine x + 15 - half, y + j, half * 2 + 2, IIf(j = 29, C_DARK, &hFFFFFF00)
            PSetC x + 15 - half, y + j, C_DARK: PSetC x + 16 + half, y + j, C_DARK
        Next
        Fill x + 14, y + 10, 4, 11, C_DARK
        Fill x + 14, y + 23, 4, 3, C_DARK
    Case MB_QUESTION, MB_INFO
        ' a speech bubble
        For j = 0 To 25: For i = 0 To 31
            Dim As Double r = ((i - 15.5) / 15.5) ^ 2 + ((j - 12.5) / 12.5) ^ 2
            If r <= 1 Then PSetC x + i, y + j, IIf(r > 0.86, C_DARK, C_HILITE)
        Next: Next
        For j = 22 To 30
            HLine x + 6, y + j, IIf(j < 26, 31 - j - 3, 2), C_HILITE
            PSetC x + 5, y + j, C_DARK
        Next
        If kind = MB_QUESTION Then
            TextAt x + 11, y + 2, "?", &hFF0000FF, True, 2
        Else
            TextAt x + 13, y + 1, "i", &hFF0000FF, True, 2
        End If
    End Select
End Sub

Sub DrawEditCtl(ByRef c As TCtl, ByVal ox As Long, ByVal oy As Long, ByVal focused As Boolean)
    Dim As Long x = ox + c.x, y = oy + c.y
    Bevel x, y, c.w, c.h, BEV_SUNKEN
    Fill x + 2, y + 2, c.w - 4, c.h - 4, IIf(c.disabled, C_FACE, C_WINDOW)
    Dim As Long a = c.selStart, b = c.caret
    If a > b Then Swap a, b
    If Not focused Then a = b
    ' keep the caret in view
    Dim As Long cx = TextW(Left(c.text, c.caret)) + IIf(c.caret > 0, 1, 0)
    If cx - c.scrollX > c.w - 10 Then c.scrollX = cx - (c.w - 10)
    If cx - c.scrollX < 0 Then c.scrollX = cx
    Dim As Long tx = x + 4 - c.scrollX, ty = y + (c.h - 11) \ 2
    ClipTo x + 2, y + 2, c.w - 4, c.h - 4
    If b > a Then
        Dim As Long sx1 = tx + TextW(Left(c.text, a)) + IIf(a > 0, 1, 0)
        Dim As Long sx2 = tx + TextW(Left(c.text, b)) + 1
        Fill sx1, ty - 1, sx2 - sx1, 13, C_SEL
        Text tx, ty, Left(c.text, a), C_TEXT
        Text sx1, ty, Mid(c.text, a + 1, b - a), C_SELTEXT
        Text sx2 + IIf(b < Len(c.text), 0, 0), ty, Mid(c.text, b + 1), C_TEXT
    Else
        Text tx, ty, c.text, IIf(c.disabled, C_GRAYTEXT, C_TEXT)
    End If
    If focused And (CLng(Int(Timer * 2)) Mod 2 = 0 Or HeadlessMode) Then
        VLine tx + cx - 1, ty - 1, 13, C_TEXT
    End If
    NoClip
End Sub

Sub DrawScrollV(ByVal x As Long, ByVal y As Long, ByVal h As Long, ByVal total As Long, ByVal shown As Long, ByVal first As Long)
    ' a Windows 98 vertical scroll bar, 16 wide: arrows, track, thumb
    Fill x, y, 16, h, &hFFE0E0E0
    Fill x, y, 16, 16, C_FACE: Bevel x, y, 16, 16, BEV_BUTTON
    Fill x, y + h - 16, 16, 16, C_FACE: Bevel x, y + h - 16, 16, 16, BEV_BUTTON
    Dim As Long i
    For i = 0 To 3
        HLine x + 8 - i, y + 6 + i, 1 + i * 2, C_DARK
        HLine x + 8 - i, y + h - 7 - i, 1 + i * 2, C_DARK
    Next
    If total > shown And total > 0 Then
        Dim As Long track = h - 32, th = track * shown \ total
        If th < 8 Then th = 8
        Dim As Long ty = y + 16 + (track - th) * first \ IIf(total - shown > 0, total - shown, 1)
        Fill x, ty, 16, th, C_FACE: Bevel x, ty, 16, th, BEV_BUTTON
    End If
End Sub

Const LIST_ROW_H = 16

Sub DrawListCtl(ByRef d As TDlg, ByVal level As Long, ByRef c As TCtl, ByVal ox As Long, ByVal oy As Long, ByVal focused As Boolean)
    Dim As Long x = ox + c.x, y = oy + c.y, i, rows = (c.h - 4) \ LIST_ROW_H
    Dim As Long n = ListCount
    Bevel x, y, c.w, c.h, BEV_SUNKEN
    Fill x + 2, y + 2, c.w - 4, c.h - 4, C_WINDOW
    Dim As Long iw = c.w - 4 - IIf(n > rows, 16, 0)
    ClipTo x + 2, y + 2, iw, c.h - 4
    For i = c.top To c.top + rows - 1
        If i >= n Then Exit For
        Dim As String it = ListRows(i)
        Dim As Long ry = y + 2 + (i - c.top) * LIST_ROW_H
        Dim As String nm = Mid(it, 2)
        DrawIcon x + 4, ry, IIf(Left(it, 1) = "D", "Open", "New")
        If i = c.sel Then
            Fill x + 22, ry + 1, TextW(nm) + 4, 14, IIf(focused, C_SEL, C_FACE)
            Text x + 24, ry + 3, nm, IIf(focused, C_SELTEXT, C_TEXT)
            If focused Then FocusRect x + 22, ry + 1, TextW(nm) + 4, 14
        Else
            Text x + 24, ry + 3, nm, C_TEXT
        End If
    Next
    NoClip
    If n > rows Then DrawScrollV x + c.w - 18, y + 2, c.h - 4, n, rows, c.top
End Sub

Sub DrawButtonCtl(ByRef c As TCtl, ByVal ox As Long, ByVal oy As Long, ByVal focused As Boolean, ByVal isDef As Boolean)
    Dim As Long x = ox + c.x, y = oy + c.y, w = c.w, h = c.h, off
    Fill x, y, w, h, C_FACE
    If isDef Then Frame x, y, w, h, C_DARK: x += 1: y += 1: w -= 2: h -= 2
    If c.pressed Then
        Bevel x, y, w, h, BEV_PRESSED: off = 1
    Else
        Bevel x, y, w, h, BEV_BUTTON
    End If
    Dim As Long tw = TextW(AmpStrip(c.text))
    TextAmp x + (w - tw) \ 2 + off, y + (h - 11) \ 2 + off, c.text, C_TEXT, c.disabled
    If focused Then FocusRect x + 3, y + 3, w - 6, h - 6
End Sub

Sub DrawComboCtl(ByRef c As TCtl, ByVal ox As Long, ByVal oy As Long, ByVal focused As Boolean)
    Dim As Long x = ox + c.x, y = oy + c.y, i
    Bevel x, y, c.w, c.h, BEV_SUNKEN
    Fill x + 2, y + 2, c.w - 4, c.h - 4, C_WINDOW
    ClipTo x + 2, y + 2, c.w - 22, c.h - 4
    If focused Then
        Fill x + 3, y + 3, TextW(c.text) + 4, c.h - 6, C_SEL
        Text x + 5, y + (c.h - 11) \ 2, c.text, C_SELTEXT
    Else
        Text x + 5, y + (c.h - 11) \ 2, c.text, C_TEXT
    End If
    NoClip
    Dim As Long bx = x + c.w - 18, by = y + 2
    Fill bx, by, 16, c.h - 4, C_FACE: Bevel bx, by, 16, c.h - 4, BEV_BUTTON
    For i = 0 To 3
        HLine bx + 4 + i, by + (c.h - 4) \ 2 - 2 + i, 7 - i * 2, C_DARK
    Next
End Sub

Sub DrawDialog(ByVal level As Long)
    Dim d As TDlg Ptr = DlgStack(level)
    Dim As Long i, ox, oy
    Dim As Boolean isTop = (level = DlgTop)
    With *d
        If Not .noFrame Then
            Fill .x, .y, .w, .h, C_FACE
            Bevel .x, .y, .w, .h, BEV_RAISED
            GradientH .x + 3, .y + 3, .w - 6, DLG_TITLE_H, IIf(isTop, C_TITLE1, C_TITLEI1), IIf(isTop, C_TITLE2, C_TITLEI2)
            ClipTo .x + 3, .y + 3, .w - 26, DLG_TITLE_H
            Text .x + 7, .y + 6, .title, IIf(isTop, C_HILITE, &hFFD4D0C8), True
            NoClip
            ' the close box
            Dim As Long bx = .x + .w - 21, by = .y + 5
            Fill bx, by, 16, 14, C_FACE: Bevel bx, by, 16, 14, BEV_BUTTON
            For i = 0 To 5
                Fill bx + 4 + i, by + 3 + i, 2, 1, C_DARK
                Fill bx + 9 - i, by + 3 + i, 2, 1, C_DARK
            Next
        End If
        ox = ClientX(*d): oy = ClientY(*d)
        For i = 0 To .nCtl - 1
            If .c(i).hidden Then Continue For
            Dim As Boolean foc = isTop And (i = .focus)
            Select Case .c(i).kind
            Case CT_LABEL
                Dim As String t = .c(i).text
                Dim As Long ly = oy + .c(i).y
                Do
                    Dim As Long p = InStr(t, Chr(10))
                    Dim As String ln = IIf(p, Left(t, p - 1), t)
                    If .c(i).disabled Then TextDisabled ox + .c(i).x, ly, ln Else TextAmp ox + .c(i).x, ly, ln, C_TEXT
                    ly += LINE_H
                    If p = 0 Then Exit Do
                    t = Mid(t, p + 1)
                Loop
            Case CT_BUTTON
                Dim As Boolean isDef = .c(i).isDefault
                ' the focused button is the default while focus is on a button
                If .c(.focus).kind = CT_BUTTON Then isDef = (i = .focus)
                DrawButtonCtl .c(i), ox, oy, foc, isDef And isTop
            Case CT_EDIT
                DrawEditCtl .c(i), ox, oy, foc
            Case CT_ICON
                DrawMsgIcon ox + .c(i).x, oy + .c(i).y, .c(i).tag
            Case CT_LIST
                DrawListCtl *d, level, .c(i), ox, oy, foc
            Case CT_COMBO
                DrawComboCtl .c(i), ox, oy, foc
            End Select
        Next
        If .drawFn <> 0 Then .drawFn(d)
    End With
End Sub

' The mouse pointer: our own arrow, drawn last (the console has none).
Sub DrawPointer()
    Static arrow(0 To 18) As ZString * 13 = { _
        "X...........", "XX..........", "XWX.........", "XWWX........", "XWWWX.......", "XWWWWX......", _
        "XWWWWWX.....", "XWWWWWWX....", "XWWWWWWWX...", "XWWWWWWWWX..", "XWWWWWWWWWX.", "XWWWWWXXXXXX", _
        "XWWXWWX.....", "XWX.XWWX....", "XX..XWWX....", "X....XWWX...", ".....XWWX...", "......XWWX..", "......XXX..." }
    Static glass(0 To 18) As ZString * 13 = { _
        "XXXXXXXXXXX.", "XWWWWWWWWWX.", ".XWWWWWWWX..", ".XWXWXWXWX..", ".XWWXWXWWX..", "..XWWXWWX...", _
        "...XWXWX....", "....XWX.....", "....XWX.....", "...XWWWX....", "..XWWXWWX...", ".XWWWWWWWX..", _
        ".XWWWXWWWX..", ".XWWXWXWWX..", "XWXWXWXWXWX.", "XXXXXXXXXXX.", "............", "............", "............" }
    Dim As Long r, c
    For r = 0 To 18
        For c = 0 To 11
            Dim As Long ch = IIf(Busy, glass(r)[c], arrow(r)[c])
            If ch = Asc("X") Then PSetC MouseX + c, MouseY + r, C_DARK
            If ch = Asc("W") Then PSetC MouseX + c, MouseY + r, C_HILITE
        Next
    Next
End Sub

' What was under the pointer, so it can move without redrawing the screen.
Const PTR_W = 12, PTR_H = 19
Dim Shared PtrUnder(0 To PTR_W * PTR_H - 1) As ULong
Dim Shared PtrX As Long = -1000, PtrY As Long = -1000
Dim Shared PointerMoved As Boolean

Sub SavePointerArea()
    Dim As Long r, c
    PtrX = MouseX: PtrY = MouseY
    For r = 0 To PTR_H - 1
        For c = 0 To PTR_W - 1
            PtrUnder(r * PTR_W + c) = PGet(PtrX + c, PtrY + r)
        Next
    Next
End Sub

Sub RestorePointerArea()
    Dim As Long r, c
    For r = 0 To PTR_H - 1
        For c = 0 To PTR_W - 1
            PSetC PtrX + c, PtrY + r, PtrUnder(r * PTR_W + c)
        Next
    Next
End Sub

Function ShowPointer() As Boolean
    Return Not HeadlessMode Or Len(ShotRequested) > 0
End Function

Sub RenderFrame()
    ScreenLock
    SurfFromScreen S
    AppRender
    Dim i As Long
    For i = 0 To DlgTop
        DrawDialog i
    Next
    If ShowPointer() Then SavePointerArea: DrawPointer
    ScreenUnlock
    PointerMoved = False
End Sub

' Only the pointer moved: put back what was under it, draw it at the new
' place, and send just those rows to the screen.
Sub MovePointer()
    PointerMoved = False
    If Not ShowPointer() Then Exit Sub
    ScreenLock
    SurfFromScreen S
    Dim As Long y0 = PtrY
    RestorePointerArea
    SavePointerArea
    DrawPointer
    Dim As Long a = IIf(y0 < PtrY, y0, PtrY), b = IIf(y0 > PtrY, y0, PtrY) + PTR_H
    If a < 0 Then a = 0
    If b > ScrH - 1 Then b = ScrH - 1
    If a > ScrH - 1 Then a = ScrH - 1
    ScreenUnlock a, b
End Sub

' One turn of the event loop: script, input, timers, drawing.
Declare Sub DialogEvent(ByVal d As TDlg Ptr, ByRef ev As UIEvent)

Sub UIStep()
    Dim ev As UIEvent
    ScriptStep
    Dim As Long n = 0
    Do While PollEvent(ev)
        ' a move only moves the pointer, unless whatever handles it says otherwise
        If ev.kind = EV_MOVE Then PointerMoved = True Else NeedRedraw = True
        If ev.kind = EV_CLOSE Then
            If DlgTop >= 0 Then
                DlgStack(DlgTop)->result = 0: DlgStack(DlgTop)->done = True
            Else
                AppEvent ev
            End If
        ElseIf DlgTop >= 0 Then
            DialogEvent DlgStack(DlgTop), ev
        Else
            AppEvent ev
        End If
        n += 1
        If n > 40 OrElse (DlgTop >= 0 AndAlso DlgStack(DlgTop)->done) Then Exit Do
    Loop
    AppTick
    If DlgTop >= 0 AndAlso DlgStack(DlgTop)->tickFn <> 0 Then DlgStack(DlgTop)->tickFn(DlgStack(DlgTop))
    ' redraw only when something changed: an event, a ticking dialog, or the
    ' caret blinking (twice a second); a Pi 1 has better things to do
    Static lastBlink As Long
    Dim As Long blink = CLng(Int(Timer * 2))
    If blink <> lastBlink Then lastBlink = blink: If DlgTop >= 0 Then NeedRedraw = True
    If DlgTop >= 0 AndAlso DlgStack(DlgTop)->tickFn <> 0 Then NeedRedraw = True
    If NeedRedraw Then
        RenderFrame
        NeedRedraw = False
    ElseIf PointerMoved Then
        MovePointer
    End If
    If Len(ShotRequested) Then
        RenderFrame
        BSave ShotRequested, 0
        LogLine "shot " & ShotRequested
        ShotRequested = ""
    End If
    If HeadlessMode Then
        Sleep 1, 1
    Else
        Sleep 12, 1
    End If
End Sub

' Shows a dialog and runs until it closes. Returns its result.
Function RunDialog(ByRef d As TDlg) As Long
    DlgTop += 1
    DlgStack(DlgTop) = @d
    d.done = False
    d.capture = -1
    NeedRedraw = True
    Do
        UIStep
        ' a test script that has run out leaves no dialog waiting for a person
        If HeadlessMode AndAlso ScriptPos >= ScriptCount AndAlso EvHead = EvTail AndAlso Timer >= ScriptWaitUntil Then d.done = True: d.result = 0
    Loop Until d.done
    DlgTop -= 1
    NeedRedraw = True
    Return d.result
End Function

' ---- dialog input ----

Function Focusable(ByRef c As TCtl) As Boolean
    Return Not c.hidden And Not c.disabled And (c.kind = CT_BUTTON Or c.kind = CT_EDIT Or c.kind = CT_LIST Or c.kind = CT_COMBO)
End Function

Sub SetFocus(ByRef d As TDlg, ByVal i As Long)
    d.focus = i
    If d.c(i).kind = CT_EDIT Then
        d.c(i).selStart = 0: d.c(i).caret = Len(d.c(i).text)     ' focus selects it all, so typing replaces it
    End If
End Sub

Sub NextFocus(ByRef d As TDlg, ByVal dirn As Long)
    Dim As Long i = d.focus, n
    For n = 1 To d.nCtl
        i = (i + dirn + d.nCtl) Mod d.nCtl
        If Focusable(d.c(i)) Then SetFocus d, i: Exit Sub
    Next
End Sub

Sub PressButton(ByVal d As TDlg Ptr, ByVal i As Long)
    If d->clickFn <> 0 Then
        If d->clickFn(d, i) Then d->done = True
    Else
        d->result = d->c(i).id: d->done = True
    End If
End Sub

Function FindButton(ByRef d As TDlg, ByVal wantDefault As Boolean) As Long
    Dim i As Long
    For i = 0 To d.nCtl - 1
        If d.c(i).kind = CT_BUTTON And Not d.c(i).hidden And Not d.c(i).disabled Then
            If wantDefault And d.c(i).isDefault Then Return i
            If Not wantDefault And d.c(i).isCancel Then Return i
        End If
    Next
    Return -1
End Function

Function HitCtl(ByRef d As TDlg, ByVal x As Long, ByVal y As Long) As Long
    Dim As Long i, ox = ClientX(d), oy = ClientY(d)
    For i = d.nCtl - 1 To 0 Step -1
        With d.c(i)
            If Not .hidden And x >= ox + .x And x < ox + .x + .w And y >= oy + .y And y < oy + .y + .h Then Return i
        End With
    Next
    Return -1
End Function

Function EditPosAt(ByRef c As TCtl, ByVal px As Long) As Long
    Dim As Long i, best = 0
    For i = 0 To Len(c.text)
        If TextW(Left(c.text, i)) <= px Then best = i
    Next
    Return best
End Function

Sub EditKey(ByRef c As TCtl, ByRef ev As UIEvent)
    Dim As Long a = c.selStart, b = c.caret
    If a > b Then Swap a, b
    Select Case ev.key
    Case K_LEFT
        If c.caret > 0 Then c.caret -= 1
        If Not ev.shift Then c.selStart = c.caret
    Case K_RIGHT
        If c.caret < Len(c.text) Then c.caret += 1
        If Not ev.shift Then c.selStart = c.caret
    Case K_HOME
        c.caret = 0: If Not ev.shift Then c.selStart = 0
    Case K_END
        c.caret = Len(c.text): If Not ev.shift Then c.selStart = c.caret
    Case K_BACK
        If b > a Then
            c.text = Left(c.text, a) & Mid(c.text, b + 1): c.caret = a
        ElseIf c.caret > 0 Then
            c.text = Left(c.text, c.caret - 1) & Mid(c.text, c.caret + 1): c.caret -= 1
        End If
        c.selStart = c.caret
    Case K_DEL
        If b > a Then
            c.text = Left(c.text, a) & Mid(c.text, b + 1): c.caret = a
        ElseIf c.caret < Len(c.text) Then
            c.text = Left(c.text, c.caret) & Mid(c.text, c.caret + 2)
        End If
        c.selStart = c.caret
    Case Else
        If ev.ctrl And ev.key = Asc("A") Then
            c.selStart = 0: c.caret = Len(c.text)
        ElseIf Len(ev.ch) And Not ev.ctrl Then
            c.text = Left(c.text, a) & ev.ch & Mid(c.text, b + 1)
            c.caret = a + 1: c.selStart = c.caret
        End If
    End Select
End Sub

Sub ListEnsureVisible(ByRef c As TCtl)
    Dim As Long rows = (c.h - 4) \ LIST_ROW_H
    If c.sel < c.top Then c.top = c.sel
    If c.sel >= c.top + rows Then c.top = c.sel - rows + 1
    If c.top < 0 Then c.top = 0
End Sub

Sub DialogEvent(ByVal d As TDlg Ptr, ByRef ev As UIEvent)
    Dim As Long i, ox = ClientX(*d), oy = ClientY(*d)
    If d->mouseFn <> 0 AndAlso ev.kind <> EV_KEY Then
        If d->mouseFn(d, ev) Then Exit Sub
    End If
    Select Case ev.kind
    Case EV_DOWN
        ' the title bar: drag the dialog; the close box: cancel
        If Not d->noFrame And ev.y >= d->y + 3 And ev.y < d->y + 3 + DLG_TITLE_H And ev.x >= d->x And ev.x < d->x + d->w Then
            If ev.x >= d->x + d->w - 21 Then
                i = FindButton(*d, False)
                If i >= 0 Then PressButton d, i Else d->result = 0: d->done = True
            Else
                d->dragTitle = True: d->dragDX = ev.x - d->x: d->dragDY = ev.y - d->y
            End If
            Exit Sub
        End If
        i = HitCtl(*d, ev.x, ev.y)
        d->capture = i
        If i < 0 Then Exit Sub
        With d->c(i)
            If .disabled Then Exit Sub
            Select Case .kind
            Case CT_BUTTON
                .pressed = True: d->focus = i
            Case CT_EDIT
                If d->focus <> i Then d->focus = i
                .caret = EditPosAt(d->c(i), ev.x - (ox + .x + 4) + .scrollX)
                .selStart = .caret
                If ev.dbl Then .selStart = 0: .caret = Len(.text)
            Case CT_LIST
                d->focus = i
                Dim As Long n = ListCount, rows = (.h - 4) \ LIST_ROW_H
                If n > rows And ev.x >= ox + .x + .w - 18 Then
                    ' the scroll bar: arrows step, the track pages
                    If ev.y < oy + .y + 18 Then
                        .top -= 1
                    ElseIf ev.y > oy + .y + .h - 18 Then
                        .top += 1
                    ElseIf ev.y < oy + .y + .h \ 2 Then
                        .top -= rows
                    Else
                        .top += rows
                    End If
                    If .top > n - rows Then .top = n - rows
                    If .top < 0 Then .top = 0
                Else
                    Dim As Long r = .top + (ev.y - (oy + .y + 2)) \ LIST_ROW_H
                    If r >= 0 And r < n Then
                        .sel = r
                        If d->clickFn <> 0 Then
                            .tag = IIf(ev.dbl, 2, 1)
                            If d->clickFn(d, i) Then d->done = True
                        End If
                    End If
                End If
            Case CT_COMBO
                d->focus = i
                If d->clickFn <> 0 Then
                    If d->clickFn(d, i) Then d->done = True
                End If
            Case CT_CUSTOM
                If d->clickFn <> 0 Then
                    If d->clickFn(d, i) Then d->done = True
                End If
            End Select
        End With
    Case EV_MOVE
        If d->dragTitle Or d->capture >= 0 Then NeedRedraw = True
        If d->dragTitle Then
            d->x = ev.x - d->dragDX: d->y = ev.y - d->dragDY
        ElseIf d->capture >= 0 Then
            With d->c(d->capture)
                If .kind = CT_BUTTON Then
                    .pressed = (HitCtl(*d, ev.x, ev.y) = d->capture)
                ElseIf .kind = CT_EDIT And (MouseBtn And 1) Then
                    .caret = EditPosAt(d->c(d->capture), ev.x - (ox + .x + 4) + .scrollX)
                End If
            End With
        End If
    Case EV_UP
        d->dragTitle = False
        If d->capture >= 0 Then
            i = d->capture
            d->capture = -1
            If d->c(i).kind = CT_BUTTON And d->c(i).pressed Then
                d->c(i).pressed = False
                If HitCtl(*d, ev.x, ev.y) = i Then PressButton d, i
            End If
        End If
    Case EV_WHEEL
        If d->focus >= 0 AndAlso d->c(d->focus).kind = CT_LIST Then
            d->c(d->focus).top -= ev.wheel * 3
            If d->c(d->focus).top < 0 Then d->c(d->focus).top = 0
        End If
    Case EV_KEY
        If d->keyFn <> 0 Then
            If d->keyFn(d, ev) Then Exit Sub
        End If
        Dim As Long f = d->focus
        Select Case ev.key
        Case K_TAB
            NextFocus *d, IIf(ev.shift, -1, 1)
        Case K_ESC
            i = FindButton(*d, False)
            If i >= 0 Then PressButton d, i Else d->result = 0: d->done = True
        Case K_ENTER
            If f >= 0 AndAlso d->c(f).kind = CT_BUTTON Then
                PressButton d, f
            ElseIf f >= 0 AndAlso d->c(f).kind = CT_LIST AndAlso d->clickFn <> 0 Then
                d->c(f).tag = 2
                If d->clickFn(d, f) Then d->done = True
            Else
                i = FindButton(*d, True)
                If i >= 0 Then PressButton d, i
            End If
        Case Else
            If f >= 0 Then
                Select Case d->c(f).kind
                Case CT_EDIT
                    EditKey d->c(f), ev
                Case CT_BUTTON
                    If ev.key = K_SPACE Then PressButton d, f
                Case CT_LIST
                    Dim As Long n = ListCount
                    If ev.key = K_UP And d->c(f).sel > 0 Then d->c(f).sel -= 1
                    If ev.key = K_DOWN And d->c(f).sel < n - 1 Then d->c(f).sel += 1
                    If ev.key = K_UP Or ev.key = K_DOWN Then
                        ListEnsureVisible d->c(f)
                        If d->clickFn <> 0 Then d->c(f).tag = 1: If d->clickFn(d, f) Then d->done = True
                    End If
                End Select
            End If
            ' Alt+letter, or a plain letter when no text box has focus: the button with that hot key
            If Len(ev.ch) Or ev.alt Then
                If ev.alt Or (f >= 0 AndAlso d->c(f).kind <> CT_EDIT) Then
                    For i = 0 To d->nCtl - 1
                        If d->c(i).kind = CT_BUTTON And Not d->c(i).hidden Then
                            Dim As Long p = InStr(d->c(i).text, "&")
                            If p AndAlso UCase(Mid(d->c(i).text, p + 1, 1)) = Chr(ev.key) Then PressButton d, i: Exit For
                        End If
                    Next
                End If
            End If
        End Select
    End Select
End Sub

' ---- MsgBox, as VB had it ----

Function MsgBox(ByRef prompt As String, ByVal flags As Long = 0, ByRef title As String = "SolidCraft 98") As Long
    Dim d As TDlg
    Busy = False                 ' a question needs the arrow, not the hourglass
    Dim As Long i, tw, nl = 1, iconKind = flags And &h70, btnSet = flags And 7
    Dim As String t = prompt, ln
    ' measure the text
    Do
        Dim As Long p = InStr(t, Chr(10))
        ln = IIf(p, Left(t, p - 1), t)
        If TextW(ln) > tw Then tw = TextW(ln)
        If p = 0 Then Exit Do
        t = Mid(t, p + 1): nl += 1
    Loop
    Dim As Long iconW = IIf(iconKind, 32 + 16, 0)
    Dim As Long textH = nl * LINE_H
    Dim As Long bodyH = IIf(textH > 32 And iconKind, textH, IIf(iconKind, 32, textH))
    Dim As String caps(2)
    Dim As Long ids(2), nb
    Select Case btnSet
    Case MB_OKCANCEL: caps(0) = "OK": ids(0) = IDOK: caps(1) = "Cancel": ids(1) = IDCANCEL: nb = 2
    Case MB_YESNOCANCEL: caps(0) = "&Yes": ids(0) = IDYES: caps(1) = "&No": ids(1) = IDNO: caps(2) = "Cancel": ids(2) = IDCANCEL: nb = 3
    Case MB_YESNO: caps(0) = "&Yes": ids(0) = IDYES: caps(1) = "&No": ids(1) = IDNO: nb = 2
    Case Else: caps(0) = "OK": ids(0) = IDOK: nb = 1
    End Select
    Dim As Long bw = 75, bh = 23, gap = 6, btnRow = nb * bw + (nb - 1) * gap
    Dim As Long cw = 12 + iconW + tw + 20
    If cw < btnRow + 24 Then cw = btnRow + 24
    If cw < TextW(title, True) + 50 Then cw = TextW(title, True) + 50
    Dim As Long ch = 12 + bodyH + 18 + bh + 12
    d.w = cw + 6: d.h = ch + 3 + DLG_TITLE_H + 1 + 3
    d.title = title
    CenterDialog d
    If iconKind Then
        i = AddCtl(d, CT_ICON, 12, 12, 32, 32): d.c(i).tag = iconKind
    End If
    AddCtl d, CT_LABEL, 12 + iconW, 12 + IIf(iconKind And textH < 32, (32 - textH) \ 2, 0), tw, textH, prompt
    Dim As Long bx = (cw - btnRow) \ 2, defIdx = IIf(flags And MB_DEFBUTTON2, 1, 0)
    For i = 0 To nb - 1
        Dim As Long ci = AddCtl(d, CT_BUTTON, bx + i * (bw + gap), 12 + bodyH + 18, bw, bh, caps(i), ids(i))
        d.c(ci).isDefault = (i = defIdx)
        d.c(ci).isCancel = (ids(i) = IDCANCEL) Or (nb = 1) Or (btnSet = MB_YESNO And ids(i) = IDNO)
        If i = defIdx Then d.focus = ci
    Next
    LogLine "msgbox: " & Left(prompt, 60)
    Dim As Long r = RunDialog(d)
    If r = 0 Then r = IIf(btnSet = MB_YESNO, IDNO, IIf(btnSet = MB_OK, IDOK, IDCANCEL))
    Return r
End Function
