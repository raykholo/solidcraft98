Attribute VB_Name = "modJson"
' modJson - reads JSON into a table of nodes. No Scripting.Dictionary, no
' OCX: just arrays, the way you did it when you couldn't count on the
' customer's PC having anything installed.
'
' JsonParse returns the root node. Nodes are numbered from 1; 0 means "none",
' so every lookup can be chained without checking: JNum(JGet(JGet(r, "a"), "b"))
' is 0 when either key is missing.
Option Explicit

Public Const JS_NULL As Integer = 0
Public Const JS_BOOL As Integer = 1
Public Const JS_NUM As Integer = 2
Public Const JS_STR As Integer = 3
Public Const JS_ARR As Integer = 4
Public Const JS_OBJ As Integer = 5

Private Type TJNode
    Kind As Integer
    Key As String         ' the member name, for a node inside an object
    S As String           ' a string's value
    N As Double           ' a number's value, or 1/0 for true/false
    First As Long         ' first child (arrays and objects)
    NextSib As Long       ' the next child of the same parent
    Count As Long         ' how many children
End Type

Private mNodes() As TJNode
Private mCount As Long
Private mText As String
Private mPos As Long

' Parses s. Returns the root node, or raises error 13 on bad JSON.
Public Function JsonParse(ByVal s As String) As Long
    mText = s
    mPos = 1
    mCount = 0
    ReDim mNodes(0 To 1023)
    SkipSpace
    JsonParse = ParseValue()
    SkipSpace
    If mPos <= Len(mText) Then Err.Raise 13, , "Unexpected text after the JSON value"
End Function

Public Function JKind(ByVal n As Long) As Integer
    If n > 0 Then JKind = mNodes(n).Kind
End Function

Public Function JCount(ByVal n As Long) As Long
    If n > 0 Then JCount = mNodes(n).Count
End Function

Public Function JStr(ByVal n As Long) As String
    If n = 0 Then Exit Function
    Select Case mNodes(n).Kind
    Case JS_STR: JStr = mNodes(n).S
    Case JS_NUM: JStr = Trim$(Str$(mNodes(n).N))
    Case JS_BOOL: If mNodes(n).N <> 0 Then JStr = "true" Else JStr = "false"
    End Select
End Function

Public Function JNum(ByVal n As Long) As Double
    If n = 0 Then Exit Function
    Select Case mNodes(n).Kind
    Case JS_NUM, JS_BOOL: JNum = mNodes(n).N
    Case JS_STR: JNum = Val(mNodes(n).S)
    End Select
End Function

Public Function JBool(ByVal n As Long) As Boolean
    If n > 0 Then JBool = (mNodes(n).N <> 0)
End Function

' The member called sKey of an object, or 0.
Public Function JGet(ByVal n As Long, ByVal sKey As String) As Long
    Dim c As Long
    If n = 0 Then Exit Function
    If mNodes(n).Kind <> JS_OBJ Then Exit Function
    c = mNodes(n).First
    Do While c > 0
        If mNodes(c).Key = sKey Then
            JGet = c
            Exit Function
        End If
        c = mNodes(c).NextSib
    Loop
End Function

' Item i (from 0) of an array or object, or 0.
Public Function JItem(ByVal n As Long, ByVal i As Long) As Long
    Dim c As Long, k As Long
    If n = 0 Then Exit Function
    c = mNodes(n).First
    Do While c > 0
        If k = i Then
            JItem = c
            Exit Function
        End If
        k = k + 1
        c = mNodes(c).NextSib
    Loop
End Function

' ---- the parser ----

Private Function NewNode(ByVal kind As Integer) As Long
    mCount = mCount + 1
    If mCount > UBound(mNodes) Then ReDim Preserve mNodes(0 To UBound(mNodes) * 2 + 1)
    mNodes(mCount).Kind = kind
    NewNode = mCount
End Function

Private Sub SkipSpace()
    Dim ch As String
    Do While mPos <= Len(mText)
        ch = Mid$(mText, mPos, 1)
        If ch = " " Or ch = vbTab Or ch = vbCr Or ch = vbLf Then mPos = mPos + 1 Else Exit Do
    Loop
End Sub

Private Function ParseValue() As Long
    Dim ch As String
    SkipSpace
    If mPos > Len(mText) Then Err.Raise 13, , "The JSON ended early"
    ch = Mid$(mText, mPos, 1)
    Select Case ch
    Case "{": ParseValue = ParseObject()
    Case "[": ParseValue = ParseArray()
    Case """"
        ParseValue = NewNode(JS_STR)
        mNodes(ParseValue).S = ParseString()
    Case "t", "f", "n": ParseValue = ParseWord()
    Case Else: ParseValue = ParseNumber()
    End Select
End Function

Private Function ParseObject() As Long
    Dim n As Long, child As Long, last As Long, sKey As String
    n = NewNode(JS_OBJ)
    mPos = mPos + 1
    SkipSpace
    If Mid$(mText, mPos, 1) = "}" Then
        mPos = mPos + 1
        ParseObject = n
        Exit Function
    End If
    Do
        SkipSpace
        If Mid$(mText, mPos, 1) <> """" Then Err.Raise 13, , "Expected a member name"
        sKey = ParseString()
        SkipSpace
        If Mid$(mText, mPos, 1) <> ":" Then Err.Raise 13, , "Expected :"
        mPos = mPos + 1
        child = ParseValue()
        mNodes(child).Key = sKey
        If last = 0 Then mNodes(n).First = child Else mNodes(last).NextSib = child
        last = child
        mNodes(n).Count = mNodes(n).Count + 1
        SkipSpace
        Select Case Mid$(mText, mPos, 1)
        Case ",": mPos = mPos + 1
        Case "}": mPos = mPos + 1: Exit Do
        Case Else: Err.Raise 13, , "Expected , or }"
        End Select
    Loop
    ParseObject = n
