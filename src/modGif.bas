Attribute VB_Name = "modGif"
' modGif - writes 16-colour GIF89a files, animated if you like.
'
' A real LZW compressor is a weekend. This one sends a Clear code every few
' pixels so the code table never grows: every pixel goes out as its own
' 5-bit code. The files are bigger than they need to be, which in 1999 was
' called "web-ready". Any browser can read them.
Option Explicit

Private mBuf() As Byte
Private mLen As Long
Private mBitBuf As Long
Private mBitCount As Long
Private mBlock(0 To 254) As Byte
Private mBlockLen As Long

' Begin a GIF of w x h with the 16-colour QBColor palette.
Public Sub GifBegin(ByVal w As Long, ByVal h As Long, ByVal bLoop As Boolean)
    Dim i As Integer, c As Long
    ReDim mBuf(0 To 4095)
    mLen = 0
    PutStr "GIF89a"
    PutWord w: PutWord h
    PutByte &HF3          ' global colour table, 4 bits per colour, 16 entries
    PutByte 0             ' background colour
    PutByte 0             ' square pixels
    For i = 0 To 15
        c = QBColor(i)
        PutByte c And &HFF&
        PutByte (c \ &H100&) And &HFF&
        PutByte (c \ &H10000) And &HFF&
    Next i
    If bLoop Then         ' loop forever
        PutByte &H21: PutByte &HFF: PutByte 11
        PutStr "NETSCAPE2.0"
        PutByte 3: PutByte 1: PutWord 0: PutByte 0
    End If
End Sub

' Add one frame. px(x, y) holds a palette index 0-15; nTransparent is -1 or an index.
Public Sub GifFrame(px() As Byte, ByVal w As Long, ByVal h As Long, ByVal nDelay As Long, ByVal nTransparent As Integer)
    Dim x As Long, y As Long, run As Long
    ' graphic control extension: delay in 1/100 s, optional transparency
    PutByte &H21: PutByte &HF9: PutByte 4
    PutByte IIf(nTransparent >= 0, 9, 8)    ' dispose to background (+ transparent flag)
    PutWord nDelay
    PutByte IIf(nTransparent >= 0, nTransparent, 0)
    PutByte 0
    ' image descriptor
    PutByte &H2C
    PutWord 0: PutWord 0: PutWord w: PutWord h
    PutByte 0
    ' image data: minimum code size 4, so Clear = 16, End = 17, codes are 5 bits
    PutByte 4
    mBitBuf = 0: mBitCount = 0: mBlockLen = 0
    PutCode 16
    For y = 0 To h - 1
        For x = 0 To w - 1
            PutCode px(x, y)
            run = run + 1
            If run = 12 Then     ' before the table would need 6-bit codes
                PutCode 16
                run = 0
            End If
        Next x
    Next y
    PutCode 17
    If mBitCount > 0 Then BlockByte mBitBuf And &HFF&
    FlushBlock
    PutByte 0                ' end of image data
End Sub

Public Sub GifSave(ByVal sPath As String)
    Dim fh As Integer, out() As Byte
    PutByte &H3B             ' trailer
    ReDim out(0 To mLen - 1)
    CopyBytes out, mLen
    If FileExists(sPath) Then Kill sPath
    fh = FreeFile
    Open sPath For Binary Access Write As #fh
    Put #fh, 1, out
    Close #fh
End Sub

Private Sub CopyBytes(out() As Byte, ByVal n As Long)
    Dim i As Long
    For i = 0 To n - 1
        out(i) = mBuf(i)
    Next i
End Sub

Private Sub PutCode(ByVal code As Long)
    mBitBuf = mBitBuf Or (code * (2 ^ mBitCount))
    mBitCount = mBitCount + 5
    Do While mBitCount >= 8
        BlockByte mBitBuf And &HFF&
        mBitBuf = mBitBuf \ 256
        mBitCount = mBitCount - 8
    Loop
End Sub

Private Sub BlockByte(ByVal b As Long)
    mBlock(mBlockLen) = b
    mBlockLen = mBlockLen + 1
    If mBlockLen = 255 Then FlushBlock
End Sub

Private Sub FlushBlock()
    Dim i As Long
    If mBlockLen = 0 Then Exit Sub
    PutByte mBlockLen
    For i = 0 To mBlockLen - 1
        PutByte mBlock(i)
    Next i
    mBlockLen = 0
End Sub

Private Sub PutByte(ByVal b As Long)
    If mLen > UBound(mBuf) Then ReDim Preserve mBuf(0 To UBound(mBuf) * 2 + 1)
    mBuf(mLen) = b And &HFF&
    mLen = mLen + 1
End Sub

Private Sub PutWord(ByVal v As Long)
    PutByte v And &HFF&
    PutByte (v \ 256) And &HFF&
End Sub

Private Sub PutStr(ByVal s As String)
    Dim i As Integer
    For i = 1 To Len(s)
        PutByte Asc(Mid$(s, i, 1))
    Next i
End Sub

' The nearest of the 16 colours, for turning a screen picture into a GIF.
Public Function NearestQB(ByVal c As Long) As Byte
    Dim i As Integer, q As Long, d As Long, best As Long, r As Long, g As Long, b As Long
    r = c And &HFF&: g = (c \ &H100&) And &HFF&: b = (c \ &H10000) And &HFF&
    best = &H7FFFFFFF
    For i = 0 To 15
        q = QBColor(i)
        d = (r - (q And &HFF&)) ^ 2 + (g - ((q \ &H100&) And &HFF&)) ^ 2 + (b - ((q \ &H10000) And &HFF&)) ^ 2
        If d < best Then best = d: NearestQB = i
    Next i
End Function
