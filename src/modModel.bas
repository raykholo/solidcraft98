Attribute VB_Name = "modModel"
' modModel - the design, as one Type you can Put straight to disk.
'
' The file format IS this Type. Change a field and every older file breaks,
' which is why FILE_VERSION exists and why the "migration system" is a MsgBox.
Option Explicit

Public Const FILE_MAGIC As String = "SC98"
Public Const FILE_VERSION As Integer = 3
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

' The last extruded rectangle, i.e. a box with a top face to drill.
Public Function LastBox(d As TDesign) As Integer
    Dim i As Integer
    For i = d.Count To 1 Step -1
        If d.Features(i).Kind = FK_EXTRUDE Then
            If d.Features(i).Ref >= 1 Then
                If d.Features(d.Features(i).Ref).Kind = FK_SKETCH_RECT Then
                    LastBox = i
                    Exit Function
                End If
            End If
        End If
    Next i
End Function

Public Function Describe(d As TDesign, ByVal i As Integer) As String
    Dim f As TFeature
    f = d.Features(i)
    Select Case f.Kind
    Case FK_SKETCH_RECT
        Describe = Fmt(f.P1) & " x " & Fmt(f.P2) & " mm at (" & Fmt(f.X) & ", " & Fmt(f.Y) & ")"
    Case FK_SKETCH_CIRCLE
        Describe = "R " & Fmt(f.P1) & " mm at (" & Fmt(f.X) & ", " & Fmt(f.Y) & ")"
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
    If h.Version < FILE_VERSION Then
        Close #fh
        MsgBox "This file was saved by an older version of SolidCraft." & vbCrLf & vbCrLf & _
            "Older files are not supported. They never were.", vbExclamation, App.Title
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
