' tutor.bas - the help the remote control gives whoever drives it. "how
' <words>" looks the words up in a small help index, and every "look" ends
' with a tutor line saying what to do here, like a screen reader's tutor
' messages. When there's one obvious next step, it's offered, and "yes"
' takes it.

Dim Shared TopicKeys(0 To 31) As String
Dim Shared TopicTexts(0 To 31) As String
Dim Shared TopicSteps(0 To 31) As String
Dim Shared TopicN As Long

Sub TutorTopic(ByRef k As String, ByRef t As String, ByRef s As String)
    TopicKeys(TopicN) = " " & k & " ": TopicTexts(TopicN) = t: TopicSteps(TopicN) = s
    TopicN += 1
End Sub

Sub LoadTopics()
    If TopicN Then Exit Sub
    TutorTopic "box cube block plate brick rectangle rectangular square slab", "A box, cube, block or plate: menu Sketch > Rectangle... (key r). Type the Width, key tab, the Height, key enter. Then menu Features > Extrude... (key e), type the thickness, key enter. A cube has all three the same.", "menu Sketch > Rectangle..."
    TutorTopic "cylinder cylindrical rod disc disk circle shaft peg tube diameter", "A cylinder or disc: menu Sketch > Circle... (key c). Type the Radius, which is half the diameter, key enter. Then menu Features > Extrude... (key e), type the height, key enter.", "menu Sketch > Circle..."
    TutorTopic "hole holes drill drilled bore through", "A hole: make the solid first. Then menu Features > Hole... (key h): Diameter, key tab, Depth (0 goes all the way through), key tab, Centre X, key tab, Centre Y, key enter. One hole each time. Centre X and Y are measured from the origin (0, 0), not from a corner.", "menu Features > Hole..."
    TutorTopic "extrude extrusion solid thick thickness thicken pull", "Extrude makes the last sketch solid: menu Features > Extrude... (key e), type the depth, key enter.", "menu Features > Extrude..."
    TutorTopic "revolve revolved lathe turn turned spin vase", "Revolve spins the last sketch around the Y axis: menu Features > Revolve... (key v), type the angle (360 for all the way), key enter. The sketch has to be all on one side of X = 0.", "menu Features > Revolve..."
    TutorTopic "fillet fillets round rounded rounding chamfer bevel radius edge edges corner corners blend", "SolidCraft 98 can't round or chamfer the edges of a solid. It can round the four corners of a rectangle sketch: dblclick the sketch in the timeline, key tab to Corner radius, type the radius, key enter. That rounds the four upright edges, not the top and bottom ones.", "dblclick Sketch1"
    TutorTopic "move moving translate shift position place offset along axis", "To move a part, move the sketch it grew from: dblclick the sketch in the timeline and change Corner X and Corner Y (Centre X and Y for a circle), then key enter. Everything built on it follows.", "dblclick Sketch1"
    TutorTopic "edit change changing modify resize size bigger smaller taller shorter thicker thinner longer wider dimension", "To change a feature: dblclick it in the timeline (or click it and key enter). The same dialog comes back with its numbers in it. Change them and key enter.", ""
    TutorTopic "rename name names named call label", "SolidCraft 98 names features and bodies itself: Sketch1, Extrude1 and so on. Nothing can be renamed, so tell the user it can't be done. (A part takes the name of the file it's saved as, but that's the file, not the body.)", ""
    TutorTopic "volume mass weight area measure measurement properties big much", "SolidCraft 98 doesn't measure parts. Work it out from the numbers in the timeline: a box is width x height x depth; a cylinder is 3.1416 x radius x radius x height; a through hole takes away 3.1416 x (diameter / 2) x (diameter / 2) x the thickness.", ""
    TutorTopic "undo delete remove mistake back oops", "menu Edit > Undo Last Feature (key ctrl+z) takes off the last feature added. To delete any feature, click it in the timeline and key del.", ""
    TutorTopic "save open new file export stl print", "menu File > Save (key ctrl+s), Open (key ctrl+o), New (key ctrl+n). menu File > Export for Rapid Prototyping... makes an STL file for a 3D printer.", ""
    TutorTopic "view shade shaded look see iso isometric zoom rotate orbit fit", "key s shades the part (again for wireframe), key i is the isometric view, key f zooms to fit. Drag in the view to turn it.", ""
    TutorTopic "dialog field fields number numbers type typing tab enter ok cancel units", "In a dialog, the field with the focus is all selected, so typing replaces it. key tab goes to the next field, key enter is OK, key esc is Cancel. Numbers only: 20, not 20mm. Number boxes do sums: 80/2 is 40.", ""
    TutorTopic "top stack stacked boss onto sit sits", "To put a sketch on top of a solid, set On feature # in the sketch dialog to the solid's number in the timeline's # column. It sits on that solid's top face.", ""
End Sub

' The topic that shares the most words with these, or -1.
Function BestTopic(ByRef words As String) As Long
    Dim As String s = LCase(words)
    Dim As Long i, k, n, best = 0, bestK = -1
    LoadTopics
    For i = 1 To Len(s)
        If InStr("abcdefghijklmnopqrstuvwxyz0123456789", Mid(s, i, 1)) = 0 Then Mid(s, i, 1) = " "
    Next
    For k = 0 To TopicN - 1
        n = 0
        Dim As String rest = s & " "
        Do
            rest = LTrim(rest)
            Dim As Long sp = InStr(rest, " ")
            If sp = 0 Then Exit Do
            Dim As String w = Left(rest, sp - 1)
            rest = Mid(rest, sp + 1)
            If Len(w) > 1 Then
                If InStr(TopicKeys(k), " " & w & " ") Then
                    n += 1
                ElseIf Right(w, 1) = "s" AndAlso InStr(TopicKeys(k), " " & Left(w, Len(w) - 1) & " ") Then
                    n += 1
                End If
            End If
        Loop
        If n > best Then best = n: bestK = k
    Next
    Return bestK
End Function

' "box, cylinder, hole, ...": the first word of each topic.
Function TopicList() As String
    Dim As String s
    LoadTopics
    For k As Long = 0 To TopicN - 1
        Dim As String t = Trim(TopicKeys(k))
        s &= IIf(k, ", ", "") & Left(t, InStr(t & " ", " ") - 1)
    Next
    Return s
End Function

' How many letters to add, drop or change to turn a into b.
Function EditDistance(ByRef a As String, ByRef b As String) As Long
    Dim As Long la = Len(a), lb = Len(b), i, j
    Dim d(0 To la, 0 To lb) As Long
    For i = 0 To la: d(i, 0) = i: Next
    For j = 0 To lb: d(0, j) = j: Next
    For i = 1 To la
        For j = 1 To lb
            d(i, j) = d(i - 1, j - 1) + IIf(Mid(a, i, 1) = Mid(b, j, 1), 0, 1)
            If d(i - 1, j) + 1 < d(i, j) Then d(i, j) = d(i - 1, j) + 1
            If d(i, j - 1) + 1 < d(i, j) Then d(i, j) = d(i, j - 1) + 1
        Next
    Next
    Return d(la, lb)
End Function

' Near enough to be what they meant: one inside the other, or a slip of a
' few letters.
Function LooksLike(ByRef want As String, ByRef have As String) As Boolean
    If Len(want) = 0 Or Len(have) = 0 Then Return False
    If InStr(have, want) > 0 Or InStr(want, have) > 0 Then Return True
    Return EditDistance(want, have) <= IIf(Len(want) > 6, 2, 1)
End Function
