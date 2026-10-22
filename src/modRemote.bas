Attribute VB_Name = "modRemote"
' modRemote - remote control. Started with /REMOTE (or /REMOTE:port),
' SolidCraft 98 listens on TCP port 9898, the way remote-administration
' tools of the day did, and takes one command per line from whoever
' connects. It answers in text, reading the screen the way a screen reader
' does. Each answer ends with a line holding a single ".".
'
'   look                      what's on the screen
'   click <name>              a button, menu, field, feature or toolbar
'   click <x> <y>             button, by the name the read-out gives it
'   dblclick <name>|<x> <y>   (a feature in the timeline: edit it)
'   rclick <name>|<x> <y>
'   drag <x1> <y1> <x2> <y2> [right]
'   menu <title> > <item>     e.g. "menu File > Save As..."
'   key <keys>                e.g. "key e", "key ctrl+s", "key enter"
'   type <text>
'   wait <ms>
'   help
'   quit                      ends SolidCraft 98 at once, nothing saved
'
' Clicks and keys go in as real mouse and keyboard input, a step at a time,
' so anyone watching sees the pointer move and the letters appear. Actions
' answer "ok" once the screen has settled, or "error: ..." if they can't.
Option Explicit

' ---- Winsock ----

Private Type WSADATA
    wVersion As Integer
    wHighVersion As Integer
    szDescription(0 To 256) As Byte
    szSystemStatus(0 To 128) As Byte
    iMaxSockets As Integer
    iMaxUdpDg As Integer
    lpVendorInfo As Long
End Type

Private Type SOCKADDR_IN
    sin_family As Integer
    sin_port As Integer
    sin_addr As Long
    sin_zero(0 To 7) As Byte
End Type

Private Declare Function ws_WSAStartup Lib "wsock32.dll" Alias "WSAStartup" (ByVal wVersion As Integer, lpWSAData As WSADATA) As Long
Private Declare Function ws_socket Lib "wsock32.dll" Alias "socket" (ByVal af As Long, ByVal stype As Long, ByVal protocol As Long) As Long
Private Declare Function ws_bind Lib "wsock32.dll" Alias "bind" (ByVal s As Long, addr As SOCKADDR_IN, ByVal namelen As Long) As Long
Private Declare Function ws_listen Lib "wsock32.dll" Alias "listen" (ByVal s As Long, ByVal backlog As Long) As Long
Private Declare Function ws_accept Lib "wsock32.dll" Alias "accept" (ByVal s As Long, ByVal addr As Long, ByVal addrlen As Long) As Long
Private Declare Function ws_recv Lib "wsock32.dll" Alias "recv" (ByVal s As Long, buf As Any, ByVal buflen As Long, ByVal flags As Long) As Long
Private Declare Function ws_send Lib "wsock32.dll" Alias "send" (ByVal s As Long, buf As Any, ByVal buflen As Long, ByVal flags As Long) As Long
Private Declare Function ws_ioctlsocket Lib "wsock32.dll" Alias "ioctlsocket" (ByVal s As Long, ByVal cmd As Long, argp As Long) As Long
Private Declare Function ws_closesocket Lib "wsock32.dll" Alias "closesocket" (ByVal s As Long) As Long
Private Declare Function ws_htons Lib "wsock32.dll" Alias "htons" (ByVal hostshort As Integer) As Integer

Private Const AF_INET As Long = 2
Private Const SOCK_STREAM As Long = 1
Private Const FIONBIO As Long = &H8004667E
Private Const INVALID_SOCKET As Long = -1

' ---- the rest of Windows ----

Private Type RECT
    Left As Long
    Top As Long
    Right As Long
    Bottom As Long
End Type

Private Type POINTAPI
    x As Long
    y As Long
End Type

Private Declare Function SetTimer Lib "user32" (ByVal hWnd As Long, ByVal nIDEvent As Long, ByVal uElapse As Long, ByVal lpTimerFunc As Long) As Long
Private Declare Function SetCursorPos Lib "user32" (ByVal x As Long, ByVal y As Long) As Long
Private Declare Function GetCursorPos Lib "user32" (lpPoint As POINTAPI) As Long
Private Declare Sub mouse_event Lib "user32" (ByVal dwFlags As Long, ByVal dx As Long, ByVal dy As Long, ByVal cButtons As Long, ByVal dwExtraInfo As Long)
Private Declare Sub keybd_event Lib "user32" (ByVal bVk As Byte, ByVal bScan As Byte, ByVal dwFlags As Long, ByVal dwExtraInfo As Long)
Private Declare Function VkKeyScan Lib "user32" Alias "VkKeyScanA" (ByVal cChar As Byte) As Integer
Private Declare Function MapVirtualKey Lib "user32" Alias "MapVirtualKeyA" (ByVal wCode As Long, ByVal wMapType As Long) As Long
Private Declare Function GetWindowRect Lib "user32" (ByVal hWnd As Long, lpRect As RECT) As Long
Private Declare Function ClientToScreen Lib "user32" (ByVal hWnd As Long, lpPoint As POINTAPI) As Long
Private Declare Function SendMessage Lib "user32" Alias "SendMessageA" (ByVal hWnd As Long, ByVal wMsg As Long, ByVal wParam As Long, lParam As Any) As Long
Private Declare Function GetWindowText Lib "user32" Alias "GetWindowTextA" (ByVal hWnd As Long, ByVal lpString As String, ByVal cch As Long) As Long
Private Declare Function GetClassName Lib "user32" Alias "GetClassNameA" (ByVal hWnd As Long, ByVal lpClassName As String, ByVal nMaxCount As Long) As Long
Private Declare Function IsWindowVisible Lib "user32" (ByVal hWnd As Long) As Long
Private Declare Function IsWindowEnabled Lib "user32" (ByVal hWnd As Long) As Long
Private Declare Function GetWindow Lib "user32" (ByVal hWnd As Long, ByVal wCmd As Long) As Long
Private Declare Function GetDesktopWindow Lib "user32" () As Long
Private Declare Function GetWindowThreadProcessId Lib "user32" (ByVal hWnd As Long, ByVal lpdwProcessId As Long) As Long
Private Declare Function GetCurrentThreadId Lib "kernel32" () As Long
Private Declare Sub ExitProcess Lib "kernel32" (ByVal uExitCode As Long)
Private Declare Function GetForegroundWindow Lib "user32" () As Long
Private Declare Function GetFocus Lib "user32" () As Long
Private Declare Function GetMenu Lib "user32" (ByVal hWnd As Long) As Long
Private Declare Function GetSubMenu Lib "user32" (ByVal hMenu As Long, ByVal nPos As Long) As Long
Private Declare Function GetMenuItemCount Lib "user32" (ByVal hMenu As Long) As Long
Private Declare Function GetMenuString Lib "user32" Alias "GetMenuStringA" (ByVal hMenu As Long, ByVal wIDItem As Long, ByVal lpString As String, ByVal nMaxCount As Long, ByVal wFlag As Long) As Long
Private Declare Function GetMenuState Lib "user32" (ByVal hMenu As Long, ByVal wID As Long, ByVal wFlags As Long) As Long
Private Declare Function GetMenuItemRect Lib "user32" (ByVal hWnd As Long, ByVal hMenu As Long, ByVal uItem As Long, lprcItem As RECT) As Long

