Attribute VB_Name = "modModel"
' modModel - the design, as one Type you can Put straight to disk.
'
' The file format IS this Type. Change a field and every older file breaks,
' which is why FILE_VERSION exists and why the "migration system" is a MsgBox.
Option Explicit

Public Const FILE_MAGIC As String = "SC98"
Public Const FILE_VERSION As Integer = 4
Public Const MAX_FEATURES As Integer = 64    ' someone once had 41 features

Public Const FK_NONE As Integer = 0
Public Const FK_SKETCH_RECT As Integer = 1
Public Const FK_SKETCH_CIRCLE As Integer = 2
Public Const FK_EXTRUDE As Integer = 3
Public Const FK_REVOLVE As Integer = 4
Public Const FK_HOLE As Integer = 5

Public Type TFeature
    Kind As Integer
    Name As String * 24
    X As Double            ' sketch origin / hole centre, mm
    Y As Double
    Z As Double            ' sketch plane height, mm
    P1 As Double           ' width | radius | depth | angle | diameter
    P2 As Double           ' height | - | - | - | hole depth (0 = through all)
    Ref As Integer         ' the feature this one is built on
    Suppressed As Integer
    P3 As Double           ' rectangle corner radius
    Reserved(1 To 3) As Double   ' so the next version won't break every file (it will anyway)
End Type

' Version 3 files, from before corner radii. Read and converted on Open.
Private Type TFeatureV3
    Kind As Integer
    Name As String * 24
    X As Double
    Y As Double
    Z As Double
    P1 As Double
    P2 As Double
    Ref As Integer
    Suppressed As Integer
End Type

Private Type TDesignV3
    Magic As String * 4
    Version As Integer
    Title As String * 64
    Count As Integer
    Features(1 To MAX_FEATURES) As TFeatureV3
End Type

Public Type TFileHeader
    Magic As String * 4
    Version As Integer
End Type

Public Type TDesign
    Magic As String * 4
    Version As Integer
    Title As String * 64
    Count As Integer
    Features(1 To MAX_FEATURES) As TFeature
End Type

Public Sub NewDesign(d As TDesign, ByVal sTitle As String)
    Dim i As Integer
    d.Magic = FILE_MAGIC
    d.Version = FILE_VERSION
    d.Title = sTitle
    d.Count = 0
    For i = 1 To MAX_FEATURES
        d.Features(i).Kind = FK_NONE
    Next i
End Sub

Public Function KindName(ByVal k As Integer) As String
    Select Case k
    Case FK_SKETCH_RECT: KindName = "Sketch (Rectangle)"
    Case FK_SKETCH_CIRCLE: KindName = "Sketch (Circle)"
    Case FK_EXTRUDE: KindName = "Extrude"
    Case FK_REVOLVE: KindName = "Revolve"
    Case FK_HOLE: KindName = "Hole"
    Case Else: KindName = "?"
    End Select
End Function

Public Function KindPrefix(ByVal k As Integer) As String
    Select Case k
    Case FK_SKETCH_RECT, FK_SKETCH_CIRCLE: KindPrefix = "Sketch"
    Case FK_EXTRUDE: KindPrefix = "Extrude"
    Case FK_REVOLVE: KindPrefix = "Revolve"
    Case FK_HOLE: KindPrefix = "Hole"
    End Select
End Function

Public Function IsSketch(ByVal k As Integer) As Boolean
    IsSketch = (k = FK_SKETCH_RECT Or k = FK_SKETCH_CIRCLE)
End Function

' Adds a feature and gives it a name like "Extrude2". Returns its index, 0 if full.
Public Function AddFeature(d As TDesign, f As TFeature) As Integer
    Dim i As Integer, n As Integer
    If d.Count >= MAX_FEATURES Then
        AddFeature = 0
        Exit Function
    End If
    For i = 1 To d.Count
        If KindPrefix(d.Features(i).Kind) = KindPrefix(f.Kind) Then n = n + 1
    Next i
    d.Count = d.Count + 1
    f.Name = KindPrefix(f.Kind) & CStr(n + 1)
    d.Features(d.Count) = f
    AddFeature = d.Count
