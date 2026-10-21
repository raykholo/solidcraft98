Attribute VB_Name = "modPublish"
' modPublish - File > Publish to Web. Writes a home page for your part, in
' the style of the day: a marquee, a hit counter, an "under construction"
' GIF (our own, animated, two frames) and a picture of the part.
' It writes three files into the folder you pick and goes nowhere near a
' network. Works with Turbo on or off.
Option Explicit

Private Declare Function GetPixel Lib "gdi32" (ByVal hdc As Long, ByVal x As Long, ByVal y As Long) As Long

Public Sub PublishPart(p As frmPart)
    Dim sHtml As String, sDir As String, sBase As String, slot As Integer
    slot = p.DocIndex
    sHtml = frmMain.AskFileName(True, MakeFileName(RTrim$(Docs(slot).Title)) & ".htm", "Web Pages (*.htm)|*.htm", "htm")
    If Len(sHtml) = 0 Then Exit Sub
    sDir = Left$(sHtml, InStrRev(sHtml, "\"))
    sBase = FileTitle(sHtml)
    Screen.MousePointer = vbHourglass
    frmMain.SetStatus "Rendering " & sBase & ".gif..."
    WritePartGif p.ViewPicture, sDir & sBase & ".gif"
    WriteConstructionGif sDir & "construction.gif"
    WriteHtml slot, sHtml, sBase & ".gif"
    Screen.MousePointer = vbDefault
    frmMain.SetStatus "Published " & sHtml
    MsgBox "Your part is on the World Wide Web!*" & vbCrLf & vbCrLf & _
        sHtml & vbCrLf & vbCrLf & _
        "* On your hard disk. Upload it with your FTP program.", vbInformation, "Publish to Web"
End Sub

Private Function MakeFileName(ByVal s As String) As String
    Dim i As Integer, ch As String
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch Like "[A-Za-z0-9_-]" Then MakeFileName = MakeFileName & ch
    Next i
    If Len(MakeFileName) = 0 Then MakeFileName = "mypart"
End Function

' The viewport as it is now, squeezed into the 16 colours.
Private Sub WritePartGif(ByVal pic As PictureBox, ByVal sPath As String)
    Dim w As Long, h As Long, x As Long, y As Long, px() As Byte
    w = pic.ScaleWidth: h = pic.ScaleHeight
    ReDim px(0 To w - 1, 0 To h - 1)
    For y = 0 To h - 1
        For x = 0 To w - 1
            px(x, y) = NearestQB(GetPixel(pic.hDC, x, y))
        Next x
        If y Mod 40 = 0 Then DoEvents
    Next y
    GifBegin w, h, False
    GifFrame px, w, h, 0, -1
    GifSave sPath
End Sub

' Two frames of the road sign, at 3x, blinking twice a second.
Private Sub WriteConstructionGif(ByVal sPath As String)
    GifBegin 48, 48, True
    AddSignFrame "Construction"
    AddSignFrame "Construction2"
    GifSave sPath
End Sub

Private Sub AddSignFrame(ByVal sKey As String)
    Dim rows() As String, px() As Byte, x As Long, y As Long, ch As String
    rows = IconRows(sKey)
    ReDim px(0 To 47, 0 To 47)
    For y = 0 To 47
        For x = 0 To 47
            ch = Mid$(rows(y \ 3), x \ 3 + 1, 1)
            If ch = "." Then px(x, y) = 13 Else px(x, y) = CByte("&H" & ch)
        Next x
    Next y
    GifFrame px, 48, 48, 50, 13          ' magenta is see-through
End Sub

Private Sub WriteHtml(ByVal slot As Integer, ByVal sPath As String, ByVal sGif As String)
    Dim fh As Integer, i As Integer, sTitle As String, hits As String
    sTitle = HtmlText(RTrim$(Docs(slot).Title))
    hits = Format$(427 + Int(Rnd * 9000), "000000")   ' nobody wants to be visitor 1
    fh = FreeFile
    Open sPath For Output As #fh
    Print #fh, "<HTML>"
    Print #fh, "<HEAD><TITLE>" & sTitle & " - My SolidCraft 98 Part!!!</TITLE></HEAD>"
    Print #fh, "<BODY BGCOLOR=""#000080"" TEXT=""#FFFF00"" LINK=""#00FFFF"" VLINK=""#FF00FF"">"
    Print #fh, "<CENTER>"
    Print #fh, "<MARQUEE BEHAVIOR=""alternate""><FONT FACE=""Comic Sans MS"" SIZE=""6""><B>Welcome to " & sTitle & "!!!</B></FONT></MARQUEE>"
    Print #fh, "<P><IMG SRC=""construction.gif"" WIDTH=""48"" HEIGHT=""48""> <FONT SIZE=""5""><B>This page is under construction!</B></FONT> <IMG SRC=""construction.gif"" WIDTH=""48"" HEIGHT=""48""></P>"
    Print #fh, "<HR WIDTH=""80%"">"
    Print #fh, "<P><IMG SRC=""" & sGif & """ BORDER=""4"" ALT=""" & sTitle & " (wireframe)""></P>"
    Print #fh, "<TABLE BORDER=""3"" CELLPADDING=""4"" BGCOLOR=""#C0C0C0"">"
    Print #fh, "<TR><TH><FONT COLOR=""#000000"">#</FONT></TH><TH><FONT COLOR=""#000000"">Feature</FONT></TH><TH><FONT COLOR=""#000000"">What it is</FONT></TH></TR>"
    For i = 1 To Docs(slot).Count
        Print #fh, "<TR><TD><FONT COLOR=""#000000"">" & i & "</FONT></TD><TD><FONT COLOR=""#000000"">" & _
            HtmlText(FeatureName(Docs(slot), i)) & "</FONT></TD><TD><FONT COLOR=""#000000"">" & _
            HtmlText(Describe(Docs(slot), i)) & "</FONT></TD></TR>"
    Next i
    Print #fh, "</TABLE>"
    Print #fh, "<P>You are visitor number"
    Print #fh, "<TABLE BORDER=""1"" CELLPADDING=""2"" CELLSPACING=""0"" BGCOLOR=""#000000""><TR>"
    For i = 1 To Len(hits)
        Print #fh, "<TD><FONT FACE=""Courier New"" COLOR=""#00FF00"" SIZE=""5""><B>" & Mid$(hits, i, 1) & "</B></FONT></TD>"
    Next i
    Print #fh, "</TR></TABLE></P>"
    Print #fh, "<P><A HREF=""#"">Sign my guestbook!</A> | <A HREF=""#"">View my guestbook!</A> | <A HREF=""#"">Next site in the CAD Web Ring &gt;&gt;</A></P>"
    Print #fh, "<HR WIDTH=""80%"">"
    Print #fh, "<FONT SIZE=""2"">Best viewed in IE5 at 800x600. Made with SolidCraft 98 " & HtmlText(AppVersion()) & ".<BR>"
    Print #fh, "Last updated " & Format$(ClockNow(), "mmmm d, yyyy") & ".</FONT>"
    Print #fh, "</CENTER>"
    Print #fh, "</BODY>"
    Print #fh, "</HTML>"
    Close #fh
End Sub

Private Function HtmlText(ByVal s As String) As String
    s = Replace(s, "&", "&amp;")
    s = Replace(s, "<", "&lt;")
    s = Replace(s, ">", "&gt;")
    HtmlText = Replace(s, """", "&quot;")
End Function
