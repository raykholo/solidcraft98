Attribute VB_Name = "modTutor"
' modTutor - the help the remote control gives whoever drives it. "how
' <words>" looks the words up in a small help index, and every "look" ends
' with a tutor line saying what to do here, like a screen reader's tutor
' messages. When there's one obvious next step, it's offered, and "yes"
' takes it.
Option Explicit

Private mKeys() As String
Private mText() As String
Private mStep() As String
Private mN As Long

Private Sub Topic(ByVal sKeys As String, ByVal sText As String, ByVal sStep As String)
    ReDim Preserve mKeys(0 To mN): ReDim Preserve mText(0 To mN): ReDim Preserve mStep(0 To mN)
    mKeys(mN) = " " & sKeys & " ": mText(mN) = sText: mStep(mN) = sStep
    mN = mN + 1
End Sub

Private Sub LoadTopics()
    If mN Then Exit Sub
    Topic "box cube block plate brick rectangle rectangular square slab", "A box, cube, block or plate: menu Sketch > Rectangle... (key r). Type the Width, key tab, the Height, key enter. Then menu Features > Extrude... (key e), type the thickness, key enter. A cube has all three the same.", "menu Sketch > Rectangle..."
    Topic "cylinder cylindrical rod disc disk circle shaft peg tube diameter", "A cylinder or disc: menu Sketch > Circle... (key c). Type the Radius, which is half the diameter, key enter. Then menu Features > Extrude... (key e), type the height, key enter.", "menu Sketch > Circle..."
    Topic "hole holes drill drilled bore through", "A hole: make the solid first. Then menu Features > Hole... (key h): Diameter, key tab, Depth (0 goes all the way through), key tab, Centre X, key tab, Centre Y, key enter. One hole each time. Centre X and Y are measured from the origin (0, 0), not from a corner.", "menu Features > Hole..."
    Topic "extrude extrusion solid thick thickness thicken pull", "Extrude makes the last sketch solid: menu Features > Extrude... (key e), type the depth, key enter.", "menu Features > Extrude..."
    Topic "revolve revolved lathe turn turned spin vase", "Revolve spins the last sketch around the Y axis: menu Features > Revolve... (key v), type the angle (360 for all the way), key enter. The sketch has to be all on one side of X = 0.", "menu Features > Revolve..."
    Topic "fillet fillets round rounded rounding chamfer bevel radius edge edges corner corners blend", "SolidCraft 98 can't round or chamfer the edges of a solid. It can round the four corners of a rectangle sketch: dblclick the sketch in the timeline, key tab to Corner radius, type the radius, key enter. That rounds the four upright edges, not the top and bottom ones.", "dblclick Sketch1"
    Topic "move moving translate shift position place offset along axis", "To move a part, move the sketch it grew from: dblclick the sketch in the timeline and change Corner X and Corner Y (Centre X and Y for a circle), then key enter. Everything built on it follows.", "dblclick Sketch1"
    Topic "edit change changing modify resize size bigger smaller taller shorter thicker thinner longer wider dimension", "To change a feature: dblclick it in the timeline (or click it and key enter). The same dialog comes back with its numbers in it. Change them and key enter.", ""
    Topic "rename name names named call label", "SolidCraft 98 names features itself: Sketch1, Extrude1 and so on. They can't be renamed. The part takes the name of the file it's saved as: menu File > Save As...", "menu File > Save As..."
    Topic "volume mass weight area measure measurement properties big much", "SolidCraft 98 doesn't measure parts. Work it out from the numbers in the timeline: a box is width x height x depth; a cylinder is 3.1416 x radius x radius x height; a through hole takes away 3.1416 x (diameter / 2) x (diameter / 2) x the thickness.", ""
    Topic "undo delete remove mistake back oops", "menu Edit > Undo Last Feature (key ctrl+z) takes off the last feature added. To delete any feature, click it in the timeline and key del.", ""
    Topic "save open new file export stl print", "menu File > Save (key ctrl+s), Open (key ctrl+o), New (key ctrl+n). menu File > Export for Rapid Prototyping... makes an STL file for a 3D printer.", ""
    Topic "view shade shaded look see iso isometric zoom rotate orbit fit", "key s shades the part (again for wireframe), key i is the isometric view, key f zooms to fit. Drag in the view to turn it.", ""
    Topic "dialog field fields number numbers type typing tab enter ok cancel units", "In a dialog, the field with the focus is all selected, so typing replaces it. key tab goes to the next field, key enter is OK, key esc is Cancel. Numbers only: 20, not 20mm. Number boxes do sums: 80/2 is 40.", ""
    Topic "top stack stacked boss onto sit sits", "To put a sketch on top of a solid, set On feature # in the sketch dialog to the solid's number in the timeline's # column. It sits on that solid's top face.", ""
