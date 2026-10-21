Attribute VB_Name = "modExpr"
' modExpr - number boxes take arithmetic: 40/2+5, (10+2)*3, -8.
'
' Anything that isn't a number or + - * / ( ) raises run-time error 13,
' the same as CDbl would, so "20mm" is still a type mismatch. Dividing by
' zero raises error 11, which is what VB does.
Option Explicit

Private mS As String
Private mPos As Long

Public Function Evaluate(ByVal s As String) As Double
    mS = Replace(Trim$(s), " ", "")
    mPos = 1
    If Len(mS) = 0 Then Err.Raise 13
    Evaluate = ParseSum()
    If mPos <= Len(mS) Then Err.Raise 13
End Function

Private Function Peek() As String
    If mPos <= Len(mS) Then Peek = Mid$(mS, mPos, 1)
End Function

Private Function ParseSum() As Double
    Dim v As Double, op As String
    v = ParseProduct()
    Do
        op = Peek()
        If op <> "+" And op <> "-" Then Exit Do
        mPos = mPos + 1
        If op = "+" Then v = v + ParseProduct() Else v = v - ParseProduct()
    Loop
    ParseSum = v
End Function

Private Function ParseProduct() As Double
    Dim v As Double, op As String, d As Double
    v = ParseFactor()
    Do
        op = Peek()
        If op <> "*" And op <> "/" Then Exit Do
        mPos = mPos + 1
        If op = "*" Then
            v = v * ParseFactor()
        Else
            d = ParseFactor()
            If d = 0 Then Err.Raise 11
            v = v / d
        End If
    Loop
    ParseProduct = v
End Function

Private Function ParseFactor() As Double
    Dim start As Long, ch As String
    ch = Peek()
    If ch = "-" Then
        mPos = mPos + 1
        ParseFactor = -ParseFactor()
        Exit Function
    End If
    If ch = "(" Then
        mPos = mPos + 1
        ParseFactor = ParseSum()
        If Peek() <> ")" Then Err.Raise 13
        mPos = mPos + 1
        Exit Function
    End If
    start = mPos
    Do While mPos <= Len(mS)
        ch = Mid$(mS, mPos, 1)
        If (ch >= "0" And ch <= "9") Or ch = "." Then mPos = mPos + 1 Else Exit Do
    Loop
    If mPos = start Then Err.Raise 13
    ParseFactor = Val(Mid$(mS, start, mPos - start))
End Function
