' gfx.bas - drawing, straight into pixel memory.
'
' Everything on screen is drawn here, by hand, the way a 1998 control
' library would: rectangles, 3D bevels, gradient title bars, text in our
' own pixel font, and the 16-colour icons. Drawing goes to a "surface":
' the screen's back page or an off-screen image, with a clip rectangle.

Type Surf
    px As ULong Ptr
    w As Long
    h As Long
    pitch As Long          ' in pixels
    cx1 As Long            ' clip, inclusive
    cy1 As Long
    cx2 As Long
    cy2 As Long
End Type

Dim Shared S As Surf       ' where drawing goes now

' The Windows 98 "Windows Standard" scheme
Const C_FACE = &hFFC0C0C0
Const C_LIGHT = &hFFDFDFDF
Const C_HILITE = &hFFFFFFFF
Const C_SHADOW = &hFF808080
Const C_DARK = &hFF000000
Const C_WINDOW = &hFFFFFFFF
Const C_TEXT = &hFF000000
Const C_GRAYTEXT = &hFF808080
Const C_SEL = &hFF000080
Const C_SELTEXT = &hFFFFFFFF
Const C_TITLE1 = &hFF000080
Const C_TITLE2 = &hFF1084D0
Const C_TITLEI1 = &hFF808080
Const C_TITLEI2 = &hFFB5B5B5
Const C_APPWORK = &hFF808080
Const C_INFO = &hFFFFFFE1

Dim Shared QB(0 To 15) As ULong = { &hFF000000, &hFF000080, &hFF008000, &hFF008080, &hFF800000, &hFF800080, _
    &hFF808000, &hFFC0C0C0, &hFF808080, &hFF0000FF, &hFF00FF00, &hFF00FFFF, &hFFFF0000, &hFFFF00FF, &hFFFFFF00, &hFFFFFFFF }

Sub SurfFromImage(ByRef sf As Surf, ByVal img As Any Ptr)
    Dim As Long w, h, bypp, pitch
    Dim As Any Ptr p
    ImageInfo img, w, h, bypp, pitch, p
    sf.px = p: sf.w = w: sf.h = h: sf.pitch = pitch \ 4
    sf.cx1 = 0: sf.cy1 = 0: sf.cx2 = w - 1: sf.cy2 = h - 1
End Sub

Sub SurfFromScreen(ByRef sf As Surf)
    Dim As Long w, h, pitch
    ScreenInfo w, h, , , pitch
    sf.px = ScreenPtr(): sf.w = w: sf.h = h: sf.pitch = pitch \ 4
    sf.cx1 = 0: sf.cy1 = 0: sf.cx2 = w - 1: sf.cy2 = h - 1
End Sub

