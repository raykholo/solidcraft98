' stl.bas - Export for Rapid Prototyping: the part as a binary STL file.
'
' The 1989 rules are kept: every triangle faces out, neighbours share whole
' edges, everything sits in the all-positive corner of space, millimetres.
' The header must not begin with "solid", or some programs read it as text.

Sub PutSingle(ByVal fh As Long, ByVal v As Double)
    Dim s As Single = v
    Put #fh, , s
End Sub

' Writes n triangles to sPath. Returns True if it worked.
Function WriteStl(t() As TTri, ByVal n As Long, ByRef sPath As String, ByRef sTitle As String) As Boolean
    Dim As Long fh, i
    Dim As Double mx, my, mz, nx, ny, nz
    Dim As ULong cnt = n
    Dim As UShort attr = 0
    If n = 0 Then Return False
    ' the lowest corner, so everything can be moved to x, y, z >= 0
    mx = t(0).X1: my = t(0).Y1: mz = t(0).Z1
    For i = 0 To n - 1
        With t(i)
            mx = Min3(Min3(mx, .X1, .X2), .X3, .X3)
            my = Min3(Min3(my, .Y1, .Y2), .Y3, .Y3)
            mz = Min3(Min3(mz, .Z1, .Z2), .Z3, .Z3)
        End With
    Next i
    Dim As String hdr = Left("Binary STL from SolidCraft 98: " & sTitle & ", mm" & Space(80), 80)
    If Len(Dir(sPath)) Then Kill sPath
    fh = FreeFile
    If Open(sPath For Binary Access Write As #fh) <> 0 Then Return False
    Put #fh, , hdr
    Put #fh, , cnt
    For i = 0 To n - 1
        With t(i)
            TriNormal t(i), nx, ny, nz
            PutSingle fh, nx: PutSingle fh, ny: PutSingle fh, nz
            PutSingle fh, .X1 - mx: PutSingle fh, .Y1 - my: PutSingle fh, .Z1 - mz
            PutSingle fh, .X2 - mx: PutSingle fh, .Y2 - my: PutSingle fh, .Z2 - mz
            PutSingle fh, .X3 - mx: PutSingle fh, .Y3 - my: PutSingle fh, .Z3 - mz
            Put #fh, , attr
        End With
    Next i
    Close #fh
    Return True
End Function