End Sub

' The topic that shares the most words with these, or -1.
Public Function BestTopic(ByVal sWords As String) As Long
    Dim w() As String, i As Long, k As Long, n As Long, best As Long, s As String
    LoadTopics
    s = LCase$(sWords)
    For i = 1 To Len(s)
        If InStr("abcdefghijklmnopqrstuvwxyz0123456789", Mid$(s, i, 1)) = 0 Then Mid$(s, i, 1) = " "
    Next i
    w = Split(s, " ")
    BestTopic = -1
    For k = 0 To mN - 1
        n = 0
        For i = 0 To UBound(w)
            If Len(w(i)) > 1 Then
                If InStr(mKeys(k), " " & w(i) & " ") Then
                    n = n + 1
                ElseIf Right$(w(i), 1) = "s" Then
                    If InStr(mKeys(k), " " & Left$(w(i), Len(w(i)) - 1) & " ") Then n = n + 1
                End If
            End If
        Next i
        If n > best Then best = n: BestTopic = k
    Next k
End Function

Public Function TopicText(ByVal k As Long) As String
    LoadTopics
    TopicText = mText(k)
End Function

Public Function TopicStep(ByVal k As Long) As String
    LoadTopics
    TopicStep = mStep(k)
End Function

' "box, cylinder, hole, ...": the first word of each topic.
Public Function TopicList() As String
    Dim k As Long, s As String
    LoadTopics
    For k = 0 To mN - 1
        s = s & IIf(k, ", ", "") & Split(Trim$(mKeys(k)), " ")(0)
    Next k
    TopicList = s
End Function

' How many letters to add, drop or change to turn a into b.
Public Function EditDistance(ByVal a As String, ByVal b As String) As Long
    Dim d() As Long, i As Long, j As Long, c As Long
    ReDim d(0 To Len(a), 0 To Len(b))
    For i = 0 To Len(a): d(i, 0) = i: Next i
    For j = 0 To Len(b): d(0, j) = j: Next j
    For i = 1 To Len(a)
        For j = 1 To Len(b)
            c = IIf(Mid$(a, i, 1) = Mid$(b, j, 1), 0, 1)
            d(i, j) = d(i - 1, j - 1) + c
            If d(i - 1, j) + 1 < d(i, j) Then d(i, j) = d(i - 1, j) + 1
            If d(i, j - 1) + 1 < d(i, j) Then d(i, j) = d(i, j - 1) + 1
        Next j
    Next i
    EditDistance = d(Len(a), Len(b))
End Function

' Near enough to be what they meant: one inside the other, or a slip of a
' few letters.
Public Function LooksLike(ByVal want As String, ByVal have As String) As Boolean
    If Len(want) = 0 Or Len(have) = 0 Then Exit Function
    If InStr(have, want) > 0 Or InStr(want, have) > 0 Then LooksLike = True: Exit Function
    LooksLike = EditDistance(want, have) <= IIf(Len(want) > 6, 2, 1)
End Function
