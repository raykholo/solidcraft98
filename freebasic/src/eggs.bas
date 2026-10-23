' eggs.bas - Turbo's authentic 1999 behaviour, and the other things in here.
' Every one of them is only drawn on screen: nothing touches system files,
' the clock or a disk drive, and no design is ever lost.

Const FLOPPY_BYTES = 1457664        ' a formatted 3 1/2" HD floppy

' ---- the clock, read and never set; /Y2KTEST pretends it's 31 Dec 1999 ----

Dim Shared ClockOffset As Double
Dim Shared SawNewYearsEve As Boolean

Sub InitClock()
    Dim i As Long
    For i = 1 To 9
        If UCase(Command(i)) = "/Y2KTEST" Or LCase(Command(i)) = "--y2ktest" Then
            ClockOffset = DateSerial(1999, 12, 31) + TimeSerial(23, 59, 0) - Now
        End If
    Next
End Sub

Function ClockNow() As Double
    Return Now + ClockOffset
End Function

' ---- the floppy: "copying" a part to a stack of 1.44 MB disks ----

Type TFloppy
    nm As String
    total As Double
    done As Double
    disks As Long
    disk As Long
    finished As Boolean
    lastTick As Double
End Type
Dim Shared Fl As TFloppy

Sub FloppyDraw(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    Dim As Long ox = ClientX(*d), oy = ClientY(*d), x
    ' a 3 1/2" disk: blue body, metal shutter, white label
    Fill ox + 16 + 4, oy + 14 + 2, 41, 44, &hFF002080
    Fill ox + 16 + 14, oy + 14 + 2, 23, 15, C_FACE
    Fill ox + 16 + 28, oy + 14 + 4, 5, 11, &hFF404040
    Fill ox + 16 + 9, oy + 14 + 24, 32, 22, C_HILITE
    HLine ox + 16 + 12, oy + 14 + 29, 25, C_FACE: HLine ox + 16 + 12, oy + 14 + 34, 25, C_FACE: HLine ox + 16 + 12, oy + 14 + 39, 19, C_FACE
    TextAt ox + 80, oy + 16, "Copying " & Fl.nm & " to A:\", C_TEXT
    TextAt ox + 80, oy + 42, "Disk " & Fl.disk & " of " & Fl.disks & "   (" & Format(Fl.done / 1024, "#,##0") & " KB of " & Format(Fl.total / 1024, "#,##0") & " KB)", C_TEXT
    ' the bar: chunky blocks, like the progress bars of the time
    Dim As Long bx = ox + 16, by = oy + 72, bw = d->w - 40
    Bevel bx, by, bw, 20, BEV_THIN_DOWN
    Fill bx + 1, by + 1, bw - 2, 18, C_WINDOW
    Dim As Double f = (Fl.done - (Fl.disk - 1) * CDbl(FLOPPY_BYTES)) / FLOPPY_BYTES
    If f > 1 Then f = 1
    For x = 2 To (bw - 4) * f Step 9
        Fill bx + x, by + 3, 7, 14, &hFF000080
    Next
End Sub

Function FloppyReadOut(ByVal dp As Any Ptr) As String
    Return "A floppy disk picture. Copying " & Fl.nm & " to A:\  Disk " & Fl.disk & " of " & Fl.disks & _
        ", " & Format(Fl.done / 1024, "#,##0") & " KB of " & Format(Fl.total / 1024, "#,##0") & " KB."
End Function

Sub FloppyTick(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    If Timer - Fl.lastTick < 0.05 Then Exit Sub
    Fl.lastTick = Timer
    Fl.done += 23000 + Rnd * 9000          ' about 500 KB a second, which was fast
    Dim As Double diskEnd = CDbl(Fl.disk) * FLOPPY_BYTES
    If Fl.done >= Fl.total Then
        Fl.done = Fl.total: Fl.finished = True: d->done = True
    ElseIf Fl.done >= diskEnd Then
        Fl.done = diskEnd
        RenderFrame
        If MsgBox("Please insert disk " & (Fl.disk + 1) & " of " & Fl.disks & " into drive A:" & Chr(10) & Chr(10) & _
            "Label it """ & Fl.nm & " - Disk " & (Fl.disk + 1) & """ so you can find it later.", MB_OKCANCEL Or MB_INFO, "Insert Disk") <> IDOK Then
            d->done = True
            Exit Sub
        End If
        Fl.disk += 1
        Fl.lastTick = Timer
    End If
End Sub

' Shows the copy of sName, nBytes long. True if it got to the last disk.
Function RunFloppy(ByRef sName As String, ByVal nBytes As Double) As Boolean
    Dim d As TDlg
    Dim blank As TFloppy
    Fl = blank
    Fl.nm = sName: Fl.total = nBytes: Fl.disks = -Int(-nBytes / FLOPPY_BYTES): Fl.disk = 1: Fl.lastTick = Timer
    d.title = "Copying..."
    d.w = 380: d.h = 170
    CenterDialog d
    Dim As Long i = AddCtl(d, CT_BUTTON, 284, 104, 75, 23, "Cancel", IDCANCEL)
    d.c(i).isCancel = True: d.focus = i
    d.drawFn = @FloppyDraw
    d.readOutFn = @FloppyReadOut
    d.tickFn = @FloppyTick
    RunDialog d
    Return Fl.finished
End Function

' ---- Cal, the caliper assistant: shows itself once per run ----

Dim Shared CalVisible As Boolean
Dim Shared CalShown As Boolean
Dim Shared CalSilenced As Boolean
Dim Shared CalText As String
Dim Shared CalStage As Long          ' 0 asking, 1 helped
' With Turbo on, "don't show this again" pins the tip instead: a small note
' where Cal was. Its x really closes it. Nothing is saved.
Dim Shared CalPinned As Boolean
Const PIN_W = 300, PIN_H = 40

Const CAL_W = 300, CAL_H = 140

Sub CalPop(ByRef sSay As String)
    If CalSilenced Or CalShown Then Exit Sub
    CalShown = True: CalVisible = True: CalStage = 0
    CalText = sSay & Chr(10) & Chr(10) & "Would you like help?"
    NeedRedraw = True
End Sub

Sub CalRect(ByRef x As Long, ByRef y As Long)
    x = ScrW - CAL_W - 24: y = ScrH - CAL_H - 40
End Sub

' Buttons: 0 help, 1 no help / thanks, 2 never
Sub CalButtonRect(ByVal b As Long, ByRef bx As Long, ByRef by As Long, ByRef bw As Long)
    Dim As Long x, y
    CalRect x, y
    bx = x + 100: bw = CAL_W - 112: by = y + 62 + b * 22
End Sub

Function CalButtonText(ByVal b As Long) As String
    Select Case b
    Case 0: Return "&Get help with drawing the box"
    Case 1: Return IIf(CalStage = 0, "&Just draw the box without help", "&Thanks, Cal")
    Case 2: Return "&Don't show me this tip again"
    End Select
    Return ""
End Function

Sub PinRect(ByRef x As Long, ByRef y As Long)
    CalRect x, y
    y += CAL_H - PIN_H
End Sub

Sub PinCloseRect(ByRef bx As Long, ByRef by As Long)
    Dim As Long x, y
    PinRect x, y
    bx = x + PIN_W - 20: by = y + 4
End Sub

Sub DrawCal()
    Dim As Long x, y, b, bx, by, bw
    If CalPinned Then
        PinRect x, y
        Fill x, y, PIN_W, PIN_H, C_INFO
        Frame x, y, PIN_W, PIN_H, C_DARK
        Text x + 6, y + 6, "Cal's tip, pinned for you:", C_TEXT, True
        Text x + 6, y + 6 + LINE_H, "Boxes want to be extruded. Press E.", C_TEXT
        PinCloseRect bx, by
        Fill bx, by, 16, 14, C_FACE: Bevel bx, by, 16, 14, BEV_BUTTON
        Text bx + (16 - TextW("x")) \ 2, by + 2, "x", C_TEXT
    End If
    If Not CalVisible Then Exit Sub
    CalRect x, y
    Fill x, y, CAL_W, CAL_H, C_INFO
    Frame x, y, CAL_W, CAL_H, C_DARK
    DrawIcon x + 10, y + 10, "Cal", 3
    Dim As String t = CalText
    Dim As Long ty = y + 10
    Do
        Dim As Long p = InStr(t, Chr(10))
        Text x + 66, ty, Ellipsize(IIf(p, Left(t, p - 1), t), CAL_W - 76), C_TEXT
        ty += LINE_H
        If p = 0 Then Exit Do
        t = Mid(t, p + 1)
    Loop
    For b = 0 To 2
        If b = 0 And CalStage = 1 Then Continue For
        CalButtonRect b, bx, by, bw
        Fill bx, by, bw, 20, C_FACE: Bevel bx, by, bw, 20, BEV_BUTTON
        TextAmp bx + (bw - TextW(AmpStrip(CalButtonText(b)))) \ 2, by + 5, CalButtonText(b), C_TEXT
    Next
End Sub

' A click: True if it was on Cal.
Function CalClick(ByVal mx As Long, ByVal my As Long) As Boolean
    Dim As Long x, y, b, bx, by, bw
    If CalPinned And Not CalVisible Then
        PinRect x, y
        If mx < x Or mx >= x + PIN_W Or my < y Or my >= y + PIN_H Then Return False
        PinCloseRect bx, by
        If mx >= bx And mx < bx + 16 And my >= by And my < by + 14 Then
            CalPinned = False
            SetStatus "Cal will remember."
            NeedRedraw = True
        End If
        Return True
    End If
    If Not CalVisible Then Return False
    CalRect x, y
    If mx < x Or mx >= x + CAL_W Or my < y Or my >= y + CAL_H Then Return False
    For b = 0 To 2
        If b = 0 And CalStage = 1 Then Continue For
        CalButtonRect b, bx, by, bw
        If mx >= bx And mx < bx + bw And my >= by And my < by + 20 Then
            Select Case b
            Case 0
                CalText = "Here's a tip: boxes usually want to be" & Chr(10) & "extruded. Press E. If that doesn't" & Chr(10) & "work, press E harder."
                CalStage = 1
            Case 1
                CalVisible = False
            Case 2
                CalSilenced = True: CalVisible = False
                ' Turbo: the authentic 1999 reading of "don't show this again"
                If Turbo Then
                    CalPinned = True
                Else
                    MsgBox "OK. Cal won't show this tip again." & Chr(10) & "(Until you restart SolidCraft 98.)", MB_INFO, "Cal"
                End If
            End Select
            NeedRedraw = True
            Return True
        End If
    Next
    If mx < x + 60 Then CalText = "Did you know? Every SolidCraft 98 file" & Chr(10) & "is also a perfectly good door stop," & Chr(10) & "if you print it out."
    NeedRedraw = True
    Return True
End Function

' ---- DLL Hell: Turbo on, Help > About, Shift-click the logo ----

Dim Shared SetupPct As Double, SetupLast As Double

Sub SetupDraw(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    Dim As Long ox = ClientX(*d), oy = ClientY(*d), x
    Dim As Long w = d->w - 6
    GradientV ox, oy, w, d->h - DLG_TITLE_H - 7, &hFF0000A0, &hFF000020
    TextAt ox + 16, oy + 12, "SolidCraft 98 Setup", C_HILITE, True
    Dim As String sFile
    If SetupPct > 100 Then
        sFile = "Copying more than all of it..."
    ElseIf SetupPct > 30 Then
        sFile = "A newer version exists. Copying the older one over it anyway..."
    Else
        sFile = "Checking for a newer version of MSCOMCTL.OCX..."
    End If
    Text ox + 16, oy + 40, sFile, &hFFFFFFC0
    Text ox + 16, oy + 62, "Source:       C:\WINDOWS\SYSTEM\MSCOMCTL.OCX", C_HILITE
    Text ox + 16, oy + 78, "Destination:  C:\WINDOWS\SYSTEM\MSCOMCTL.OCX", C_HILITE
    Fill ox + 16, oy + 104, 369, 21, C_FACE: Bevel ox + 16, oy + 104, 369, 21, BEV_THIN_DOWN
    Dim As Long bw = 364 * IIf(SetupPct > 100, 1, SetupPct / 100)
    For x = 19 To 16 + bw Step 10
        Fill ox + x, oy + 107, 8, 15, IIf(SetupPct > 100, &hFFFF0000, &hFF000080)
    Next
    Text ox + 190, oy + 132, Int(SetupPct) & "%", C_HILITE
    Text ox + 16, oy + 164, "Please do not turn off your computer.", C_FACE
End Sub

Function SetupReadOut(ByVal dp As Any Ptr) As String
    Return "Copying C:\WINDOWS\SYSTEM\MSCOMCTL.OCX over C:\WINDOWS\SYSTEM\MSCOMCTL.OCX: " & Int(SetupPct) & _
        "%. Please do not turn off your computer. (No buttons: it has to finish.)"
End Function

Sub SetupTick(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    If Timer - SetupLast < 0.08 Then Exit Sub
    SetupLast = Timer
    SetupPct += 1 + Rnd * 2
    If SetupPct >= 112 Then
        SetupPct = 112
        RenderFrame
        MsgBox "Setup has updated your system files." & Chr(10) & Chr(10) & _
            "Please restart Windows to complete setup." & Chr(10) & _
            "(Excel may not start afterwards. That's normal.)", MB_EXCLAMATION, "SolidCraft 98 Setup"
        MsgBox "Just kidding. Nothing was copied and nothing needs restarting." & Chr(10) & _
            "Your Excel is fine.", MB_INFO, "SolidCraft 98 Setup"
        d->done = True
    End If
End Sub

Function SetupKey(ByVal dp As Any Ptr, ByRef ev As UIEvent) As Boolean
    Return True                  ' no way out but through
End Function

Sub ShowSetup()
    Dim d As TDlg
    SetupPct = 0: SetupLast = Timer
    d.title = "SolidCraft 98 Setup"
    d.w = 406: d.h = 216
    CenterDialog d
    d.drawFn = @SetupDraw
    d.readOutFn = @SetupReadOut
    d.tickFn = @SetupTick
    d.keyFn = @SetupKey
    d.focus = -1
    RunDialog d
End Sub

' ---- the WIN98 credits: starfield, copper bars, a sine scroller ----

Const STARS = 90
Dim Shared StarX(1 To STARS) As Double, StarY(1 To STARS) As Double, StarZ(1 To STARS) As Double
Dim Shared DemoT As Long, DemoScroll As Double, DemoLast As Double

Sub CreditsDraw(ByVal dp As Any Ptr)
    Static lines(0 To 32) As ZString * 56 = { _
        "SOLIDCRAFT 98", "THE PROFESSIONAL EDITION", "", _
        "A FORTY-THOUSAND-LINE PRODUCTION", "", "", _
        "GEOMETRY KERNEL", "KERNEL.BAS (ALL OF IT)", "", _
        "CONSTRAINT SOLVER", "THE VARIANT SQUAD", "", _
        "CHIEF REGENERATE CLICKER", "PRESS F5 THREE TIMES", "", _
        "ICONS", "16 COLOURS, NO UNDO", "", _
        "FILE FORMAT", "PUT #1, , DESIGN", "", _
        "QUALITY ASSURANCE", "THE MACHINE SHOP", "", _
        "SPECIAL THANKS", "THE ONE PC NOBODY IS ALLOWED TO UPDATE", "", _
        "NO PARTS WERE HARMED IN THE MAKING OF THIS SOFTWARE", "", "", "", "", "PRESS ANY KEY" }
    Dim As TDlg Ptr d = dp
    Dim As Long w = d->w, h = d->h, ox = d->x, oy = d->y, i, k
    Dim As Double cx = w / 2, cy = h / 2
    Fill ox, oy, w, h, &hFF000000
    ClipTo ox, oy, w, h
    ' copper bars
    For k = 0 To 2
        Dim As Long yy = cy + Sin((DemoT + k * 25) / 15) * (h / 4)
        For i = 0 To 7
            Dim As ULong c
            Select Case k
            Case 0: c = RGB(40 + i * 25, 0, 120 - i * 10)
            Case 1: c = RGB(0, 40 + i * 25, 100)
            Case 2: c = RGB(40 + i * 25, 40 + i * 25, 0)
            End Select
            HLine ox, oy + yy - 8 + i, w, c: HLine ox, oy + yy + 8 - i, w, c
        Next
    Next
    ' the starfield
    For i = 1 To STARS
        Dim As Long sx = ox + cx + StarX(i) / StarZ(i) * cx * 0.5, sy = oy + cy + StarY(i) / StarZ(i) * cy * 0.5
        Dim As Long v = 255 * (1 - StarZ(i))
        PSetC sx, sy, RGB(v, v, v)
        If StarZ(i) < 0.3 Then PSetC sx + 1, sy, RGB(v, v, v)
    Next
    ' the credits, rolling up
    For i = 0 To 32
        Dim As Long y = DemoScroll + i * 26
        If y > -20 And y < h Then
            Dim As String t = lines(i)
            TextAt ox + (w - TextW(t, True, 2)) \ 2, oy + y, t, IIf(i Mod 3 = 0, &hFFFFFF00, &hFF00FFFF), True, 2
        End If
    Next
    ' the sine scroller along the bottom
    Dim As String msg = "   GREETINGS TO EVERYONE STILL RUNNING WINDOWS 98 SE ...  TURBO OFF IS FASTER THAN TURBO ON ...  BEST VIEWED AT 800 X 600 ...  "
    Dim As Long mw = TextW(msg, True, 2)
    Dim As Long x = w - ((DemoT * 4) Mod (mw + w))
    For k = 1 To Len(msg)
        Dim As String ch = Mid(msg, k, 1)
        If x > -20 And x < w Then
            TextAt ox + x, oy + h - 50 + Sin((x + DemoT * 6) / 30) * 10, ch, RGB(255, 128 + 127 * Sin((k + DemoT) / 6), 64), True, 2
        End If
        x += TextW(ch, True, 2) + 2
    Next
    NoClip
End Sub

Sub CreditsTick(ByVal dp As Any Ptr)
    Dim As TDlg Ptr d = dp
    Dim i As Long
    If Timer - DemoLast < 0.03 Then Exit Sub
    DemoLast = Timer
    DemoT += 1
    For i = 1 To STARS
        StarZ(i) -= 0.01
        If StarZ(i) <= 0.02 Then StarX(i) = Rnd * 2 - 1: StarY(i) = Rnd * 2 - 1: StarZ(i) = 1
    Next
    DemoScroll -= 1.4
    If DemoScroll < -33 * 26 Then DemoScroll = d->h
End Sub

Function CreditsKey(ByVal dp As Any Ptr, ByRef ev As UIEvent) As Boolean
    Dim As TDlg Ptr d = dp
    d->done = True
    Return True
End Function

Function CreditsMouse(ByVal dp As Any Ptr, ByRef ev As UIEvent) As Boolean
    Dim As TDlg Ptr d = dp
    If ev.kind = EV_DOWN Then d->done = True
    Return True
End Function

Function CreditsReadOut(ByVal dp As Any Ptr) As String
    Return "A demo-scene credits screen: stars, copper bars and scrolling text. A click or a key closes it."
End Function

Sub ShowCredits()
    Dim d As TDlg
    Dim i As Long
    Randomize
    For i = 1 To STARS: StarX(i) = Rnd * 2 - 1: StarY(i) = Rnd * 2 - 1: StarZ(i) = Rnd: Next
    d.noFrame = True
    d.w = 560: d.h = 420
    CenterDialog d
    DemoT = 0: DemoScroll = d.h: DemoLast = 0
    d.drawFn = @CreditsDraw
    d.readOutFn = @CreditsReadOut
    d.tickFn = @CreditsTick
    d.keyFn = @CreditsKey
    d.mouseFn = @CreditsMouse
    d.focus = -1
    RunDialog d
End Sub

' ---- the splash ----

Declare Sub DrawLogo(ByVal ox As Long, ByVal oy As Long, ByVal s As Double, ByVal c As ULong)
Dim Shared SplashMsg As String

Sub DrawSplash()
    Dim As Long w = 440, h = 280, x = (ScrW - w) \ 2, y = (ScrH - h) \ 2
    GradientV x, y, w, h, &hFF000080, &hFF000000
    DrawLogo x + 90, y + 70, 26, &hFFFFFF00
    TextAt x + 190, y + 50, "SolidCraft", C_HILITE, True, 3
    TextAt x + 330, y + 94, "98", &hFFFFFF00, True, 4
    Text x + 192, y + 136, "Professional Edition", C_FACE
    Text x + 16, y + 207, SplashMsg, C_HILITE
    Text x + 16, y + 230, "Version 1.2.0  Build 1998.1023", C_FACE
    Text x + 16, y + 246, "Copyright (C) 1998-1999 SolidCraft Software. Made with Line and Circle.", C_FACE
    Frame x, y, w, h, C_SHADOW
End Sub

Sub SplashProgress(ByRef msg As String)
    SplashMsg = msg
    ScreenLock
    SurfFromScreen S
    Fill 0, 0, ScrW, ScrH, &hFF008080        ' the desktop, teal
    DrawSplash
    ScreenUnlock
    If Not HeadlessMode Then Sleep 350, 1
End Sub

' ---- Publish to Web: a home page, a hit counter, an animated GIF ----
' The GIF writer sends a Clear code every few pixels so the code table never
' grows: every pixel goes out as its own 5-bit code. In 1999 that was called
' "web-ready".

Dim Shared gifData As String
Dim Shared gBits As ULong, gBitCount As Long
Dim Shared gBlock As String

Sub GPutByte(ByVal b As Long)
    gifData &= Chr(b And 255)
End Sub
Sub GPutWord(ByVal v As Long)
    GPutByte v And 255: GPutByte (v Shr 8) And 255
End Sub
Sub GFlush()
    If Len(gBlock) = 0 Then Exit Sub
    GPutByte Len(gBlock): gifData &= gBlock: gBlock = ""
End Sub
Sub GBlockByte(ByVal b As Long)
    gBlock &= Chr(b And 255)
    If Len(gBlock) = 255 Then GFlush
End Sub
Sub GCode(ByVal code As Long)
    gBits Or= CULng(code) Shl gBitCount
    gBitCount += 5
    Do While gBitCount >= 8
        GBlockByte gBits And 255
        gBits Shr= 8: gBitCount -= 8
    Loop
End Sub

Sub GifBegin(ByVal w As Long, ByVal h As Long, ByVal bLoop As Boolean)
    Dim i As Long
    gifData = "GIF89a"
    GPutWord w: GPutWord h
    GPutByte &hF3: GPutByte 0: GPutByte 0      ' 16-colour global table
    For i = 0 To 15
        GPutByte (QB(i) Shr 16) And 255: GPutByte (QB(i) Shr 8) And 255: GPutByte QB(i) And 255
    Next
    If bLoop Then
        GPutByte &h21: GPutByte &hFF: GPutByte 11
        gifData &= "NETSCAPE2.0"
        GPutByte 3: GPutByte 1: GPutWord 0: GPutByte 0
    End If
End Sub

' px is w*h palette indices, row by row.
Sub GifFrame(ByRef px As String, ByVal w As Long, ByVal h As Long, ByVal delay As Long, ByVal transparent As Long)
    Dim As Long i, nRun
    GPutByte &h21: GPutByte &hF9: GPutByte 4
    GPutByte IIf(transparent >= 0, 9, 8)
    GPutWord delay
    GPutByte IIf(transparent >= 0, transparent, 0)
    GPutByte 0
    GPutByte &h2C: GPutWord 0: GPutWord 0: GPutWord w: GPutWord h: GPutByte 0
    GPutByte 4
    gBits = 0: gBitCount = 0: gBlock = ""
    GCode 16
    For i = 0 To w * h - 1
        GCode px[i]
        nRun += 1
        If nRun = 12 Then GCode 16: nRun = 0       ' before the table would need 6-bit codes
    Next
    GCode 17
    If gBitCount > 0 Then GBlockByte gBits And 255
    GFlush
    GPutByte 0
End Sub

Function GifSave(ByRef sPath As String) As Boolean
    GPutByte &h3B
    If Len(Dir(sPath)) Then Kill sPath
    Dim As Long fh = FreeFile
    If Open(sPath For Binary Access Write As #fh) <> 0 Then Return False
    Put #fh, , gifData
    Close #fh
    Return True
End Function

Function NearestQB(ByVal c As ULong) As Long
    Dim As Long i, best = &h7FFFFFFF, bi
    Dim As Long r = (c Shr 16) And 255, g = (c Shr 8) And 255, b = c And 255
    For i = 0 To 15
        Dim As Long q = QB(i)
        Dim As Long dd = (r - ((q Shr 16) And 255)) ^ 2 + (g - ((q Shr 8) And 255)) ^ 2 + (b - (q And 255)) ^ 2
        If dd < best Then best = dd: bi = i
    Next
    Return bi
End Function

Function HtmlText(ByVal s As String) As String
    Dim As String r
    Dim i As Long
    For i = 1 To Len(s)
        Select Case Mid(s, i, 1)
        Case "&": r &= "&amp;"
        Case "<": r &= "&lt;"
        Case ">": r &= "&gt;"
        Case """": r &= "&quot;"
        Case Else: r &= Mid(s, i, 1)
        End Select
    Next
    Return r
End Function

Function MakeFileName(ByRef s As String) As String
    Dim As String r
    Dim i As Long
    For i = 1 To Len(s)
        Dim As String ch = Mid(s, i, 1)
        If (ch >= "A" And ch <= "Z") Or (ch >= "a" And ch <= "z") Or (ch >= "0" And ch <= "9") Or ch = "_" Or ch = "-" Then r &= ch
    Next
    If Len(r) = 0 Then r = "mypart"
    Return r
End Function

Sub PublishPart(ByVal p As Long)
    Dim As Long slot = Parts(p).slot, i, x, y
    Dim As String sHtml = FileDialog(True, MakeFileName(Docs(slot).Title) & ".htm", "Web Pages (*.htm)|*.htm", "htm")
    If Len(sHtml) = 0 Then Exit Sub
    Dim As String sDir = Left(sHtml, InStrRev(sHtml, "/")), sBase = FileTitle(sHtml)
    Busy = True
    SetStatus "Rendering " & sBase & ".gif..."
    RenderFrame
    ' the view as it is now, squeezed into the 16 colours
    Dim As Long w, h, bypp, pitch
    Dim As Any Ptr pxp
    ImageInfo Parts(p).viewImg, w, h, bypp, pitch, pxp
    Dim As String px = String(w * h, 0)
    For y = 0 To h - 1
        Dim As ULong Ptr row = pxp + y * pitch
        For x = 0 To w - 1: px[y * w + x] = NearestQB(row[x]): Next
    Next
    GifBegin w, h, False
    GifFrame px, w, h, 0, -1
    GifSave sDir & sBase & ".gif"
    ' the road sign, two frames at 3x, blinking twice a second
    GifBegin 48, 48, True
    Dim As String keys(1) = {"Construction", "Construction2"}
    For i = 0 To 1
        Dim As Long k = IconIndex(keys(i))
        Dim As String fr = String(48 * 48, 0)
        For y = 0 To 47
            For x = 0 To 47
                Dim As Long ch = IconArt(k, y \ 3)[x \ 3]
                fr[y * 48 + x] = IIf(ch = Asc("."), 13, IIf(ch <= Asc("9"), ch - Asc("0"), ch - Asc("A") + 10))
            Next
        Next
        GifFrame fr, 48, 48, 50, 13          ' magenta is see-through
    Next
    GifSave sDir & "construction.gif"
    ' the page
    Dim As String sTitle = HtmlText(Docs(slot).Title), hits = Right("000000" & (427 + Int(Rnd * 9000)), 6)
    Dim As Long fh = FreeFile
    If Open(sHtml For Output As #fh) <> 0 Then Busy = False: MsgBox "Could not write " & sHtml, MB_CRITICAL: Exit Sub
    Print #fh, "<HTML>"
    Print #fh, "<HEAD><TITLE>" & sTitle & " - My SolidCraft 98 Part!!!</TITLE></HEAD>"
    Print #fh, "<BODY BGCOLOR=""#000080"" TEXT=""#FFFF00"" LINK=""#00FFFF"" VLINK=""#FF00FF"">"
    Print #fh, "<CENTER>"
    Print #fh, "<MARQUEE BEHAVIOR=""alternate""><FONT FACE=""Comic Sans MS"" SIZE=""6""><B>Welcome to " & sTitle & "!!!</B></FONT></MARQUEE>"
    Print #fh, "<P><IMG SRC=""construction.gif"" WIDTH=""48"" HEIGHT=""48""> <FONT SIZE=""5""><B>This page is under construction!</B></FONT> <IMG SRC=""construction.gif"" WIDTH=""48"" HEIGHT=""48""></P>"
    Print #fh, "<HR WIDTH=""80%"">"
    Print #fh, "<P><IMG SRC=""" & sBase & ".gif"" BORDER=""4"" ALT=""" & sTitle & """></P>"
    Print #fh, "<TABLE BORDER=""3"" CELLPADDING=""4"" BGCOLOR=""#C0C0C0"">"
    Print #fh, "<TR><TH><FONT COLOR=""#000000"">#</FONT></TH><TH><FONT COLOR=""#000000"">Feature</FONT></TH><TH><FONT COLOR=""#000000"">What it is</FONT></TH></TR>"
    For i = 1 To Docs(slot).Count
        Print #fh, "<TR><TD><FONT COLOR=""#000000"">" & i & "</FONT></TD><TD><FONT COLOR=""#000000"">" & _
            HtmlText(FeatureName(Docs(slot), i)) & "</FONT></TD><TD><FONT COLOR=""#000000"">" & _
            HtmlText(Describe(Docs(slot), i)) & "</FONT></TD></TR>"
    Next
    Print #fh, "</TABLE>"
    Print #fh, "<P>You are visitor number"
    Print #fh, "<TABLE BORDER=""1"" CELLPADDING=""2"" CELLSPACING=""0"" BGCOLOR=""#000000""><TR>"
    For i = 1 To Len(hits)
        Print #fh, "<TD><FONT FACE=""Courier New"" COLOR=""#00FF00"" SIZE=""5""><B>" & Mid(hits, i, 1) & "</B></FONT></TD>"
    Next
    Print #fh, "</TR></TABLE></P>"
    Print #fh, "<P><A HREF=""#"">Sign my guestbook!</A> | <A HREF=""#"">View my guestbook!</A> | <A HREF=""#"">Next site in the CAD Web Ring &gt;&gt;</A></P>"
    Print #fh, "<HR WIDTH=""80%"">"
    Print #fh, "<FONT SIZE=""2"">Best viewed in Netscape at 800x600. Made with SolidCraft 98 Version 1.2.0.<BR>"
    Print #fh, "Last updated " & Format(ClockNow(), "mmmm d, yyyy") & ".</FONT>"
    Print #fh, "</CENTER>"
    Print #fh, "</BODY>"
    Print #fh, "</HTML>"
    Close #fh
    Busy = False
    SetStatus "Published " & sHtml
    MsgBox "Your part is on the World Wide Web!*" & Chr(10) & Chr(10) & sHtml & Chr(10) & Chr(10) & _
        "* On your hard disk. Upload it with your FTP program.", MB_INFO, "Publish to Web"
End Sub
