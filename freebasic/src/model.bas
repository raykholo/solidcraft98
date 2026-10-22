' model.bas - the design, and the .sc98 file.
'
' The file is byte for byte what the Windows version writes with Put: a
' 72-byte header, then 64 feature records of 134 bytes, little-endian, VB
' 16-bit Integers and 8-byte Doubles, fixed strings padded with spaces.
' Parts move freely between the two versions. Versions 3 and 4 (smaller
' records) are read and converted, as the Windows version does.

Const FILE_MAGIC = "SC98"
Const FILE_VERSION = 5
Const MAX_FEATURES = 64            ' someone once had 41 features

Const FK_NONE = 0
Const FK_SKETCH_RECT = 1
Const FK_SKETCH_CIRCLE = 2
Const FK_EXTRUDE = 3
Const FK_REVOLVE = 4
Const FK_HOLE = 5
Const FK_FOREIGN = 9               ' from a SolidCraft design, and not something SolidCraft 98 can build

Type TFeature
    Kind As Long
    Name As String
    X As Double                    ' sketch origin / hole centre, mm
    Y As Double
    Z As Double                    ' sketch plane height, mm
    P1 As Double                   ' width | radius | depth | angle | diameter
    P2 As Double                   ' height | - | - | - | hole depth (0 = through all)
    Ref As Long                    ' the feature this one is built on
    Suppressed As Long
    P3 As Double                   ' rectangle corner radius
    Info As String                 ' FK_FOREIGN: what the feature was in SolidCraft ("fillet")
End Type

Type TDesign
    Title As String
    Count As Long
    F(1 To MAX_FEATURES) As TFeature
End Type

Declare Function Y2KDimension() As String
Dim Shared Y2KHappened As Boolean

Sub NewDesign(ByRef d As TDesign, ByRef sTitle As String)
    Dim i As Long, blank As TFeature
    d.Title = sTitle
    d.Count = 0
    For i = 1 To MAX_FEATURES
        d.F(i) = blank
    Next i
End Sub

Function KindName(ByVal k As Long) As String
    Select Case k
    Case FK_SKETCH_RECT: Return "Sketch (Rectangle)"
    Case FK_SKETCH_CIRCLE: Return "Sketch (Circle)"
    Case FK_EXTRUDE: Return "Extrude"
    Case FK_REVOLVE: Return "Revolve"
    Case FK_HOLE: Return "Hole"
    Case FK_FOREIGN: Return "SolidCraft"
    End Select
    Return "?"
End Function

Function KindPrefix(ByVal k As Long) As String
    Select Case k
    Case FK_SKETCH_RECT, FK_SKETCH_CIRCLE: Return "Sketch"
    Case FK_EXTRUDE: Return "Extrude"
    Case FK_REVOLVE: Return "Revolve"
    Case FK_HOLE: Return "Hole"
    End Select
    Return ""
End Function

Function IsSketch(ByVal k As Long) As Boolean
    Return k = FK_SKETCH_RECT Or k = FK_SKETCH_CIRCLE
End Function

' Adds a feature and gives it a name like "Extrude2". Returns its index, 0 if full.
Function AddFeature(ByRef d As TDesign, ByRef f As TFeature) As Long
    Dim As Long i, n
    If d.Count >= MAX_FEATURES Then Return 0
    For i = 1 To d.Count
        If KindPrefix(d.F(i).Kind) = KindPrefix(f.Kind) Then n += 1
    Next i
    d.Count += 1
    f.Name = KindPrefix(f.Kind) & (n + 1)
    d.F(d.Count) = f
    Return d.Count
End Function

Function FeatureName(ByRef d As TDesign, ByVal i As Long) As String
    If i < 1 Or i > d.Count Then Return ""
    Return d.F(i).Name
End Function

' The last sketch nobody has used yet, for Extrude and Revolve.
Function LastFreeSketch(ByRef d As TDesign) As Long
    Dim As Long i, j
    For i = d.Count To 1 Step -1
        If IsSketch(d.F(i).Kind) Then
            Dim used As Boolean = False
            For j = i + 1 To d.Count
                If d.F(j).Ref = i And (d.F(j).Kind = FK_EXTRUDE Or d.F(j).Kind = FK_REVOLVE) Then used = True
            Next j
            If Not used Then Return i
        End If
    Next i
    Return 0
End Function

' The last extrude, the default place for a hole.
Function LastSolid(ByRef d As TDesign) As Long
    Dim i As Long
    For i = d.Count To 1 Step -1
        If d.F(i).Kind = FK_EXTRUDE Then Return i
    Next i
    Return 0
End Function

