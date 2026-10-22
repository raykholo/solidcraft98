' json.bas - reads JSON into a table of nodes, just arrays. A port of the
' Windows version's modJson. Nodes are numbered from 1; 0 means "none", so
' lookups chain without checking: JNum(JGet(JGet(r, "a"), "b")) is 0 when
' either key is missing. Errors go in JsonErr.

Const JS_NULL = 0, JS_BOOL = 1, JS_NUM = 2, JS_STR = 3, JS_ARR = 4, JS_OBJ = 5

Type TJNode
    Kind As Long
    Key As String
    S As String
    N As Double
    First As Long
    NextSib As Long
    Count As Long
End Type

Dim Shared jNodes() As TJNode
Dim Shared jCountN As Long
Dim Shared jText As String
Dim Shared jPos As Long          ' 0-based
Dim Shared JsonErr As String

Sub JFail(ByRef t As String)
    If Len(JsonErr) = 0 Then JsonErr = t
End Sub

Function JKind(ByVal n As Long) As Long
    If n > 0 Then Return jNodes(n).Kind
    Return JS_NULL
End Function

Function JCount(ByVal n As Long) As Long
    If n > 0 Then Return jNodes(n).Count
    Return 0
End Function

Function JStr(ByVal n As Long) As String
    If n = 0 Then Return ""
    Select Case jNodes(n).Kind
    Case JS_STR: Return jNodes(n).S
    Case JS_NUM: Return Trim(Str(jNodes(n).N))
    Case JS_BOOL: Return IIf(jNodes(n).N <> 0, "true", "false")
    End Select
    Return ""
End Function

Function JNum(ByVal n As Long) As Double
    If n = 0 Then Return 0
    Select Case jNodes(n).Kind
    Case JS_NUM, JS_BOOL: Return jNodes(n).N
    Case JS_STR: Return Val(jNodes(n).S)
    End Select
    Return 0
End Function

Function JBool(ByVal n As Long) As Boolean
    If n > 0 Then Return jNodes(n).N <> 0
    Return False
End Function

Function JGet(ByVal n As Long, ByRef sKey As String) As Long
    If n = 0 Then Return 0
    If jNodes(n).Kind <> JS_OBJ Then Return 0
    Dim As Long c = jNodes(n).First
    Do While c > 0
        If jNodes(c).Key = sKey Then Return c
        c = jNodes(c).NextSib
    Loop
    Return 0
End Function

Function JItem(ByVal n As Long, ByVal i As Long) As Long
    If n = 0 Then Return 0
    Dim As Long c = jNodes(n).First, k
    Do While c > 0
        If k = i Then Return c
        k += 1
        c = jNodes(c).NextSib
    Loop
    Return 0
End Function

Function NewNode(ByVal kind As Long) As Long
    jCountN += 1
    If jCountN > UBound(jNodes) Then ReDim Preserve jNodes(0 To UBound(jNodes) * 2 + 1)
    jNodes(jCountN).Kind = kind
    Return jCountN
End Function

Function JCh() As Long
    If jPos < Len(jText) Then Return jText[jPos]
    Return -1
End Function

Sub SkipSpace()
    Do While jPos < Len(jText)
        Dim As Long c = jText[jPos]
        If c = 32 Or c = 9 Or c = 13 Or c = 10 Then jPos += 1 Else Exit Do
    Loop
End Sub

' A code point as one byte of our Latin-1 font: anything past 255 is "?".
Function CodeChar(ByVal cp As Long) As String
    If cp < 256 Then Return Chr(cp)
    Return "?"
End Function

Function ParseString() As String
    Dim As String sOut
    jPos += 1                            ' the opening quote
    Do
        If jPos >= Len(jText) Then JFail "Unterminated string": Return sOut
        Dim As Long c = jText[jPos]
        If c = 34 Then
            jPos += 1: Exit Do
        ElseIf c = 92 Then
            Dim As Long e = IIf(jPos + 1 < Len(jText), jText[jPos + 1], 0)
            Select Case e
            Case Asc("n"): sOut &= Chr(10)
            Case Asc("r"): sOut &= Chr(13)
            Case Asc("t"): sOut &= Chr(9)
            Case Asc("b"): sOut &= Chr(8)
            Case Asc("f"): sOut &= Chr(12)
            Case Asc("u")
                sOut &= CodeChar(ValInt("&h" & Mid(jText, jPos + 3, 4)))
                jPos += 4
            Case Else: sOut &= Chr(e)          ' \" \\ \/
            End Select
            jPos += 2
        ElseIf c >= &hC0 Then
            ' UTF-8 to our Latin-1
            Dim As Long cp, extra
            If c >= &hF0 Then
                cp = c And 7: extra = 3
            ElseIf c >= &hE0 Then
                cp = c And 15: extra = 2
            Else
                cp = c And 31: extra = 1
            End If
            Dim As Long k
            For k = 1 To extra
                If jPos + k < Len(jText) Then cp = (cp Shl 6) Or (jText[jPos + k] And 63)
            Next
            sOut &= CodeChar(cp)
            jPos += 1 + extra
        Else
            sOut &= Chr(c)
            jPos += 1
        End If
    Loop
    Return sOut