Sub ClipTo(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    S.cx1 = IIf(x < 0, 0, x): S.cy1 = IIf(y < 0, 0, y)
    S.cx2 = x + w - 1: S.cy2 = y + h - 1
    If S.cx2 > S.w - 1 Then S.cx2 = S.w - 1
    If S.cy2 > S.h - 1 Then S.cy2 = S.h - 1
End Sub

Sub NoClip()
    S.cx1 = 0: S.cy1 = 0: S.cx2 = S.w - 1: S.cy2 = S.h - 1
End Sub

Sub PSetC(ByVal x As Long, ByVal y As Long, ByVal c As ULong)
    If x < S.cx1 Or x > S.cx2 Or y < S.cy1 Or y > S.cy2 Then Exit Sub
    S.px[y * S.pitch + x] = c
End Sub

Function PGet(ByVal x As Long, ByVal y As Long) As ULong
    If x < 0 Or y < 0 Or x >= S.w Or y >= S.h Then Return 0
    Return S.px[y * S.pitch + x]
End Function

Sub Fill(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal c As ULong)
    Dim As Long x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, yy, xx
    If x1 < S.cx1 Then x1 = S.cx1
    If y1 < S.cy1 Then y1 = S.cy1
    If x2 > S.cx2 Then x2 = S.cx2
    If y2 > S.cy2 Then y2 = S.cy2
    If x1 > x2 Or y1 > y2 Then Exit Sub
    For yy = y1 To y2
        Dim As ULong Ptr p = S.px + yy * S.pitch + x1
        For xx = x1 To x2
            *p = c: p += 1
        Next xx
    Next yy
End Sub

Sub HLine(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal c As ULong)
    Fill x, y, w, 1, c
End Sub

Sub VLine(ByVal x As Long, ByVal y As Long, ByVal h As Long, ByVal c As ULong)
    Fill x, y, 1, h, c
End Sub

Sub Frame(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal c As ULong)
    HLine x, y, w, c: HLine x, y + h - 1, w, c
    VLine x, y, h, c: VLine x + w - 1, y, h, c
End Sub

' A line, any direction (Bresenham), clipped per pixel.
Sub DrawLine(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long, ByVal c As ULong)
    Dim As Long dx = Abs(x2 - x1), dy = -Abs(y2 - y1), sx = IIf(x1 < x2, 1, -1), sy = IIf(y1 < y2, 1, -1), e = dx + dy, e2
    ' a line wholly off one side draws nothing
    If (x1 < S.cx1 And x2 < S.cx1) Or (x1 > S.cx2 And x2 > S.cx2) Or (y1 < S.cy1 And y2 < S.cy1) Or (y1 > S.cy2 And y2 > S.cy2) Then Exit Sub
    Dim As Long guard = 0
    Do
        PSetC x1, y1, c
        If x1 = x2 And y1 = y2 Then Exit Do
        e2 = 2 * e
        If e2 >= dy Then e += dy: x1 += sx
        If e2 <= dx Then e += dx: y1 += sy
        guard += 1
        If guard > 20000 Then Exit Do
    Loop
End Sub

' Dotted line (focus rectangles, tree lines): every other pixel.
Sub DotH(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal c As ULong)
    Dim i As Long
    For i = 0 To w - 1 Step 2: PSetC x + i, y, c: Next
End Sub
Sub DotV(ByVal x As Long, ByVal y As Long, ByVal h As Long, ByVal c As ULong)
    Dim i As Long
    For i = 0 To h - 1 Step 2: PSetC x, y + i, c: Next
End Sub
Sub FocusRect(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    DotH x, y, w, C_TEXT: DotH x, y + h - 1, w, C_TEXT
    DotV x, y, h, C_TEXT: DotV x + w - 1, y, h, C_TEXT
End Sub

' ---- 3D edges, the Windows 98 way ----

Enum Bev
    BEV_RAISED         ' windows, dialogs: light/white outside-in, black/grey bottom right
    BEV_BUTTON         ' a push button
    BEV_PRESSED        ' a pushed button
    BEV_SUNKEN         ' text boxes, lists, the view
    BEV_THIN_UP        ' toolbar hover
    BEV_THIN_DOWN      ' toolbar pushed, status bar panels
End Enum

Sub Bevel(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal kind As Long)
    Select Case kind
    Case BEV_RAISED
        HLine x, y, w - 1, C_LIGHT: VLine x, y, h - 1, C_LIGHT
        HLine x, y + h - 1, w, C_DARK: VLine x + w - 1, y, h, C_DARK
        HLine x + 1, y + 1, w - 3, C_HILITE: VLine x + 1, y + 1, h - 3, C_HILITE
        HLine x + 1, y + h - 2, w - 2, C_SHADOW: VLine x + w - 2, y + 1, h - 2, C_SHADOW
    Case BEV_BUTTON
        HLine x, y, w - 1, C_HILITE: VLine x, y, h - 1, C_HILITE
        HLine x, y + h - 1, w, C_DARK: VLine x + w - 1, y, h, C_DARK
        HLine x + 1, y + 1, w - 3, C_LIGHT: VLine x + 1, y + 1, h - 3, C_LIGHT
        HLine x + 1, y + h - 2, w - 2, C_SHADOW: VLine x + w - 2, y + 1, h - 2, C_SHADOW
    Case BEV_PRESSED
        Frame x, y, w, h, C_DARK
        Frame x + 1, y + 1, w - 2, h - 2, C_SHADOW
    Case BEV_SUNKEN
        HLine x, y, w - 1, C_SHADOW: VLine x, y, h - 1, C_SHADOW
        HLine x, y + h - 1, w, C_HILITE: VLine x + w - 1, y, h, C_HILITE
        HLine x + 1, y + 1, w - 3, C_DARK: VLine x + 1, y + 1, h - 3, C_DARK
        HLine x + 1, y + h - 2, w - 2, C_LIGHT: VLine x + w - 2, y + 1, h - 2, C_LIGHT
    Case BEV_THIN_UP
        HLine x, y, w - 1, C_HILITE: VLine x, y, h - 1, C_HILITE
        HLine x, y + h - 1, w, C_SHADOW: VLine x + w - 1, y, h, C_SHADOW
    Case BEV_THIN_DOWN
        HLine x, y, w - 1, C_SHADOW: VLine x, y, h - 1, C_SHADOW
        HLine x, y + h - 1, w, C_HILITE: VLine x + w - 1, y, h, C_HILITE
    End Select
End Sub

' Left to right, from one colour to another (title bars).
Sub GradientH(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal c1 As ULong, ByVal c2 As ULong)
    Dim i As Long, t As Double
    If w <= 1 Then Fill x, y, w, h, c1: Exit Sub
    For i = 0 To w - 1
        t = i / (w - 1)
        Dim As ULong r = ((c1 Shr 16) And 255) * (1 - t) + ((c2 Shr 16) And 255) * t
        Dim As ULong g = ((c1 Shr 8) And 255) * (1 - t) + ((c2 Shr 8) And 255) * t
        Dim As ULong b = (c1 And 255) * (1 - t) + (c2 And 255) * t
        VLine x + i, y, h, &hFF000000 Or (r Shl 16) Or (g Shl 8) Or b
    Next i
End Sub

Sub GradientV(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long, ByVal c1 As ULong, ByVal c2 As ULong)
    Dim i As Long, t As Double
    If h <= 1 Then Fill x, y, w, h, c1: Exit Sub
    For i = 0 To h - 1
        t = i / (h - 1)
        Dim As ULong r = ((c1 Shr 16) And 255) * (1 - t) + ((c2 Shr 16) And 255) * t
        Dim As ULong g = ((c1 Shr 8) And 255) * (1 - t) + ((c2 Shr 8) And 255) * t
        Dim As ULong b = (c1 And 255) * (1 - t) + (c2 And 255) * t
        HLine x, y + i, w, &hFF000000 Or (r Shl 16) Or (g Shl 8) Or b
    Next i
End Sub

' ---- Text, in our own pixel font ----

Const LINE_H = 13          ' line spacing

Function CharW(ByVal ch As Long, ByVal bold As Boolean = False) As Long
    Dim w As Long = FontW(ch And 255)
    If w = 0 And ch <> 32 Then w = 4        ' an unknown character: a little box
    Return w + 1 + IIf(bold, 1, 0)
End Function

Function TextW(ByRef t As String, ByVal bold As Boolean = False, ByVal scale As Long = 1) As Long
    Dim As Long i, w
    For i = 0 To Len(t) - 1
        w += CharW(t[i], bold)
    Next i
    If w > 0 Then w -= 1
    Return w * scale
End Function

' Draws one line of text with its top at y. Returns the x after it.
Function TextAt(ByVal x As Long, ByVal y As Long, ByRef t As String, ByVal c As ULong, ByVal bold As Boolean = False, ByVal scale As Long = 1) As Long
    Dim As Long i, ch, r, col, w
    For i = 0 To Len(t) - 1
        ch = t[i]
        w = FontW(ch)
        If w = 0 And ch <> 32 Then
            Frame x, y + 2 * scale, 3 * scale, 7 * scale, c      ' unknown: an empty box
            w = 4
        Else
            For r = 0 To FONT_H - 1
                Dim As Long bits = FontBits(ch, r)
                If bits Then
                    For col = 0 To w - 1
                        If bits And (1 Shl col) Then
                            If scale = 1 Then
                                PSetC x + col, y + r, c
                                If bold Then PSetC x + col + 1, y + r, c
                            Else
                                Fill x + col * scale, y + r * scale, scale * IIf(bold, 2, 1), scale, c
                            End If
                        End If
                    Next col
                End If
            Next r
        End If
        x += (w + 1 + IIf(bold, 1, 0)) * scale
    Next i
    Return x
End Function

Sub Text(ByVal x As Long, ByVal y As Long, ByRef t As String, ByVal c As ULong, ByVal bold As Boolean = False)
    TextAt x, y, t, c, bold
End Sub

' Greyed-out text, with the white "etched" shadow Windows used.
Sub TextDisabled(ByVal x As Long, ByVal y As Long, ByRef t As String)
    TextAt x + 1, y + 1, t, C_HILITE
    TextAt x, y, t, C_SHADOW
End Sub

' A menu or button caption: "&File" underlines the F. Returns the hot key (upper case) or "".
Function TextAmp(ByVal x As Long, ByVal y As Long, ByRef t As String, ByVal c As ULong, ByVal disabled As Boolean = False) As String
    Dim As Long i, cx = x
    Dim hot As String
    i = 0
    Do While i < Len(t)
        Dim ch As String = Chr(t[i])
        If ch = "&" And i + 1 < Len(t) Then
            i += 1
            ch = Chr(t[i])
            If ch <> "&" Then
                hot = UCase(ch)
                Dim As Long w = FontW(t[i])
                If disabled Then
                    HLine cx + 1, y + 11, w, C_HILITE: HLine cx, y + 10, w, C_SHADOW
                Else
                    HLine cx, y + 10, w, c
                End If
            End If
        End If
        If disabled Then
            TextAt cx + 1, y + 1, ch, C_HILITE
            cx = TextAt(cx, y, ch, C_SHADOW)
        Else
            cx = TextAt(cx, y, ch, c)
        End If
        i += 1
    Loop
    Return hot
End Function

Function AmpStrip(ByRef t As String) As String
    Dim As String r
    Dim i As Long
    Do While i < Len(t)
        If t[i] = Asc("&") And i + 1 < Len(t) Then i += 1
        r &= Chr(t[i])
        i += 1
    Loop
    Return r
End Function

' Text cut to fit a width, with "..." the way list views did it.
Function Ellipsize(ByRef t As String, ByVal maxw As Long, ByVal bold As Boolean = False) As String
    If TextW(t, bold) <= maxw Then Return t
    Dim As Long n = Len(t)
    Do While n > 0 And TextW(Left(t, n) & "...", bold) > maxw
        n -= 1
    Loop
    Return Left(t, n) & "..."
End Function

' ---- Icons: 16 x 16, from icons.bi ----

Function IconIndex(ByRef key As String) As Long
    Dim i As Long
    For i = 0 To ICON_COUNT - 1
        If IconName(i) = key Then Return i
    Next i
    Return -1
End Function

' Draws an icon at x, y, s times the size. Disabled icons are drawn the
' Windows way: white embossed shadow, then grey.
Sub DrawIcon(ByVal x As Long, ByVal y As Long, ByRef key As String, ByVal sc As Long = 1, ByVal disabled As Boolean = False)
    Dim As Long k = IconIndex(key), r, c
    If k < 0 Then Exit Sub
    For r = 0 To 15
        Dim As String row = IconArt(k, r)
        For c = 0 To 15
            Dim As Long ch = row[c]
            If ch <> Asc(".") Then
                Dim As Long v = IIf(ch <= Asc("9"), ch - Asc("0"), ch - Asc("A") + 10)
                If disabled Then
                    If v <> 15 And v <> 7 Then
                        Fill x + c * sc + 1, y + r * sc + 1, sc, sc, C_HILITE
                        Fill x + c * sc, y + r * sc, sc, sc, C_SHADOW
                    End If
                ElseIf sc = 1 Then
                    PSetC x + c, y + r, QB(v)
                Else
                    Fill x + c * sc, y + r * sc, sc, sc, QB(v)
                End If
            End If
        Next c
    Next r
End Sub