Private Const GW_HWNDNEXT As Long = 2
Private Const GW_CHILD As Long = 5
Private Const MF_BYPOSITION As Long = &H400
Private Const MF_GRAYED As Long = &H1
Private Const MF_CHECKED As Long = &H8
Private Const MF_SEPARATOR As Long = &H800
Private Const MF_HILITE As Long = &H80
Private Const MOUSEEVENTF_MOVE As Long = &H1
Private Const MOUSEEVENTF_LEFTDOWN As Long = &H2
Private Const MOUSEEVENTF_LEFTUP As Long = &H4
Private Const MOUSEEVENTF_RIGHTDOWN As Long = &H8
Private Const MOUSEEVENTF_RIGHTUP As Long = &H10
Private Const KEYEVENTF_KEYUP As Long = &H2
Private Const LVM_GETITEMRECT As Long = &H100E
Private Const LVIR_LABEL As Long = 2

Private Const DEFAULT_PORT As Long = 9898
Private Const SETTLE_MS As Long = 400
Private Const TICK_MS As Long = 20

' ---- state ----

Private mListen As Long
Private mClient As Long
Private mIn As String                    ' read but not yet run
Private mBusy As Boolean
Private mAnswerDue As Boolean
Private mSettleAt As Double
Private mWaitUntil As Double

' The input still to send: one step per tick. "M x y" glides the pointer
' there, "LC"/"RC" click, "DRAG x1 y1 x2 y2 L|R" drags, "KD vk"/"KU vk"
' a key, "P ms" pauses.
Private mSteps() As String
Private mStepHead As Long
Private mStepTail As Long
Private mGlideI As Long                  ' a glide in progress: tick i of n, from where
Private mGlideN As Long
Private mGlideX0 As Long
Private mGlideY0 As Long
Private mSkipClick As Long               ' a menu item picked by keyboard: skip the click queued for it
Private mPauseUntil As Double

' What the last read-out found, and where.
Private mTgName() As String
Private mTgX() As Long
Private mTgY() As Long
Private mTgN As Long


' ---- starting ----

' From Sub Main: listens if the command line says /REMOTE.
Public Sub RemoteStart()
    Dim p As Long, i As Long, wsa As WSADATA, addr As SOCKADDR_IN, nb As Long
    i = InStr(1, Command$, "/REMOTE", vbTextCompare)
    If i = 0 Then Exit Sub
    p = DEFAULT_PORT
    If Mid$(Command$, i + 7, 1) = ":" Then p = Val(Mid$(Command$, i + 8))
    If p <= 0 Or p > 32767 Then p = DEFAULT_PORT
    ReDim mSteps(0 To 2047)
    mListen = INVALID_SOCKET: mClient = INVALID_SOCKET
    If ws_WSAStartup(&H101, wsa) <> 0 Then Exit Sub
    mListen = ws_socket(AF_INET, SOCK_STREAM, 0)
    If mListen = INVALID_SOCKET Then Exit Sub
    addr.sin_family = AF_INET
    addr.sin_port = ws_htons(CInt(p))
    addr.sin_addr = 0                    ' any address
    If ws_bind(mListen, addr, LenB(addr)) <> 0 Then ws_closesocket mListen: mListen = INVALID_SOCKET: Exit Sub
    ws_listen mListen, 1
    nb = 1
    ws_ioctlsocket mListen, FIONBIO, nb
    SetTimer 0, 0, TICK_MS, AddressOf RemoteTick
    frmMain.SetStatus "Remote control: listening on port " & p & "."
End Sub

' ---- the connection ----

Private Sub Say(ByVal t As String)
    Dim s As String, ln As String, rest As String, p As Long
    rest = t
    Do While Right$(rest, 2) = vbCrLf
        rest = Left$(rest, Len(rest) - 2)
    Loop
    rest = rest & vbCrLf
    Do While Len(rest)
        p = InStr(rest, vbCrLf)
        ln = Left$(rest, p - 1)
        rest = Mid$(rest, p + 2)
        If Left$(ln, 1) = "." Then ln = "." & ln
        s = s & ln & vbLf
    Loop
    s = s & "." & vbLf
    SendAll s
End Sub

Private Sub SendAll(ByVal s As String)
    Dim b() As Byte, sent As Long, n As Long
    If mClient = INVALID_SOCKET Then Exit Sub
    b = StrConv(s, vbFromUnicode)
    Do While sent <= UBound(b)
        n = ws_send(mClient, b(sent), UBound(b) - sent + 1, 0)
        If n <= 0 Then Exit Do
        sent = sent + n
    Loop
End Sub

Private Sub ReadSocket()
    Dim b(0 To 1023) As Byte, n As Long, nb As Long, c As Long
    If mClient = INVALID_SOCKET Then
        c = ws_accept(mListen, 0, 0)
        If c = INVALID_SOCKET Then Exit Sub
        mClient = c
        nb = 1
        ws_ioctlsocket mClient, FIONBIO, nb
        mIn = ""
        mAnswerDue = False
        frmMain.SetStatus "Remote control: connected."
    End If
    Do
        n = ws_recv(mClient, b(0), 1024, 0)
        If n = 0 Then
            ' the other end hung up; wait for the next one
            ws_closesocket mClient
            mClient = INVALID_SOCKET
            frmMain.SetStatus "Remote control: disconnected."
            Exit Sub
        End If
        If n < 0 Then Exit Sub           ' nothing more for now
        mIn = mIn & Left$(StrConv(b, vbUnicode), n)
    Loop
