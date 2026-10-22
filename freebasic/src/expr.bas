' expr.bas - number boxes take arithmetic: 40/2+5, (10+2)*3, -8.
'
' Anything that isn't a number or + - * / ( ) is error 13 (type mismatch),
' as CDbl would say, so "20mm" is still a type mismatch. Dividing by zero is
' error 11, which is what VB does. The error comes back in exErr.

Dim Shared exS As String
Dim Shared exPos As Long
Dim Shared exErr As Long

Declare Function ParseSum() As Double

Function ExPeek() As String
    If exPos <= Len(exS) Then Return Mid(exS, exPos, 1)
    Return ""
End Function

Function ParseFactor() As Double
    Dim As String ch = ExPeek()
    Dim As Long start
    If exErr Then Return 0
    If ch = "-" Then
        exPos += 1
        Return -ParseFactor()
    End If
    If ch = "(" Then
        exPos += 1
        Dim v As Double = ParseSum()
        If ExPeek() <> ")" Then exErr = 13: Return 0
        exPos += 1
        Return v
    End If
    start = exPos
    Do While exPos <= Len(exS)
        ch = Mid(exS, exPos, 1)
        If (ch >= "0" And ch <= "9") Or ch = "." Then exPos += 1 Else Exit Do
    Loop
    If exPos = start Then exErr = 13: Return 0
    Return Val(Mid(exS, start, exPos - start))
End Function

Function ParseProduct() As Double
    Dim As Double v = ParseFactor(), dv
    Dim As String op
    Do
        If exErr Then Return 0
        op = ExPeek()
        If op <> "*" And op <> "/" Then Exit Do
        exPos += 1
        If op = "*" Then
            v *= ParseFactor()
        Else
            dv = ParseFactor()
            If exErr = 0 And dv = 0 Then exErr = 11: Return 0
            v /= dv
        End If
    Loop
    Return v
End Function

Function ParseSum() As Double
    Dim As Double v = ParseProduct()
    Dim As String op
    Do
        If exErr Then Return 0
        op = ExPeek()
        If op <> "+" And op <> "-" Then Exit Do
        exPos += 1
        If op = "+" Then v += ParseProduct() Else v -= ParseProduct()
    Loop
    Return v
End Function

' The value of s; exErr is 0, 11 (division by zero) or 13 (type mismatch).
Function Evaluate(ByRef s As String) As Double
    Dim As String t = Trim(s)
    Dim As Long i
    exS = ""
    For i = 1 To Len(t)
        If Mid(t, i, 1) <> " " Then exS &= Mid(t, i, 1)
    Next i
    exPos = 1: exErr = 0
    If Len(exS) = 0 Then exErr = 13: Return 0
    Dim v As Double = ParseSum()
    If exErr = 0 And exPos <= Len(exS) Then exErr = 13
    Return v
End Function
