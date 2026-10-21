Attribute VB_Name = "modMain"
' modMain - startup: splash, main window, an empty part.
Option Explicit

Sub Main()
    InitClock
    frmSplash.Show
    frmSplash.Paint
    frmSplash.Refresh
    Load frmMain
    frmSplash.Progress "Loading geometry kernel..."
    frmSplash.Progress "Registering MSCOMCTL.OCX..."
    frmSplash.Progress "Reticulating B-splines..."
    frmMain.Show
    RunCommand "New"
    frmSplash.Progress "Ready."
    Unload frmSplash
End Sub
