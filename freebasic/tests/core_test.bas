' Headless test of the geometry: load a part, regenerate, mesh, STL, render.
#include "fbgfx.bi"
#include "dir.bi"
#include "../src/font.bi"
#include "../src/icons.bi"
#include "../src/gfx.bas"
#include "../src/model.bas"
#include "../src/kernel.bas"
#include "../src/view.bas"
#include "../src/mesh.bas"
#include "../src/shade.bas"
#include "../src/expr.bas"
#include "../src/stl.bas"
Function Y2KDimension() As String
    Return "19100"
End Function

ScreenControl FB.SET_DRIVER_NAME, "null"
ScreenRes 640, 480, 32
Dim d As TDesign
Dim r As Long = LoadDesign(d, "tests/Mounting Plate.sc98")
Print "load"; r; " title "; d.Title; " count"; d.Count
Dim i As Long
For i = 1 To d.Count
    Print i; " "; d.F(i).Name; " | "; KindName(d.F(i).Kind); " | "; Describe(d, i); " | ok "; RefOk(d, i)
Next
Dim e() As TEdge
Dim ne As Long = Regenerate(d, e())
Print "edges"; ne
Dim t() As TTri, sErr As String
Dim nt As Long = MeshDesign(d, t(), MESH_SEGS, sErr)
Print "tris"; nt; " err '"; sErr; "'"
Print "stl "; WriteStl(t(), nt, "tests/out/plate.stl", d.Title)
Print "save "; SaveDesign(d, "tests/out/resaved.sc98")
' render wireframe and shaded
Dim v As TView
ResetView v
Dim img As Any Ptr = ImageCreate(480, 320, 0, 32)
SurfFromImage S, img
FitView v, 480, 320, @e(0), ne
DrawScene v, 480, 320, @e(0), ne
Text 6, 4, ne & " edges", &hFF404040
BSave "tests/out/wire.bmp", img
Dim t2() As TTri, g() As Long
Dim n2 As Long = MeshDesign(d, t2(), 32, sErr)
FaceGroups t2(), n2, g()
DrawScene v, 480, 320, @e(0), 0
RenderShaded v, @t2(0), n2, @g(0), d
Text 6, 4, "Shaded, " & n2 & " triangles", &hFF404040
BSave "tests/out/shaded.bmp", img
' expressions
Dim ex As String
For Each_ As Long = 0 To 0
Next
Dim tests(5) As String = {"40/2+5", "(10+2)*3", "-8", "20mm", "40/0", ""}
For i = 0 To 5
    Dim vv As Double = Evaluate(tests(i))
    Print "eval '"; tests(i); "' = "; vv; " err"; exErr
Next