End Function

Private Function ParseArray() As Long
    Dim n As Long, child As Long, last As Long
    n = NewNode(JS_ARR)
    mPos = mPos + 1
    SkipSpace
    If Mid$(mText, mPos, 1) = "]" Then
        mPos = mPos + 1
        ParseArray = n
        Exit Function
    End If
    Do
        child = ParseValue()
        If last = 0 Then mNodes(n).First = child Else mNodes(last).NextSib = child
        last = child
        mNodes(n).Count = mNodes(n).Count + 1
        SkipSpace
        Select Case Mid$(mText, mPos, 1)
        Case ",": mPos = mPos + 1
        Case "]": mPos = mPos + 1: Exit Do
        Case Else: Err.Raise 13, , "Expected , or ]"
        End Select
    Loop
    ParseArray = n
End Function

Private Function ParseString() As String
    Dim ch As String, start As Long, sOut As String, code As Long
    mPos = mPos + 1                     ' the opening quote
    start = mPos
    Do
        If mPos > Len(mText) Then Err.Raise 13, , "Unterminated string"
        ch = Mid$(mText, mPos, 1)
        If ch = """" Then
            sOut = sOut & Mid$(mText, start, mPos - start)
            mPos = mPos + 1
            Exit Do
        ElseIf ch = "\" Then
            sOut = sOut & Mid$(mText, start, mPos - start)
            ch = Mid$(mText, mPos + 1, 1)
            Select Case ch
            Case "n": sOut = sOut & vbLf
            Case "r": sOut = sOut & vbCr
            Case "t": sOut = sOut & vbTab
            Case "b": sOut = sOut & Chr$(8)
            Case "f": sOut = sOut & Chr$(12)
            Case "u"
                code = CLng("&H" & Mid$(mText, mPos + 2, 4))
                sOut = sOut & ChrW$(code)
                mPos = mPos + 4
            Case Else: sOut = sOut & ch      ' \" \\ \/
            End Select
            mPos = mPos + 2
            start = mPos
        Else
            mPos = mPos + 1
        End If
    Loop
    ParseString = sOut
End Function

Private Function ParseWord() As Long
    If Mid$(mText, mPos, 4) = "true" Then
        ParseWord = NewNode(JS_BOOL)
        mNodes(ParseWord).N = 1
        mPos = mPos + 4
    ElseIf Mid$(mText, mPos, 5) = "false" Then
        ParseWord = NewNode(JS_BOOL)
        mPos = mPos + 5
    ElseIf Mid$(mText, mPos, 4) = "null" Then
        ParseWord = NewNode(JS_NULL)
        mPos = mPos + 4
    Else
        Err.Raise 13, , "Unexpected word in JSON"
    End If
End Function

Private Function ParseNumber() As Long
    Dim start As Long, ch As String
    start = mPos
    Do While mPos <= Len(mText)
        ch = Mid$(mText, mPos, 1)
        If InStr(1, "0123456789+-.eE", ch) > 0 Then mPos = mPos + 1 Else Exit Do
    Loop
    If mPos = start Then Err.Raise 13, , "Unexpected character in JSON"
    ParseNumber = NewNode(JS_NUM)
    mNodes(ParseNumber).N = Val(Mid$(mText, start, mPos - start))
End Function

' ---- UTF-8 bytes to a VB string ----

Public Function Utf8ToString(b() As Byte, ByVal n As Long) As String
    Dim i As Long, c As Long, out() As Integer, k As Long, s As String
    ReDim out(0 To n)
    Do While i < n
        c = b(i)
        If c < &H80 Then
            i = i + 1
        ElseIf c >= &HF0 And i + 3 < n Then
            c = &HFFFD                       ' outside the 16-bit range VB strings hold
            i = i + 4
        ElseIf c >= &HE0 And i + 2 < n Then
            c = ((c And &HF) * &H1000&) Or ((b(i + 1) And &H3F) * &H40&) Or (b(i + 2) And &H3F)
            i = i + 3
        ElseIf c >= &HC0 And i + 1 < n Then
            c = ((c And &H1F) * &H40&) Or (b(i + 1) And &H3F)
            i = i + 2
        Else
            i = i + 1
        End If
        If c > 32767 Then c = c - 65536
        out(k) = c
        k = k + 1
    Loop
    s = Space$(k)
    For i = 0 To k - 1
        Mid$(s, i + 1, 1) = ChrW$(out(i))
    Next i
    Utf8ToString = s
End Function