End Sub

Private Function NextLine(sLine As String) As Boolean
    Dim p As Long
    p = InStr(mIn, vbLf)
    If p = 0 Then Exit Function
    sLine = Trim$(Replace(Left$(mIn, p - 1), vbCr, ""))
    mIn = Mid$(mIn, p + 1)
    NextLine = True
End Function

' Every TICK_MS, whatever else is going on: inside dialogs, message boxes
' and menus too, since their loops hand timers on.
Public Sub RemoteTick(ByVal hWnd As Long, ByVal uMsg As Long, ByVal idEvent As Long, ByVal dwTime As Long)
    Dim l As String
    If mBusy Then Exit Sub
    mBusy = True
    On Error GoTo Done
    ReadSocket
    If mStepHead <> mStepTail Then
        RunStep
        mSettleAt = Timer + SETTLE_MS / 1000
        GoTo Done
    End If
    If Timer < mWaitUntil Then GoTo Done
    If mAnswerDue Then
        If Timer < mSettleAt Then GoTo Done
        mAnswerDue = False
        Say "ok"
    End If
    If NextLine(l) Then RemoteDo l
Done:
    mBusy = False
End Sub

' ---- input, one step at a time ----

Private Sub AddStep(ByVal s As String)
    mSteps(mStepTail) = s
    mStepTail = (mStepTail + 1) Mod (UBound(mSteps) + 1)
End Sub

Private Sub RunStep()
    Dim s As String, w() As String, cur As POINTAPI, tx As Long, ty As Long
    s = mSteps(mStepHead)
    w = Split(s, " ")
    Select Case w(0)
    Case "M"
        ' a glide, the way a hand moves a mouse: longer for further, quick in
        ' the middle and slowing at the end
        tx = CLng(w(1)): ty = CLng(w(2))
        If mGlideN = 0 Then
            GetCursorPos cur
            mGlideX0 = cur.x: mGlideY0 = cur.y
            mGlideN = Sqr((tx - cur.x) ^ 2 + (ty - cur.y) ^ 2) / 25
            If mGlideN < 10 Then mGlideN = 10
            If mGlideN > 30 Then mGlideN = 30
            mGlideI = 0
        End If
        mGlideI = mGlideI + 1
        Dim f As Double
        f = mGlideI / mGlideN
        f = f * f * (3 - 2 * f)
        SetCursorPos mGlideX0 + (tx - mGlideX0) * f, mGlideY0 + (ty - mGlideY0) * f
        If mGlideI < mGlideN Then Exit Sub
        mGlideN = 0
        SetCursorPos tx, ty
    Case "MT", "MI"
        ' where a menu title or item is, asked for only now: an item's place
        ' is known once its menu is open
        Dim r As RECT, ok As Long
        If w(0) = "MT" Then
            ok = GetMenuItemRect(frmMain.hWnd, GetMenu(frmMain.hWnd), CLng(w(1)), r)
        Else
            ok = GetMenuItemRect(0, CLng(w(1)), CLng(w(2)), r)
        End If
        If ok <> 0 Then
            mSteps(mStepHead) = "M " & ((r.Left + r.Right) \ 2) & " " & ((r.Top + r.Bottom) \ 2)
            If w(0) = "MI" Then mSteps(mStepHead) = "M " & (r.Left + 40) & " " & ((r.Top + r.Bottom) \ 2)
            Exit Sub
        End If
        ' Windows couldn't say: the keyboard, then, and no click
        If w(0) = "MT" Then
            keybd_event 18, 0, 0, 0
            keybd_event CByte(VkKeyScan(Asc(LCase$(Mid$(MenuText(GetMenu(frmMain.hWnd), CLng(w(1))), InStr(MenuText(GetMenu(frmMain.hWnd), CLng(w(1))), "&") + 1, 1)))) And &HFF), 0, 0, 0
            keybd_event CByte(VkKeyScan(Asc(LCase$(Mid$(MenuText(GetMenu(frmMain.hWnd), CLng(w(1))), InStr(MenuText(GetMenu(frmMain.hWnd), CLng(w(1))), "&") + 1, 1)))) And &HFF), 0, KEYEVENTF_KEYUP, 0
            keybd_event 18, 0, KEYEVENTF_KEYUP, 0
        Else
            Dim k As Long
            For k = 0 To CLng(w(2)) - 1
                If (GetMenuState(CLng(w(1)), k, MF_BYPOSITION) And MF_SEPARATOR) = 0 Then keybd_event 40, 0, 0, 0: keybd_event 40, 0, KEYEVENTF_KEYUP, 0
            Next k
            keybd_event 13, 0, 0, 0: keybd_event 13, 0, KEYEVENTF_KEYUP, 0
        End If
        mSkipClick = 1
    Case "DRAG"
        ' all in one go, Windows plays it back: a drag on a title bar starts
        ' a loop that hands on no timers until the button comes up
        Dim i As Long, x1 As Long, y1 As Long, x2 As Long, y2 As Long, bRt As Boolean
        x1 = CLng(w(1)): y1 = CLng(w(2)): x2 = CLng(w(3)): y2 = CLng(w(4)): bRt = (w(5) = "R")
        mouse_event IIf(bRt, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_LEFTDOWN), 0, 0, 0, 0
        For i = 1 To 20
            SetCursorPos x1 + (x2 - x1) * i \ 20, y1 + (y2 - y1) * i \ 20
            mouse_event MOUSEEVENTF_MOVE, 0, 0, 0, 0
        Next i
        mouse_event IIf(bRt, MOUSEEVENTF_RIGHTUP, MOUSEEVENTF_LEFTUP), 0, 0, 0, 0
    Case "LC"
        ' a click, press and release together: pressing a title-bar button
        ' starts a loop in Windows that hands on no timers until the release
        If mSkipClick > 0 Then
            mSkipClick = 0
        Else
            mouse_event MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0
            mouse_event MOUSEEVENTF_LEFTUP, 0, 0, 0, 0
        End If
    Case "RC"
        mouse_event MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0
        mouse_event MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0
    Case "KD": keybd_event CByte(w(1)), CByte(MapVirtualKey(CLng(w(1)), 0)), 0, 0
    Case "KU": keybd_event CByte(w(1)), CByte(MapVirtualKey(CLng(w(1)), 0)), KEYEVENTF_KEYUP, 0
    Case "P"
        If mPauseUntil = 0 Then mPauseUntil = Timer + CLng(w(1)) / 1000
        If Timer < mPauseUntil Then Exit Sub
        mPauseUntil = 0
    End Select
    mStepHead = (mStepHead + 1) Mod (UBound(mSteps) + 1)
