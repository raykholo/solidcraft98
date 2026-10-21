Attribute VB_Name = "modTurbo"
' modTurbo - the Turbo button.
'
' On a 1990s PC the Turbo button switched the CPU between full speed and a
' slower one for old games. Ours does the opposite of what you'd hope: the
' LED says 66 MHz normally and 33 with Turbo on, and Turbo switches on the
' authentic 1999 behaviour. Every fake in here is only drawn on screen: it
' never touches system files, the clock or a disk drive, and never loses
' a design.
Option Explicit

Public Turbo As Boolean

Public Const FLOPPY_BYTES As Long = 1457664    ' a formatted 3 1/2" HD floppy

' The Y2K bug has happened (only possible in Turbo, only on 31 Dec 1999).
Public Y2KHappened As Boolean

Private mSawNewYearsEve As Boolean
Private mClockOffset As Double

Public Sub SetTurbo(ByVal bOn As Boolean)
    Turbo = bOn
    If Not Turbo Then Y2KHappened = False
    frmMain.TurboChanged
    RefreshAllParts
    If Turbo Then
        frmMain.SetStatus "Turbo on: 33 MHz. Authentic 1999 behaviour enabled."
    Else
        frmMain.SetStatus "Turbo off: 66 MHz. Everything works again."
    End If
End Sub

Public Function LedDigits() As String
    If Turbo Then LedDigits = "33" Else LedDigits = "66"
End Function

Public Sub RefreshAllParts()
    Dim f As Form
    For Each f In Forms
        If TypeOf f Is frmPart Then f.RefreshAll False
    Next f
End Sub

' ---- The clock. Read, never set. ----

' Starting SolidCraft98.exe with /Y2KTEST pretends it's a minute to
' midnight on 31 Dec 1999, so the Y2K bug can be seen without touching the
' PC's clock.
Public Sub InitClock()
    If InStr(1, Command$, "/Y2KTEST", vbTextCompare) > 0 Then
        mClockOffset = DateSerial(1999, 12, 31) + TimeSerial(23, 59, 0) - Now
    End If
End Sub

Public Function ClockNow() As Date
    ClockNow = Now + mClockOffset
End Function

' Called every second. On 31 Dec 1999 at midnight, with Turbo on, the
' year rolls over the way a two-digit year does: 19 & 100.
Public Sub ClockTick()
    Dim t As Date
    If Not Turbo Or Y2KHappened Then Exit Sub
    t = ClockNow()
    If Year(t) = 1999 And Month(t) = 12 And Day(t) = 31 Then mSawNewYearsEve = True
    If mSawNewYearsEve And Year(t) = 2000 Then
        Y2KHappened = True
        RefreshAllParts
        frmMain.SetStatus "Happy New Year 19100! All dimensions have been updated."
    End If
End Sub

' What a dimension says once the Y2K bug has struck.
Public Function Y2KDimension() As String
    Y2KDimension = "19" & CStr(Year(ClockNow()) - 1900)
End Function

' ---- The solver: Variant everything, converges on the third try ----

Public Function SolverConverges(nTries As Integer) As Boolean
    Dim residual As Variant
    If Not Turbo Then
        SolverConverges = True
        Exit Function
    End If
    nTries = nTries + 1
    residual = "0." & String$(3 - nTries, "9") & "1"   ' a String, a Double, who's counting
    If nTries < 3 Then
        MsgBox "Did not converge. Try again." & vbCrLf & vbCrLf & _
            "Residual: " & residual, vbExclamation, "Constraint Solver"
        Exit Function
    End If
    nTries = 0
    MsgBox "Converged. See? Variant works.", vbInformation, "Constraint Solver"
    SolverConverges = True
End Function

' ---- Orbit speed ----

Public Function OrbitFrameInterval() As Single
    If Turbo Then OrbitFrameInterval = 0.25 Else OrbitFrameInterval = 0
End Function
