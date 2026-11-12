' Fixture generator: compiles the unchanged FreeBASIC reference without a UI.
' fbc -w all -exx reference.bas -x sc98-reference
' ./sc98-reference <part.sc98|design.solidcraft> <output-stem>
#include "dir.bi"
#include "../../../freebasic/src/model.bas"
#include "../../../freebasic/src/kernel.bas"
#include "../../../freebasic/src/mesh.bas"
#include "../../../freebasic/src/expr.bas"
#include "../../../freebasic/src/zip.bas"
#include "../../../freebasic/src/json.bas"

Const MB_EXCLAMATION = 0, MB_INFO = 0
Sub MsgBox(ByRef s As String, ByVal flags As Long)
    Print s
End Sub
Function FileTitle(ByRef p As String) As String
    Return p
End Function
Function Y2KDimension() As String
    Return "19100"
End Function
Sub GrowBox(ByVal x As Double, ByVal y As Double, ByRef x0 As Double, ByRef x1 As Double, ByRef y0 As Double, ByRef y1 As Double)
    If x < x0 Then x0 = x
    If x > x1 Then x1 = x
    If y < y0 Then y0 = y
    If y > y1 Then y1 = y
End Sub
Sub TriNormal(ByRef t As TTri, ByRef nx As Double, ByRef ny As Double, ByRef nz As Double)
    Dim As Double ux = t.X2 - t.X1, uy = t.Y2 - t.Y1, uz = t.Z2 - t.Z1
    Dim As Double vx = t.X3 - t.X1, vy = t.Y3 - t.Y1, vz = t.Z3 - t.Z1
    nx = uy * vz - uz * vy: ny = uz * vx - ux * vz: nz = ux * vy - uy * vx
    Dim As Double l = Sqr(nx * nx + ny * ny + nz * nz)
    If l = 0 Then l = 1
    nx /= l: ny /= l: nz /= l
End Sub
Function Min3(ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    Dim m As Double = a
    If b < m Then m = b
    If c < m Then m = c
    Return m
End Function
#include "../../../freebasic/src/import.bas"
#include "../../../freebasic/src/stl.bas"

Dim d As TDesign
Dim path As String = Command(1), stem As String = Command(2)
If LCase(Right(path, 5)) = ".sc98" Then
    If LoadDesign(d, path) <> 0 Then End 1
Else
    If Not ImportSolidCraft(path, d) Then End 1
End If
Dim e() As TEdge, t() As TTri, message As String
Print "title "; d.Title; " features "; d.Count
Print "edges "; Regenerate(d, e())
Dim n As Long = MeshDesign(d, t(), MESH_SEGS, message)
Print "triangles "; n; " error '"; message; "'"
If Not WriteStl(t(), n, stem & ".stl", d.Title) Then End 1
If Not SaveDesign(d, stem & ".sc98") Then End 1
' Preserve every triangle's double coordinates and owning feature too.
Dim fh As Long = FreeFile
Open stem & ".tri" For Binary Access Write As #fh
For j As Long = 0 To n - 1
    With t(j)
        Put #fh, , .X1: Put #fh, , .Y1: Put #fh, , .Z1
        Put #fh, , .X2: Put #fh, , .Y2: Put #fh, , .Z2
        Put #fh, , .X3: Put #fh, , .Y3: Put #fh, , .Z3
        Put #fh, , .Body
    End With
Next
Close #fh