End Sub

Private Sub QueueClick(ByVal x As Long, ByVal y As Long, ByVal bRight As Boolean, ByVal bDouble As Boolean)
    AddStep "M " & x & " " & y
    AddStep "P 90"
    AddStep IIf(bRight, "RC", "LC")
    If bDouble Then AddStep "LC"
End Sub

Private Sub QueueKey(ByVal vk As Long)
    AddStep "KD " & vk
    AddStep "KU " & vk
End Sub

' "ctrl+s", "enter", "shift+tab", "f5", "e"
Private Function QueueCombo(ByVal combo As String) As Boolean
    Dim parts() As String, i As Long, vk As Long, mods As String
    parts = Split(LCase$(combo), "+")
    For i = 0 To UBound(parts)
        Select Case parts(i)
        Case "ctrl", "control": mods = mods & " 17"
        Case "shift": mods = mods & " 16"
        Case "alt": mods = mods & " 18"
        Case Else
            vk = KeyCode(parts(i))
            If vk = 0 Then Exit Function
        End Select
    Next i
    If vk = 0 Then Exit Function
    Dim m() As String
    m = Split(Trim$(mods), " ")
    For i = 0 To UBound(m)
        If Len(m(i)) Then AddStep "KD " & m(i)
    Next i
    QueueKey vk
    For i = UBound(m) To 0 Step -1
        If Len(m(i)) Then AddStep "KU " & m(i)
    Next i
    QueueCombo = True
End Function

Private Function KeyCode(ByVal nm As String) As Long
    Select Case nm
    Case "enter", "return": KeyCode = 13
    Case "esc", "escape": KeyCode = 27
    Case "tab": KeyCode = 9
    Case "back", "backspace": KeyCode = 8
    Case "space": KeyCode = 32
    Case "del", "delete": KeyCode = 46
    Case "up": KeyCode = 38
    Case "down": KeyCode = 40
    Case "left": KeyCode = 37
    Case "right": KeyCode = 39
    Case "home": KeyCode = 36
    Case "end": KeyCode = 35
    Case "pgup": KeyCode = 33
    Case "pgdn": KeyCode = 34
    Case Else
        If Len(nm) >= 2 And Left$(nm, 1) = "f" And Val(Mid$(nm, 2)) >= 1 And Val(Mid$(nm, 2)) <= 12 Then
            KeyCode = 111 + Val(Mid$(nm, 2))
        ElseIf Len(nm) = 1 Then
            KeyCode = VkKeyScan(Asc(nm)) And &HFF
        End If
    End Select
End Function

Private Sub QueueType(ByVal t As String)
    Dim i As Long, k As Integer, vk As Long, sh As Boolean
    For i = 1 To Len(t)
        k = VkKeyScan(Asc(Mid$(t, i, 1)))
        If k <> -1 Then
            vk = k And &HFF
            sh = (k And &H100) <> 0
            If sh Then AddStep "KD 16"
            QueueKey vk
            If sh Then AddStep "KU 16"
            AddStep "P 40"
        End If
    Next i
End Sub

' ---- the read-out ----

Private Sub AddTarget(ByVal nm As String, ByVal x As Long, ByVal y As Long)
    nm = NormName(nm)
    If Len(nm) = 0 Then Exit Sub
    If mTgN > UBound(mTgName) Then
        ReDim Preserve mTgName(0 To mTgN * 2)
        ReDim Preserve mTgX(0 To mTgN * 2)
        ReDim Preserve mTgY(0 To mTgN * 2)
    End If
    mTgName(mTgN) = nm: mTgX(mTgN) = x: mTgY(mTgN) = y
    mTgN = mTgN + 1
End Sub

' Names compare without "&", "...", a trailing ":", quotes or case.
Private Function NormName(ByVal s As String) As String
    Dim t As String
    t = LCase$(Trim$(Replace(s, "&", "")))
    If Left$(t, 1) = """" And Right$(t, 1) = """" And Len(t) >= 2 Then t = Trim$(Mid$(t, 2, Len(t) - 2))
    If Left$(t, 1) = "[" And Right$(t, 1) = "]" And Len(t) >= 2 Then t = Trim$(Mid$(t, 2, Len(t) - 2))
    If Right$(t, 3) = "..." Then t = RTrim$(Left$(t, Len(t) - 3))
    If Right$(t, 1) = ":" Then t = RTrim$(Left$(t, Len(t) - 1))
    NormName = t
End Function

Private Function FindTarget(ByVal nm As String, x As Long, y As Long) As Boolean
    Dim i As Long, want As String
    want = NormName(nm)
    For i = 0 To mTgN - 1
        If mTgName(i) = want Then x = mTgX(i): y = mTgY(i): FindTarget = True: Exit Function
    Next i
    For i = 0 To mTgN - 1
        If Left$(mTgName(i), Len(want)) = want Then x = mTgX(i): y = mTgY(i): FindTarget = True: Exit Function
    Next i
End Function

Private Function Clean(ByVal s As String) As String
    Dim t As String
    t = Replace(s, "&&", Chr$(1))
    t = Replace(t, "&", "")
    t = Replace(t, Chr$(1), "&")
    t = Replace(t, vbCrLf, " / ")
    t = Replace(t, vbLf, " / ")
    Do While InStr(t, " /  / ") > 0
        t = Replace(t, " /  / ", " / ")
    Loop
    Clean = Trim$(t)
End Function

Private Function WinText(ByVal h As Long) As String
    Dim s As String, n As Long
    s = String$(512, 0)
    n = GetWindowText(h, s, 512)
    WinText = Left$(s, n)
End Function