End Function

Declare Function ParseValue() As Long

Function ParseObject() As Long
    Dim As Long n = NewNode(JS_OBJ), child, last
    jPos += 1
    SkipSpace
    If JCh() = Asc("}") Then jPos += 1: Return n
    Do
        SkipSpace
        If JCh() <> 34 Then JFail "Expected a member name": Return n
        Dim As String sKey = ParseString()
        SkipSpace
        If JCh() <> Asc(":") Then JFail "Expected :": Return n
        jPos += 1
        child = ParseValue()
        If Len(JsonErr) Then Return n
        jNodes(child).Key = sKey
        If last = 0 Then jNodes(n).First = child Else jNodes(last).NextSib = child
        last = child
        jNodes(n).Count += 1
        SkipSpace
        Select Case JCh()
        Case Asc(","): jPos += 1
        Case Asc("}"): jPos += 1: Exit Do
        Case Else: JFail "Expected , or }": Return n
        End Select
    Loop
    Return n
End Function

Function ParseArray() As Long
    Dim As Long n = NewNode(JS_ARR), child, last
    jPos += 1
    SkipSpace
    If JCh() = Asc("]") Then jPos += 1: Return n
    Do
        child = ParseValue()
        If Len(JsonErr) Then Return n
        If last = 0 Then jNodes(n).First = child Else jNodes(last).NextSib = child
        last = child
        jNodes(n).Count += 1
        SkipSpace
        Select Case JCh()
        Case Asc(","): jPos += 1
        Case Asc("]"): jPos += 1: Exit Do
        Case Else: JFail "Expected , or ]": Return n
        End Select
    Loop
    Return n
End Function

Function ParseValue() As Long
    SkipSpace
    If jPos >= Len(jText) Then JFail "The JSON ended early": Return NewNode(JS_NULL)
    Dim As Long c = JCh(), n
    Select Case c
    Case Asc("{"): Return ParseObject()
    Case Asc("["): Return ParseArray()
    Case 34
        n = NewNode(JS_STR)
        Dim As String s = ParseString()
        jNodes(n).S = s
        Return n
    Case Asc("t"), Asc("f"), Asc("n")
        If Mid(jText, jPos + 1, 4) = "true" Then
            n = NewNode(JS_BOOL): jNodes(n).N = 1: jPos += 4
        ElseIf Mid(jText, jPos + 1, 5) = "false" Then
            n = NewNode(JS_BOOL): jPos += 5
        ElseIf Mid(jText, jPos + 1, 4) = "null" Then
            n = NewNode(JS_NULL): jPos += 4
        Else
            JFail "Unexpected word in JSON": n = NewNode(JS_NULL)
        End If
        Return n
    Case Else
        Dim As Long start = jPos
        Do While jPos < Len(jText) AndAlso InStr("0123456789+-.eE", Chr(jText[jPos])) > 0
            jPos += 1
        Loop
        If jPos = start Then JFail "Unexpected character in JSON"
        n = NewNode(JS_NUM)
        jNodes(n).N = Val(Mid(jText, start + 1, jPos - start))
        Return n
    End Select
End Function

' Parses s (UTF-8). Returns the root node; JsonErr says what was wrong.
Function JsonParse(ByRef s As String) As Long
    jText = s
    If Left(jText, 3) = Chr(&hEF, &hBB, &hBF) Then jText = Mid(jText, 4)     ' a byte order mark
    jPos = 0: jCountN = 0: JsonErr = ""
    ReDim jNodes(0 To 1023)
    SkipSpace
    Dim As Long r = ParseValue()
    SkipSpace
    If Len(JsonErr) = 0 And jPos < Len(jText) Then JFail "Unexpected text after the JSON value"
    Return r
End Function