' Marks feature i and everything built on it, directly or not. Returns how many.
Function MarkDependents(ByRef d As TDesign, ByVal i As Long, gone() As Boolean) As Long
    Dim As Long j, n = 1
    ReDim gone(0 To d.Count)
    gone(i) = True
    For j = i + 1 To d.Count
        If d.F(j).Ref >= 1 And d.F(j).Ref <= d.Count Then
            If gone(d.F(j).Ref) Then gone(j) = True: n += 1
        End If
    Next j
    Return n
End Function

' Removes the marked features and renumbers what the rest refer to.
Sub DeleteMarked(ByRef d As TDesign, gone() As Boolean)
    Dim As Long i, n
    Dim newIndex(0 To d.Count) As Long
    Dim blank As TFeature
    For i = 1 To d.Count
        If Not gone(i) Then
            n += 1
            newIndex(i) = n
            d.F(n) = d.F(i)
            If d.F(n).Ref >= 1 Then d.F(n).Ref = newIndex(d.F(n).Ref)
        End If
    Next i
    For i = n + 1 To d.Count
        d.F(i) = blank
    Next i
    d.Count = n
End Sub

' 12.5 -> "12.5", 3 -> "3", -0.001 -> "0": two decimals at most.
Function FmtN(ByVal v As Double, ByVal places As Long) As String
    Dim As Double m = 10 ^ places
    Dim As Double r = Int(Abs(v) * m + 0.5) / m
    Dim As String s = Str(r)
    If InStr(s, "e") Or InStr(s, "E") Then s = Str(CLngInt(r))  ' tiny values print as 1e-05
    If InStr(s, ".") Then
        Dim As Long dp = InStr(s, ".")
        If Len(s) - dp > places Then s = Left(s, dp + places)
        Do While Right(s, 1) = "0": s = Left(s, Len(s) - 1): Loop
        If Right(s, 1) = "." Then s = Left(s, Len(s) - 1)
    End If
    If v < 0 And s <> "0" Then s = "-" & s
    Return s
End Function

Function Fmt(ByVal v As Double) As String
    If Y2KHappened Then Return Y2KDimension()      ' two-digit years were a mistake
    Return FmtN(v, 2)
End Function

Function Fmt0(ByVal v As Double) As String
    Return FmtN(v, 3)
End Function

'  ", on Extrude1" / ", on Extrude1 +2" / ", Z 5" / "" for where a sketch sits.
Function SketchPlace(ByRef d As TDesign, ByRef f As TFeature) As String
    If f.Ref > 0 Then
        Dim s As String = ", on " & FeatureName(d, f.Ref)
        If f.Z <> 0 Then s &= IIf(f.Z > 0, " +", " ") & Fmt(f.Z)
        Return s
    ElseIf f.Z <> 0 Then
        Return ", Z " & Fmt(f.Z)
    End If
    Return ""
End Function

Function Describe(ByRef d As TDesign, ByVal i As Long) As String
    Dim As String s
    With d.F(i)
        Select Case .Kind
        Case FK_SKETCH_RECT
            s = Fmt(.P1) & " x " & Fmt(.P2) & " mm at (" & Fmt(.X) & ", " & Fmt(.Y) & ")"
            If .P3 > 0 Then s &= ", R" & Fmt(.P3) & " corners"
            s &= SketchPlace(d, d.F(i))
        Case FK_SKETCH_CIRCLE
            s = "R " & Fmt(.P1) & " mm at (" & Fmt(.X) & ", " & Fmt(.Y) & ")" & SketchPlace(d, d.F(i))
        Case FK_EXTRUDE
            s = FeatureName(d, .Ref) & ", " & Fmt(.P1) & " mm"
        Case FK_REVOLVE
            s = FeatureName(d, .Ref) & ", " & Fmt(.P1) & Chr(176) & " about Y"
        Case FK_FOREIGN
            s = "From SolidCraft. Not in SolidCraft 98."
        Case FK_HOLE
            s = "D " & Fmt(.P1) & " mm on " & FeatureName(d, .Ref) & " top face, "
            If .P2 <= 0 Then s &= "through all" Else s &= Fmt(.P2) & " mm deep"
        End Select
    End With
    Return s
End Function

' ---- Save and Open, byte-compatible with the Windows version ----

' Fixed-length string field: the text, cut or padded with spaces to n bytes;
' an empty one is NULs, as VB leaves a fixed string nobody assigned.
Function FixStr(ByRef t As String, ByVal n As Long) As String
    If Len(t) = 0 Then Return String(n, 0)      ' never assigned in VB: NULs
    Return Left(t & Space(n), n)
End Function