Private Function WinClass(ByVal h As Long) As String
    Dim s As String, n As Long
    s = String$(128, 0)
    n = GetClassName(h, s, 128)
    WinClass = Left$(s, n)
End Function

Private Sub CentreOf(ByVal h As Long, x As Long, y As Long)
    Dim r As RECT
    GetWindowRect h, r
    x = (r.Left + r.Right) \ 2: y = (r.Top + r.Bottom) \ 2
End Sub

' "Turbo. Makes everything faster." and "New Part (Ctrl+N)": the name is
' the part before the first "(" or ". ".
Private Function ToolName(ByVal tip As String) As String
    Dim a As Long, b As Long
    a = InStr(tip, " ("): b = InStr(tip, ". ")
    If a = 0 Or (b > 0 And b < a) Then a = b
    If a = 0 Then ToolName = tip Else ToolName = Left$(tip, a - 1)
End Function

' A message box, or any other window Windows draws itself.
Private Function DescribeSystemDialog(ByVal h As Long, ByVal bTop As Boolean) As String
    Dim r As String, c As Long, cls As String, t As String, x As Long, y As Long
    r = "Message box """ & WinText(h) & """" & IIf(bTop, ", on top: it takes every click and key until it closes", "") & vbCrLf
    c = GetWindow(h, GW_CHILD)
    Do While c <> 0
        If IsWindowVisible(c) Then
            cls = WinClass(c): t = WinText(c)
            If cls = "Button" And Len(t) Then
                r = r & "  button [" & Clean(t) & "]" & vbCrLf
                CentreOf c, x, y
                AddTarget t, x, y
            ElseIf Len(Trim$(t)) And Not (Left$(t, 1) = "#" And IsNumeric(Mid$(t, 2))) Then
                ' (an icon's text is its resource number, "#0": not worth reading)
                r = r & "  " & Clean(t) & vbCrLf
            End If
        End If
        c = GetWindow(c, GW_HWNDNEXT)
    Loop
    DescribeSystemDialog = r
End Function

' What a screen reader says about the pictures, form by form.
Private Function PictureReadOut(f As Form) As String
    Select Case f.Name
    Case "frmFatal"
        PictureReadOut = "The whole screen is blue: A fatal exception 0E has occurred at 0028:SOLIDCRAFT+00000D1V0. " & _
            "Something somewhere was divided by zero. The current part will not be terminated. It is fine. " & _
            "Press any key to return to SolidCraft 98. Then type a number that isn't zero."
    Case "frmSetup"
        PictureReadOut = frmSetup.ReadOut()
    Case "frmCredits"
        PictureReadOut = "A demo-scene credits screen: stars, copper bars and scrolling text. A click or a key closes it."
    Case "frmAbout"
        PictureReadOut = "A picture: the SolidCraft 98 logo, a block with a hole in it."
    Case "frmFloppy"
        PictureReadOut = "A floppy disk picture, and a progress bar."
    Case "frmCal"
        PictureReadOut = "A picture of Cal, the caliper assistant."
    Case "frmSplash"
        PictureReadOut = "The SolidCraft 98 splash screen."
    End Select
End Function

' A form of ours that isn't the main window: its controls, top to bottom.
Private Function DescribeForm(f As Form, ByVal bTop As Boolean, Optional ByVal sHeader As String) As String
    Dim r As String, ctl As Control, n As Long, i As Long, j As Long
    Dim ord() As Long, key() As Long, txt() As String
    Dim tn As String, x As Long, y As Long, cap As String
    If Len(sHeader) Then
        r = sHeader & vbCrLf
    Else
        r = "Window """ & f.Caption & """" & IIf(bTop, ", on top: it takes every click and key until it closes", "") & vbCrLf
    End If
    If Len(PictureReadOut(f)) Then r = r & "  " & PictureReadOut(f) & vbCrLf
    ReDim ord(0 To f.Controls.Count): ReDim key(0 To f.Controls.Count): ReDim txt(0 To f.Controls.Count)
    On Error Resume Next
    For Each ctl In f.Controls
        tn = TypeName(ctl)
        Err.Clear
        If ctl.Visible = False Then GoTo NextCtl
        Select Case tn
        Case "Label"
            cap = ctl.Caption
            If Len(Trim$(cap)) = 0 Then GoTo NextCtl
            If IsFieldLabel(f, ctl) Then GoTo NextCtl
            txt(n) = "  " & Clean(cap)
        Case "TextBox", "ComboBox"
            Dim lb As String, foc As String
            lb = FieldLabel(f, ctl)
            If Len(lb) = 0 Then lb = "field"
            foc = ""
            If ctl.hWnd = GetFocus() Then
                foc = " (has the focus"
                If ctl.SelLength = Len(ctl.Text) And Len(ctl.Text) > 0 Then foc = foc & ", all selected: typing replaces it"
                foc = foc & ")"
            End If
            txt(n) = "  field """ & lb & """: [" & ctl.Text & "]" & foc
            CentreOf ctl.hWnd, x, y
            AddTarget lb, x, y
        Case "CommandButton", "CheckBox", "OptionButton"
            cap = Clean(ctl.Caption)
            txt(n) = "  " & IIf(tn = "CommandButton", "button", LCase$(tn)) & " [" & cap & "]"
            If tn = "CommandButton" Then
                If ctl.Default Then txt(n) = txt(n) & " (default: Enter presses it)"
                If ctl.Cancel Then txt(n) = txt(n) & " (Esc presses it)"
            Else
                If ctl.Value Then txt(n) = txt(n) & " (ticked)"
            End If
            If Not ctl.Enabled Then txt(n) = txt(n) & " (greyed out)"
            If ctl.hWnd = GetFocus() Then txt(n) = txt(n) & " (has the focus)"
            CentreOf ctl.hWnd, x, y
            AddTarget cap, x, y
        Case Else
            GoTo NextCtl
        End Select
        If Len(txt(n)) Then
            key(n) = CLng(f.ScaleY(ctl.Top, f.ScaleMode, vbPixels)) * 10000 + CLng(f.ScaleX(ctl.Left, f.ScaleMode, vbPixels))
            ord(n) = n
            n = n + 1
        End If
NextCtl:
    Next ctl
    On Error GoTo 0
    ' top to bottom, then left to right
    For i = 1 To n - 1
        j = i
        Do While j > 0
            If key(ord(j - 1)) <= key(ord(j)) Then Exit Do
            Dim t As Long
            t = ord(j): ord(j) = ord(j - 1): ord(j - 1) = t
            j = j - 1
        Loop
    Next i
    For i = 0 To n - 1
        r = r & txt(ord(i)) & vbCrLf
    Next i
    If f.BorderStyle <> 0 And f.ControlBox Then
        Dim wr As RECT
        GetWindowRect f.hWnd, wr
        r = r & "  title bar close box [x]" & vbCrLf
        AddTarget "x", wr.Right - 14, wr.Top + 12
        AddTarget "close box", wr.Right - 14, wr.Top + 12
        AddTarget "close", wr.Right - 14, wr.Top + 12
    End If
    DescribeForm = r
End Function

' A label on the same line as a text box, to its left, names it.
Private Function FieldLabel(f As Form, box As Control) As String
    Dim ctl As Control, best As Single
    best = -1
    On Error Resume Next
    For Each ctl In f.Controls
        If TypeName(ctl) = "Label" Then
            If ctl.Visible And ctl.Left < box.Left And Abs((ctl.Top + ctl.Height / 2) - (box.Top + box.Height / 2)) < box.Height Then
                If ctl.Left > best Then best = ctl.Left: FieldLabel = Clean(ctl.Caption)
            End If
        End If
    Next ctl
    If Right$(FieldLabel, 1) = ":" Then FieldLabel = Left$(FieldLabel, Len(FieldLabel) - 1)
End Function

Private Function IsFieldLabel(f As Form, lbl As Control) As Boolean
    Dim ctl As Control
    On Error Resume Next
    For Each ctl In f.Controls
        Select Case TypeName(ctl)
        Case "TextBox", "ComboBox"
            If ctl.Visible And lbl.Left < ctl.Left And Abs((lbl.Top + lbl.Height / 2) - (ctl.Top + ctl.Height / 2)) < ctl.Height Then
                If FieldLabel(f, ctl) = Clean(lbl.Caption) Or FieldLabel(f, ctl) & ":" = Clean(lbl.Caption) Then IsFieldLabel = True: Exit Function
            End If
        End Select
    Next ctl
End Function

' The menu bar: its titles, and the menu we opened, if it's open.
Private Function DescribeMenus(ByVal bOpen As Boolean) As String
    Dim hBar As Long, i As Long, n As Long, r As String, s As String
    hBar = GetMenu(frmMain.hWnd)
    r = "Menu bar:"
    n = GetMenuItemCount(hBar)
    For i = 0 To n - 1
        s = MenuText(hBar, i)
        If Len(s) Then r = r & IIf(Right$(r, 1) = ":", " ", ", ") & Clean(s)
    Next i
    r = r & vbCrLf
    Dim hot As Long
    hot = HotTitle()
    If hot >= 0 And Not bOpen Then
        r = r & "The menu bar is active, with " & Clean(MenuText(hBar, hot)) & " highlighted: a letter key opens a menu, Esc leaves the menu bar." & vbCrLf
    End If
    If bOpen And hot >= 0 Then
        Dim hSub As Long, st As Long
        hSub = GetSubMenu(hBar, hot)
        r = r & "The " & Clean(MenuText(hBar, hot)) & " menu is open:" & vbCrLf
        For i = 0 To GetMenuItemCount(hSub) - 1
            st = GetMenuState(hSub, i, MF_BYPOSITION)
            If (st And MF_SEPARATOR) = 0 Then
                s = MenuText(hSub, i)
                r = r & "  " & IIf(st And MF_CHECKED, "[x] ", "") & Clean(Replace(s, vbTab, "   (")) & IIf(InStr(s, vbTab) > 0, ")", "") & IIf(st And MF_GRAYED, " (greyed out)", "") & vbCrLf
            End If
        Next i
    End If
    DescribeMenus = r
End Function

' The menu bar title Windows has highlighted (its menu is open, or the
' menu bar is active from the keyboard); -1 if none.
Private Function HotTitle() As Long
    Dim hBar As Long, i As Long
    hBar = GetMenu(frmMain.hWnd)
    HotTitle = -1
    For i = 0 To GetMenuItemCount(hBar) - 1
        If GetMenuState(hBar, i, MF_BYPOSITION) And MF_HILITE Then HotTitle = i: Exit Function
    Next i
End Function

Private Function MenuText(ByVal hMenu As Long, ByVal i As Long) As String
    Dim s As String, n As Long
    s = String$(256, 0)
    n = GetMenuString(hMenu, i, s, 256, MF_BYPOSITION)
    MenuText = Left$(s, n)
End Function

Private Function DescribePart(ByVal p As Object, ByVal bActive As Boolean) As String
    Dim r As String, i As Long, nd As Object, depth As Long, par As Object
    Dim it As Object, row As String, rc As RECT, pt As POINTAPI, x As Long, y As Long
    r = "Part window """ & p.Caption & """" & IIf(bActive, " (the active one)", "") & IIf(p.WindowState = vbMinimized, ", minimised", "") & vbCrLf
    If Not bActive Or p.WindowState = vbMinimized Then DescribePart = r: Exit Function
    On Error Resume Next
    r = r & "  Feature tree:" & vbCrLf
    For i = 1 To p.tvwTree.Nodes.Count
        Set nd = p.tvwTree.Nodes(i)
        ' only what can be seen: rows whose parents are all expanded
        depth = 0
        Dim shown As Boolean
        shown = True
        Set par = nd.Parent
        Do While Not par Is Nothing
            If Not par.Expanded Then shown = False
            depth = depth + 1
            Set par = par.Parent
        Loop
        If shown Then r = r & "    " & String$(depth * 2, " ") & nd.Text & vbCrLf
    Next i
    If p.lvwTimeline.ListItems.Count = 0 Then
        r = r & "  Timeline: empty. Nothing has been made yet." & vbCrLf
    Else
        r = r & "  Timeline (# | Feature | Type | Parameters | Status):" & vbCrLf
        For i = 1 To p.lvwTimeline.ListItems.Count
            Set it = p.lvwTimeline.ListItems(i)
            row = "    " & it.Text & " | " & it.SubItems(1) & " | " & it.SubItems(2) & " | " & it.SubItems(3) & " | " & it.SubItems(4)
            If it.Selected Then row = row & "   <- selected"
            r = r & row & vbCrLf
            rc.Left = LVIR_LABEL
            If SendMessage(p.lvwTimeline.hWnd, LVM_GETITEMRECT, i - 1, rc) <> 0 Then
                pt.x = rc.Left + 60: pt.y = (rc.Top + rc.Bottom) \ 2
                If pt.y > 0 And pt.y < p.lvwTimeline.Height Then
                    ClientToScreen p.lvwTimeline.hWnd, pt
                    AddTarget it.SubItems(1), pt.x, pt.y
                End If
            End If
        Next i
    End If
    Dim vr As RECT
    GetWindowRect p.ViewPicture.hWnd, vr
    r = r & "  View (x " & vr.Left & " to " & vr.Right & ", y " & vr.Top & " to " & vr.Bottom & "; drag in it to orbit, right-drag to pan): " & _
        IIf(ViewShaded, "shaded", "wireframe") & vbCrLf
    AddTarget "view", (vr.Left + vr.Right) \ 2, (vr.Top + vr.Bottom) \ 2
    DescribePart = r
End Function

Private Function DescribeMain() As String
    Dim r As String, i As Long, k As String, tip As String, l As Long, w As Long, chk As Boolean
    Dim tr As RECT, f As Form, act As Form, nm As String
    r = DescribeMenus(MenuIsOpen())
    GetWindowRect frmMain.picToolbar.hWnd, tr
    r = r & "Toolbar buttons:"
    For i = 1 To ToolbarCount()
        If ToolbarButton(i, k, tip, l, w, chk) Then
            nm = ToolName(tip)
            r = r & IIf(Right$(r, 1) = ":", " ", ", ") & nm & IIf(chk, " (pressed in)", "")
            AddTarget nm, tr.Left + l + w \ 2, tr.Top + ToolbarButtonTop() + 11
        End If
    Next i
    r = r & vbCrLf
    On Error Resume Next
    Set act = frmMain.ActiveForm
    On Error GoTo 0
    Dim nParts As Long
    For Each f In Forms
        If TypeOf f Is frmPart Then
            nParts = nParts + 1
            r = r & DescribePart(f, f Is act)
        End If
    Next f
    If nParts = 0 Then r = r & "No part windows are open." & vbCrLf
    r = r & "Status bar: " & StatusText("msg") & IIf(Len(StatusText("fps")), "   (" & StatusText("fps") & ")", "") & "   Clock: " & StatusText("clock") & vbCrLf
    DescribeMain = r
End Function

Private Function MenuIsOpen() As Boolean
    Dim h As Long, pid As Long
    h = GetWindow(GetDesktopWindow(), GW_CHILD)
    Do While h <> 0
        If IsWindowVisible(h) Then
            If WinClass(h) = "#32768" Then MenuIsOpen = True: Exit Function
        End If
        h = GetWindow(h, GW_HWNDNEXT)
    Loop
End Function

' Everything, front to back.
Public Function DescribeScreen() As String
    Dim r As String, h As Long, f As Form, tid As Long, first As Boolean, fg As Long
    ReDim mTgName(0 To 63): ReDim mTgX(0 To 63): ReDim mTgY(0 To 63)
    mTgN = 0
    r = App.Title & ", " & Screen.Width \ Screen.TwipsPerPixelX & " x " & Screen.Height \ Screen.TwipsPerPixelY & _
        ". Turbo " & IIf(Turbo, "ON (the LED says 33 MHz)", "off (the LED says 66 MHz)") & "." & vbCrLf
    tid = GetCurrentThreadId()
    fg = GetForegroundWindow()
    first = True
    h = GetWindow(GetDesktopWindow(), GW_CHILD)
    Do While h <> 0
        If IsWindowVisible(h) Then
            If GetWindowThreadProcessId(h, 0) = tid Then
                Set f = FormOf(h)
                If Not f Is Nothing Then
                    If f.Name = "frmCal" Then
                        r = r & DescribeForm(f, False, "Cal, the caliper assistant, is in the corner of the main window:")
                    ElseIf f.Name = "frmCalPin" Then
                        r = r & DescribeForm(f, False, "A note is pinned in the corner of the main window:")
                    ElseIf Not f Is frmMain Then
                        r = r & DescribeForm(f, first)
                        first = False
                    End If
                ElseIf WinClass(h) = "#32770" Then
                    r = r & DescribeSystemDialog(h, first)
                    first = False
                End If
            End If
        End If
        h = GetWindow(h, GW_HWNDNEXT)
    Loop
    If Not first Then r = r & "Underneath: the main window." & vbCrLf
    r = r & DescribeMain()
    DescribeScreen = r
End Function

Private Function FormOf(ByVal h As Long) As Form
    Dim f As Form
    For Each f In Forms
        If f.hWnd = h Then Set FormOf = f: Exit Function
    Next f
End Function

' ---- the commands ----

Private Function HelpText() As String
    HelpText = "Commands: look | click <name> or <x> <y> | dblclick <name> or <x> <y> | rclick <name> or <x> <y>" & vbCrLf & _
        "drag <x1> <y1> <x2> <y2> [right] | menu <title> > <item> | key <keys> (e, ctrl+s, enter, esc, tab, f5)" & vbCrLf & _
        "type <text> | wait <ms> | help | quit"
End Function

' A menu title, or (with a menu open) one of its items: picked with the
' keyboard, Alt and the underlined letter, the way a touch-typist did.
Private Function MenuByName(ByVal nm As String) As Boolean
    Dim hBar As Long, i As Long, s As String, want As String
    want = NormName(nm)
    hBar = GetMenu(frmMain.hWnd)
    If MenuIsOpen() And HotTitle() >= 0 Then
        Dim hSub As Long
        hSub = GetSubMenu(hBar, HotTitle())
        For i = 0 To GetMenuItemCount(hSub) - 1
            s = MenuText(hSub, i)
            If InStr(s, vbTab) Then s = Left$(s, InStr(s, vbTab) - 1)
            If Len(s) Then
                If Left$(NormName(s), Len(want)) = want Then
                    PickItem hSub, i
                                    MenuByName = True
                    Exit Function
                End If
            End If
        Next i
    End If
    For i = 0 To GetMenuItemCount(hBar) - 1
        s = MenuText(hBar, i)
        If Len(s) Then
            If NormName(s) = want Then
                If MenuIsOpen() Or HotTitle() >= 0 Then QueueKey 27: QueueKey 27
                OpenMenu hBar, i
                MenuByName = True
                Exit Function
            End If
        End If
    Next i
End Function

' With the mouse, the way most people did: to the title, click.
Private Sub OpenMenu(ByVal hBar As Long, ByVal i As Long)
    AddStep "MT " & i
    AddStep "P 90"
    AddStep "LC"
    AddStep "P 250"
End Sub

' Down the open menu to the item, click.
Private Sub PickItem(ByVal hSub As Long, ByVal i As Long)
    AddStep "MI " & hSub & " " & i
    AddStep "P 90"
    AddStep "LC"
End Sub

Private Sub RemoteDo(ByVal l As String)
    Dim cmd As String, rest As String, p As Long, x As Long, y As Long
    p = InStr(l, " ")
    If p Then cmd = LCase$(Left$(l, p - 1)): rest = Trim$(Mid$(l, p + 1)) Else cmd = LCase$(l)
    Select Case cmd
    Case ""
        Exit Sub
    Case "look"
        Say DescribeScreen()
        Exit Sub
    Case "help"
        Say HelpText()
        Exit Sub
    Case "click", "dblclick", "rclick"
        If Len(rest) = 0 Then Say "error: " & cmd & " what?": Exit Sub
        If Not XY(rest, x, y) Then
            DescribeScreen               ' fills in the targets
            If cmd = "click" Then
                If MenuByName(rest) Then GoTo Queued
            End If
            If Not FindTarget(rest, x, y) Then
                Say "error: there's nothing called """ & rest & """ on the screen. ""look"" lists what's there."
                Exit Sub
            End If
        End If
        QueueClick x, y, cmd = "rclick", cmd = "dblclick"
    Case "drag"
        Dim v() As String
        v = Split(rest, " ")
        If UBound(v) < 3 Then Say "error: drag <x1> <y1> <x2> <y2>": Exit Sub
        Dim bR As Boolean, k As Long
        If UBound(v) >= 4 Then bR = (LCase$(v(4)) = "right")
        AddStep "M " & v(0) & " " & v(1)
        AddStep "P 90"
        AddStep "DRAG " & CLng(v(0)) & " " & CLng(v(1)) & " " & CLng(v(2)) & " " & CLng(v(3)) & " " & IIf(bR, "R", "L")
    Case "menu"
        p = InStr(rest, ">")
        If p = 0 Then Say "error: say ""menu <title> > <item>"", e.g. ""menu File > Open..."".": Exit Sub
        If Not MenuPath(Trim$(Left$(rest, p - 1)), Trim$(Mid$(rest, p + 1))) Then Exit Sub
    Case "key"
        If Len(rest) = 0 Then Say "error: key what? e.g. ""key enter"".": Exit Sub
        Dim w() As String, i As Long
        w = Split(rest, " ")
        For i = 0 To UBound(w)
            If Len(w(i)) Then
                If Not QueueCombo(w(i)) Then Say "error: no key called """ & w(i) & """.": Exit Sub
            End If
        Next i
    Case "type"
        QueueType rest
    Case "wait"
        mWaitUntil = Timer + Val(rest) / 1000
    Case "quit"
        Say "bye"
        ExitProcess 0                    ' at once: no questions, nothing saved
    Case Else
        Say "error: """ & cmd & """ isn't a command. " & HelpText()
        Exit Sub
    End Select
Queued:
    mAnswerDue = True
    mSettleAt = Timer + SETTLE_MS / 1000
End Sub

Private Function MenuPath(ByVal sTitle As String, ByVal sItem As String) As Boolean
    Dim hBar As Long, i As Long, k As Long, s As String, hSub As Long
    If Not ForegroundIsMain() Then Say "error: a dialog or message box is open, and it has to close before the menus work.": Exit Function
    hBar = GetMenu(frmMain.hWnd)
    For i = 0 To GetMenuItemCount(hBar) - 1
        s = MenuText(hBar, i)
        If Len(s) Then
            If NormName(s) = NormName(sTitle) Then
                hSub = GetSubMenu(hBar, i)
                For k = 0 To GetMenuItemCount(hSub) - 1
                    s = MenuText(hSub, k)
                    If InStr(s, vbTab) Then s = Left$(s, InStr(s, vbTab) - 1)
                    If Len(s) Then
                        If Left$(NormName(s), Len(NormName(sItem))) = NormName(sItem) Then
                            If MenuIsOpen() Or HotTitle() >= 0 Then QueueKey 27: QueueKey 27
                            OpenMenu hBar, i
                            PickItem hSub, k
                                                    MenuPath = True
                            Exit Function
                        End If
                    End If
                Next k
                Say "error: the " & Clean(MenuText(hBar, i)) & " menu has no """ & sItem & """."
                Exit Function
            End If
        End If
    Next i
    Say "error: there's no menu called """ & sTitle & """."
End Function

Private Function ForegroundIsMain() As Boolean
    Dim h As Long, tid As Long, f As Form
    tid = GetCurrentThreadId()
    h = GetWindow(GetDesktopWindow(), GW_CHILD)
    Do While h <> 0
        If IsWindowVisible(h) And GetWindowThreadProcessId(h, 0) = tid Then
            Set f = FormOf(h)
            If f Is Nothing Then
                If WinClass(h) = "#32770" Then Exit Function
            ElseIf f Is frmMain Then
                ForegroundIsMain = True
                Exit Function
            ElseIf f.Name <> "frmCal" And f.Name <> "frmCalPin" Then
                Exit Function
            End If
        End If
        h = GetWindow(h, GW_HWNDNEXT)
    Loop
End Function

Private Function XY(ByVal s As String, x As Long, y As Long) As Boolean
    Dim v() As String
    v = Split(Trim$(s), " ")
    If UBound(v) <> 1 Then Exit Function
    If Not IsNumeric(v(0)) Or Not IsNumeric(v(1)) Then Exit Function
    x = CLng(v(0)): y = CLng(v(1))
    XY = True
End Function
