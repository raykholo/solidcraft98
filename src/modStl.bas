Attribute VB_Name = "modStl"
' modStl - File > Export for Rapid Prototyping. Writes the part as a binary
' STL file, the format the stereolithography machines take: a list of
' triangles, each with its outward normal, in millimetres.
'
' The 1989 rules are kept: every triangle faces out, neighbours share whole
' edges, and everything sits in the all-positive corner of space (the part
' is moved there; slicers centre it on the bed anyway). The header must not
' begin with "solid", or some programs read the file as text.
Option Explicit

Public Sub ExportStl(p As frmPart)
    Dim slot As Integer, sPath As String, t() As TTri, n As Long, sErr As String
    slot = p.DocIndex
    n = MeshDesign(Docs(slot), t, MESH_SEGS, sErr)
    If n = 0 Then
        MsgBox "There is nothing solid to export." & vbCrLf & vbCrLf & _
            "Sketches are flat. Extrude or revolve one first.", vbExclamation, App.Title
        Exit Sub
    End If
    sPath = frmMain.AskFileName(True, RTrim$(Docs(slot).Title) & ".stl", "Stereolithography (*.stl)|*.stl", "stl")
    If Len(sPath) = 0 Then Exit Sub
    Screen.MousePointer = vbHourglass
    frmMain.SetStatus "Writing " & n & " triangles..."
    If Not WriteStl(t, n, sPath, RTrim$(Docs(slot).Title)) Then
        Screen.MousePointer = vbDefault
        Exit Sub
    End If
    Screen.MousePointer = vbDefault
    frmMain.SetStatus "Exported " & sPath & " (" & n & " triangles)"
    If Len(sErr) > 0 Then
        MsgBox "Exported " & n & " triangles, but left out: " & sErr, vbExclamation, "Export for Rapid Prototyping"
    Else
        MsgBox "Exported " & n & " triangles to" & vbCrLf & sPath & vbCrLf & vbCrLf & _
            "Send it to your service bureau. Allow 3 to 5 working days.", vbInformation, "Export for Rapid Prototyping"
    End If
End Sub

Private Function WriteStl(t() As TTri, ByVal n As Long, ByVal sPath As String, ByVal sTitle As String) As Boolean
    Dim fh As Integer, i As Long, hdr As String, mx As Double, my As Double, mz As Double
    Dim nx As Single, ny As Single, nz As Single, cnt As Long, attr As Integer
    On Error GoTo Failed
    ' the lowest corner, so everything can be moved to x, y, z >= 0
    mx = t(0).X1: my = t(0).Y1: mz = t(0).Z1
    For i = 0 To n - 1
        With t(i)
            mx = Min3(mx, .X1, .X2, .X3)
            my = Min3(my, .Y1, .Y2, .Y3)
            mz = Min3(mz, .Z1, .Z2, .Z3)
        End With
    Next i
    hdr = Left$("Binary STL from SolidCraft 98: " & sTitle & ", mm" & Space$(80), 80)
    If FileExists(sPath) Then Kill sPath
    fh = FreeFile
    Open sPath For Binary Access Write As #fh
    Put #fh, 1, hdr
    cnt = n
    Put #fh, , cnt
    For i = 0 To n - 1
        With t(i)
            UnitNormal .X2 - .X1, .Y2 - .Y1, .Z2 - .Z1, .X3 - .X1, .Y3 - .Y1, .Z3 - .Z1, nx, ny, nz
            Put #fh, , nx: Put #fh, , ny: Put #fh, , nz
            PutPoint fh, .X1 - mx, .Y1 - my, .Z1 - mz
            PutPoint fh, .X2 - mx, .Y2 - my, .Z2 - mz
            PutPoint fh, .X3 - mx, .Y3 - my, .Z3 - mz
            Put #fh, , attr
        End With
        If i Mod 2000 = 0 Then DoEvents
    Next i
    Close #fh
    WriteStl = True
    Exit Function
Failed:
    Dim sMsg As String
    sMsg = Err.Description
    If fh <> 0 Then Close #fh
    MsgBox "Could not write " & sPath & vbCrLf & vbCrLf & sMsg, vbCritical, App.Title
End Function

Private Sub PutPoint(ByVal fh As Integer, ByVal x As Double, ByVal y As Double, ByVal z As Double)
    Dim sx As Single, sy As Single, sz As Single
    sx = x: sy = y: sz = z
    Put #fh, , sx: Put #fh, , sy: Put #fh, , sz
End Sub

Private Sub UnitNormal(ByVal ax As Double, ByVal ay As Double, ByVal az As Double, _
                       ByVal bx As Double, ByVal by As Double, ByVal bz As Double, _
                       nx As Single, ny As Single, nz As Single)
    Dim cx As Double, cy As Double, cz As Double, l As Double
    cx = ay * bz - az * by
    cy = az * bx - ax * bz
    cz = ax * by - ay * bx
    l = Sqr(cx * cx + cy * cy + cz * cz)
    If l = 0 Then l = 1
    nx = cx / l: ny = cy / l: nz = cz / l
End Sub

Private Function Min3(ByVal m As Double, ByVal a As Double, ByVal b As Double, ByVal c As Double) As Double
    If a < m Then m = a
    If b < m Then m = b
    If c < m Then m = c
    Min3 = m
End Function