End Function

Public Function FeatureName(d As TDesign, ByVal i As Integer) As String
    If i < 1 Or i > d.Count Then Exit Function
    FeatureName = RTrim$(d.Features(i).Name)
End Function

' The last sketch nobody has used yet, for Extrude and Revolve.
Public Function LastFreeSketch(d As TDesign) As Integer
    Dim i As Integer, j As Integer, used As Boolean
    For i = d.Count To 1 Step -1
        If IsSketch(d.Features(i).Kind) Then
            used = False
            For j = i + 1 To d.Count
                If d.Features(j).Ref = i And (d.Features(j).Kind = FK_EXTRUDE Or d.Features(j).Kind = FK_REVOLVE) Then used = True
            Next j
            If Not used Then
                LastFreeSketch = i
                Exit Function
            End If
        End If
    Next i
End Function

' The last extrude, the default place for a hole.
Public Function LastSolid(d As TDesign) As Integer
    Dim i As Integer
    For i = d.Count To 1 Step -1
        If d.Features(i).Kind = FK_EXTRUDE Then
            LastSolid = i
            Exit Function
        End If
    Next i
End Function

' Marks feature i and everything built on it, directly or not. Returns how many.
Public Function MarkDependents(d As TDesign, ByVal i As Integer, gone() As Boolean) As Integer
    Dim j As Integer
    ReDim gone(0 To d.Count)
    gone(i) = True
    MarkDependents = 1
    For j = i + 1 To d.Count
        If d.Features(j).Ref >= 1 And d.Features(j).Ref <= d.Count Then
            If gone(d.Features(j).Ref) Then
                gone(j) = True
                MarkDependents = MarkDependents + 1
            End If
        End If
    Next j
End Function

' Removes the marked features and renumbers what the rest refer to.
Public Sub DeleteMarked(d As TDesign, gone() As Boolean)
    Dim i As Integer, n As Integer, newIndex() As Integer, blank As TFeature
    ReDim newIndex(0 To d.Count)
    For i = 1 To d.Count
        If Not gone(i) Then
            n = n + 1
            newIndex(i) = n
            d.Features(n) = d.Features(i)
            If d.Features(n).Ref >= 1 Then d.Features(n).Ref = newIndex(d.Features(n).Ref)
        End If
    Next i
    For i = n + 1 To d.Count
        d.Features(i) = blank
    Next i
    d.Count = n
End Sub

Public Function Describe(d As TDesign, ByVal i As Integer) As String
    Dim f As TFeature
    f = d.Features(i)
    Select Case f.Kind
    Case FK_SKETCH_RECT
        Describe = Fmt(f.P1) & " x " & Fmt(f.P2) & " mm at (" & Fmt(f.X) & ", " & Fmt(f.Y) & ")"
        If f.P3 > 0 Then Describe = Describe & ", R" & Fmt(f.P3) & " corners"
        Describe = Describe & SketchPlace(d, f)
    Case FK_SKETCH_CIRCLE
        Describe = "R " & Fmt(f.P1) & " mm at (" & Fmt(f.X) & ", " & Fmt(f.Y) & ")"
        Describe = Describe & SketchPlace(d, f)
    Case FK_EXTRUDE
        Describe = FeatureName(d, f.Ref) & ", " & Fmt(f.P1) & " mm"
    Case FK_REVOLVE
        Describe = FeatureName(d, f.Ref) & ", " & Fmt(f.P1) & Chr$(176) & " about Y"
    Case FK_HOLE
        Describe = "D " & Fmt(f.P1) & " mm on " & FeatureName(d, f.Ref) & " top face, "
        If f.P2 <= 0 Then
            Describe = Describe & "through all"
        Else
            Describe = Describe & Fmt(f.P2) & " mm deep"
        End If
    End Select
End Function