' A fixed string field read back: trailing spaces and NULs dropped.
Function UnFix(ByRef t As String) As String
    Dim As Long n = Len(t)
    Do While n > 0 AndAlso (t[n - 1] = 32 Or t[n - 1] = 0)
        n -= 1
    Loop
    Return Left(t, n)
End Function

Dim Shared LastFileError As String

' Returns True on success; LastFileError says what went wrong otherwise.
Function SaveDesign(ByRef d As TDesign, ByRef sPath As String) As Boolean
    Dim As Long fh, i
    Dim As Short sh
    Dim As Double z = 0
    LastFileError = ""
    If Len(Dir(sPath)) Then
        If Kill(sPath) <> 0 Then LastFileError = "Permission denied" & Chr(10) & "(While replacing the old file: " & sPath & ")": Return False
    End If
    fh = FreeFile
    If Open(sPath For Binary Access Write As #fh) <> 0 Then
        LastFileError = "Path/File access error" & Chr(10) & "(While creating the file: " & sPath & ")"
        Return False
    End If
    Put #fh, , FixStr(FILE_MAGIC, 4)
    sh = FILE_VERSION: Put #fh, , sh
    Put #fh, , FixStr(d.Title, 64)
    sh = d.Count: Put #fh, , sh
    For i = 1 To MAX_FEATURES
        With d.F(i)
            sh = .Kind: Put #fh, , sh
            Put #fh, , FixStr(.Name, 24)
            Put #fh, , .X: Put #fh, , .Y: Put #fh, , .Z: Put #fh, , .P1: Put #fh, , .P2
            sh = .Ref: Put #fh, , sh
            sh = .Suppressed: Put #fh, , sh
            Put #fh, , .P3
            Put #fh, , FixStr(.Info, 32)
            Put #fh, , z: Put #fh, , z: Put #fh, , z
        End With
    Next i
    Close #fh
    Return True
End Function

Function GetFix(ByVal fh As Long, ByVal n As Long) As String
    Dim As String s = Space(n)
    Get #fh, , s
    Return UnFix(s)
End Function

Function GetShort(ByVal fh As Long) As Long
    Dim As Short v
    Get #fh, , v
    Return v
End Function

Function GetDbl(ByVal fh As Long) As Double
    Dim As Double v
    Get #fh, , v
    Return v
End Function

' Returns 0 on success, 1 not a part, 2 too new, 3 too old, 4 couldn't read,
' 5 converted from version 3 (say so). LastFileError has the message.
Function LoadDesign(ByRef d As TDesign, ByRef sPath As String) As Long
    Dim As Long fh, i, ver, cnt
    Dim As Double dummy
    fh = FreeFile
    If Open(sPath For Binary Access Read As #fh) <> 0 Then
        LastFileError = "File not found: " & sPath
        Return 4
    End If
    Dim As String magic = GetFix(fh, 4)
    If magic <> FILE_MAGIC Then
        Close #fh
        LastFileError = "'" & sPath & "' is not a SolidCraft 98 part."
        Return 1
    End If
    ver = GetShort(fh)
    If ver > FILE_VERSION Then
        Close #fh
        LastFileError = "This file was saved by a newer version of SolidCraft." & Chr(10) & Chr(10) & "Please upgrade to SolidCraft 98 Second Edition."
        Return 2
    End If
    If ver < 3 Then
        Close #fh
        LastFileError = "This file was saved by an older version of SolidCraft." & Chr(10) & Chr(10) & "Versions before 3 are not supported. They never were."
        Return 3
    End If
    NewDesign d, GetFix(fh, 64)
    cnt = GetShort(fh)
    If cnt < 0 Or cnt > MAX_FEATURES Then cnt = 0
    For i = 1 To MAX_FEATURES
        With d.F(i)
            .Kind = GetShort(fh)
            .Name = GetFix(fh, 24)
            .X = GetDbl(fh): .Y = GetDbl(fh): .Z = GetDbl(fh): .P1 = GetDbl(fh): .P2 = GetDbl(fh)
            .Ref = GetShort(fh)
            .Suppressed = GetShort(fh)
            If ver >= 4 Then .P3 = GetDbl(fh)
            If ver >= 5 Then .Info = GetFix(fh, 32)
            If ver >= 4 Then dummy = GetDbl(fh): dummy = GetDbl(fh): dummy = GetDbl(fh)
        End With
    Next i
    Close #fh
    d.Count = cnt
    For i = cnt + 1 To MAX_FEATURES
        d.F(i).Kind = FK_NONE
    Next i
    If ver = 3 Then
        LastFileError = "This file was saved by an older version of SolidCraft." & Chr(10) & Chr(10) & _
            "It has been converted. Save it to keep the new format." & Chr(10) & "(This has never happened before.)"
        Return 5
    End If
    Return 0
End Function