'  ", on Extrude1" / ", on Extrude1 +2" / ", Z 5" / "" for where a sketch sits.
Private Function SketchPlace(d As TDesign, f As TFeature) As String
    If f.Ref > 0 Then
        SketchPlace = ", on " & FeatureName(d, f.Ref)
        If f.Z <> 0 Then SketchPlace = SketchPlace & IIf(f.Z > 0, " +", " ") & Fmt(f.Z)
    ElseIf f.Z <> 0 Then
        SketchPlace = ", Z " & Fmt(f.Z)
    End If
End Function

Public Function Fmt(ByVal v As Double) As String
    If Y2KHappened Then
        Fmt = Y2KDimension()        ' two-digit years were a mistake
        Exit Function
    End If
    Fmt = Format$(v, "0.##")
    If Right$(Fmt, 1) = "." Then Fmt = Left$(Fmt, Len(Fmt) - 1)
End Function

' ---- Save and Open: Put and Get, straight from the Type ----

Public Function SaveDesign(d As TDesign, ByVal sPath As String) As Boolean
    Dim fh As Integer
    On Error GoTo Failed
    d.Magic = FILE_MAGIC
    d.Version = FILE_VERSION
    If Len(Dir$(sPath)) > 0 Then Kill sPath
    fh = FreeFile
    Open sPath For Binary Access Write As #fh
    Put #fh, 1, d
    Close #fh
    SaveDesign = True
    Exit Function
Failed:
    If fh <> 0 Then Close #fh
    MsgBox "Run-time error '" & Err.Number & "':" & vbCrLf & vbCrLf & Err.Description, vbCritical, App.Title
End Function

Public Function LoadDesign(d As TDesign, ByVal sPath As String) As Boolean
    Dim fh As Integer, h As TFileHeader
    On Error GoTo Failed
    fh = FreeFile
    Open sPath For Binary Access Read As #fh
    Get #fh, 1, h
    If h.Magic <> FILE_MAGIC Then
        Close #fh
        MsgBox "'" & sPath & "' is not a SolidCraft 98 part.", vbExclamation, App.Title
        Exit Function
    End If
    If h.Version > FILE_VERSION Then
        Close #fh
        MsgBox "This file was saved by a newer version of SolidCraft." & vbCrLf & vbCrLf & _
            "Please upgrade to SolidCraft 98 Second Edition.", vbExclamation, App.Title
        Exit Function
    End If
    If h.Version < 3 Then
        Close #fh
        MsgBox "This file was saved by an older version of SolidCraft." & vbCrLf & vbCrLf & _
            "Versions before 3 are not supported. They never were.", vbExclamation, App.Title
        Exit Function
    End If
    If h.Version = 3 Then
        Dim old As TDesignV3, i As Integer
        Get #fh, 1, old
        Close #fh
        NewDesign d, RTrim$(old.Title)
        d.Count = old.Count
        For i = 1 To old.Count
            d.Features(i).Kind = old.Features(i).Kind
            d.Features(i).Name = old.Features(i).Name
            d.Features(i).X = old.Features(i).X
            d.Features(i).Y = old.Features(i).Y
            d.Features(i).Z = old.Features(i).Z
            d.Features(i).P1 = old.Features(i).P1
            d.Features(i).P2 = old.Features(i).P2
            d.Features(i).Ref = old.Features(i).Ref
            d.Features(i).Suppressed = old.Features(i).Suppressed
        Next i
        MsgBox "This file was saved by an older version of SolidCraft." & vbCrLf & vbCrLf & _
            "It has been converted. Save it to keep the new format." & vbCrLf & _
            "(This has never happened before.)", vbInformation, App.Title
        LoadDesign = True
        Exit Function
    End If
    Get #fh, 1, d
    Close #fh
    LoadDesign = True
    Exit Function
Failed:
    If fh <> 0 Then Close #fh
    MsgBox "Run-time error '" & Err.Number & "':" & vbCrLf & vbCrLf & Err.Description, vbCritical, App.Title
End Function
