Attribute VB_Name = "modZip"
' modZip - reads one file out of a ZIP archive, with its own Deflate
' decoder. A .solidcraft design is a ZIP, and in 1999 you couldn't assume
' the PC could open one, so we bring our own.
'
' Inflate follows RFC 1951: stored, fixed-Huffman and dynamic-Huffman blocks,
' decoded with canonical code counts, one bit at a time. Not fast, but a
' design's document.json is a few kilobytes.
Option Explicit

Private mIn() As Byte
Private mInPos As Long
Private mInEnd As Long
Private mBitBuf As Long
Private mBitCnt As Long
Private mOut() As Byte
Private mOutLen As Long
Private mPow2(0 To 30) As Long

' A Huffman code: how many codes of each length, then the symbols in code order.
Private mLenCount(0 To 15) As Long
Private mLenSym(0 To 287) As Long
Private mDistCount(0 To 15) As Long
Private mDistSym(0 To 29) As Long

Private mLenBase As Variant, mLenExtra As Variant, mDistBase As Variant, mDistExtra As Variant

' Reads sName out of the ZIP at sPath into b(). Returns its length, or -1
' when the file isn't a ZIP or has no such entry. Raises an error if it's damaged.
Public Function ZipReadEntry(ByVal sPath As String, ByVal sName As String, b() As Byte) As Long
    Dim fh As Integer, all() As Byte, n As Long, eocd As Long, i As Long
    Dim cdOff As Long, cdCount As Long, p As Long, nameLen As Long, extraLen As Long, commentLen As Long
    Dim method As Long, compSize As Long, size As Long, lho As Long, sEntry As String, dataStart As Long
    ZipReadEntry = -1
    fh = FreeFile
    Open sPath For Binary Access Read As #fh
    n = LOF(fh)
    If n < 22 Then
        Close #fh
        Exit Function
    End If
    ReDim all(0 To n - 1)
    Get #fh, 1, all
    Close #fh
    If U32(all, 0) <> &H4034B50 Then Exit Function      ' "PK", 3, 4
    ' the end-of-central-directory record is in the last 64 KB
    For i = n - 22 To IIf(n - 65558 > 0, n - 65558, 0) Step -1
        If U32(all, i) = &H6054B50 Then
            eocd = i
            Exit For
        End If
    Next i
    If eocd = 0 And U32(all, 0) <> &H6054B50 Then Err.Raise 13, , "Damaged ZIP: no central directory"
    cdCount = U16(all, eocd + 10)
    cdOff = U32(all, eocd + 16)
    p = cdOff
    For i = 1 To cdCount
        If U32(all, p) <> &H2014B50 Then Err.Raise 13, , "Damaged ZIP: bad directory entry"
        method = U16(all, p + 10)
        compSize = U32(all, p + 20)
        size = U32(all, p + 24)
        nameLen = U16(all, p + 28)
        extraLen = U16(all, p + 30)
        commentLen = U16(all, p + 32)
        lho = U32(all, p + 42)
        sEntry = Utf8ToString(SliceBytes(all, p + 46, nameLen), nameLen)
        If sEntry = sName Then
            If U32(all, lho) <> &H4034B50 Then Err.Raise 13, , "Damaged ZIP: bad local header"
            dataStart = lho + 30 + U16(all, lho + 26) + U16(all, lho + 28)
            Select Case method
            Case 0                    ' stored
                ReDim b(0 To IIf(size > 0, size - 1, 0))
                CopyBytes all, dataStart, b, size
                ZipReadEntry = size
            Case 8                    ' deflated
                ZipReadEntry = Inflate(all, dataStart, compSize, b)
                If ZipReadEntry <> size Then Err.Raise 13, , "Damaged ZIP: wrong size after inflating"
            Case Else
                Err.Raise 13, , "Unsupported ZIP compression method " & method
            End Select
            Exit Function
        End If
        p = p + 46 + nameLen + extraLen + commentLen
    Next i
End Function

Private Function U16(b() As Byte, ByVal i As Long) As Long
    U16 = b(i) Or (b(i + 1) * &H100&)
End Function

' Little-endian 32-bit, as a signed Long (the signatures fit; sizes stay under 2 GB).
Private Function U32(b() As Byte, ByVal i As Long) As Long
    Dim hi As Long
    hi = b(i + 3)
    If hi >= &H80 Then hi = hi - &H100
    U32 = b(i) Or (b(i + 1) * &H100&) Or (b(i + 2) * &H10000) Or (hi * &H1000000)
End Function

Private Function SliceBytes(b() As Byte, ByVal i As Long, ByVal n As Long) As Byte()
    Dim r() As Byte
    ReDim r(0 To IIf(n > 0, n - 1, 0))
    CopyBytes b, i, r, n
    SliceBytes = r
End Function

Private Sub CopyBytes(src() As Byte, ByVal i As Long, dst() As Byte, ByVal n As Long)
    Dim k As Long
    For k = 0 To n - 1
        dst(k) = src(i + k)
    Next k
End Sub

' ---- Inflate ----

Private Sub InitTables()
    Dim i As Integer
    If IsArray(mLenBase) Then Exit Sub
    mPow2(0) = 1
    For i = 1 To 30
        mPow2(i) = mPow2(i - 1) * 2
    Next i
    mLenBase = Array(3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
    mLenExtra = Array(0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0)
    mDistBase = Array(1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577)
    mDistExtra = Array(0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13)
End Sub

' Inflates n bytes of src from offset i into b(). Returns the length.
Private Function Inflate(src() As Byte, ByVal i As Long, ByVal n As Long, b() As Byte) As Long
    Dim final As Long, btype As Long
    InitTables
    mIn = src
    mInPos = i
    mInEnd = i + n
    mBitBuf = 0
    mBitCnt = 0
    mOutLen = 0
    ReDim mOut(0 To 65535)
    Do
        final = Bits(1)
        btype = Bits(2)
        Select Case btype
        Case 0: StoredBlock
        Case 1: FixedCodes: CodesBlock
        Case 2: DynamicCodes: CodesBlock
        Case Else: Err.Raise 13, , "Damaged Deflate data"
        End Select
    Loop Until final = 1
    ReDim b(0 To IIf(mOutLen > 0, mOutLen - 1, 0))
    CopyBytes mOut, 0, b, mOutLen
    Inflate = mOutLen
End Function

Private Function Bits(ByVal need As Long) As Long
    Do While mBitCnt < need
        If mInPos >= mInEnd Then Err.Raise 13, , "Deflate data ended early"
        mBitBuf = mBitBuf Or (CLng(mIn(mInPos)) * mPow2(mBitCnt))
        mInPos = mInPos + 1
        mBitCnt = mBitCnt + 8
    Loop
    Bits = mBitBuf And (mPow2(need) - 1)
    mBitBuf = mBitBuf \ mPow2(need)
    mBitCnt = mBitCnt - need
End Function

Private Sub PutByte(ByVal v As Long)
    If mOutLen > UBound(mOut) Then ReDim Preserve mOut(0 To UBound(mOut) * 2 + 1)
    mOut(mOutLen) = v
    mOutLen = mOutLen + 1
End Sub

Private Sub StoredBlock()
    Dim n As Long, k As Long
    mBitBuf = 0                       ' skip to the byte boundary
    mBitCnt = 0
    If mInPos + 4 > mInEnd Then Err.Raise 13, , "Deflate data ended early"
    n = mIn(mInPos) Or (mIn(mInPos + 1) * &H100&)
    mInPos = mInPos + 4               ' LEN and its complement
    If mInPos + n > mInEnd Then Err.Raise 13, , "Deflate data ended early"
    For k = 0 To n - 1
        PutByte mIn(mInPos + k)
    Next k
    mInPos = mInPos + n
End Sub

' Builds a canonical code from code lengths. Counts go in cnt(), symbols in sym().
Private Sub BuildCode(lengths() As Long, ByVal n As Long, cnt() As Long, sym() As Long)
    Dim i As Long, offs(0 To 15) As Long
    For i = 0 To 15
        cnt(i) = 0
    Next i
    For i = 0 To n - 1
        cnt(lengths(i)) = cnt(lengths(i)) + 1
    Next i
    offs(1) = 0
    For i = 1 To 14
        offs(i + 1) = offs(i) + cnt(i)
    Next i
    For i = 0 To n - 1
        If lengths(i) <> 0 Then
            sym(offs(lengths(i))) = i
            offs(lengths(i)) = offs(lengths(i)) + 1
        End If
    Next i
End Sub

' One symbol, read a bit at a time against the canonical code.
Private Function Decode(cnt() As Long, sym() As Long) As Long
    Dim code As Long, first As Long, index As Long, l As Long, c As Long
    For l = 1 To 15
        code = code Or Bits(1)
        c = cnt(l)
        If code - c < first Then
            Decode = sym(index + (code - first))
            Exit Function
        End If
        index = index + c
        first = (first + c) * 2
        code = code * 2
    Next l
    Err.Raise 13, , "Damaged Deflate data: bad code"
End Function

Private Sub FixedCodes()
    Dim lengths(0 To 287) As Long, i As Long
    For i = 0 To 143: lengths(i) = 8: Next i
    For i = 144 To 255: lengths(i) = 9: Next i
    For i = 256 To 279: lengths(i) = 7: Next i
    For i = 280 To 287: lengths(i) = 8: Next i
    BuildCode lengths, 288, mLenCount, mLenSym
    For i = 0 To 29: lengths(i) = 5: Next i
    BuildCode lengths, 30, mDistCount, mDistSym
End Sub

Private Sub DynamicCodes()
    Dim nlen As Long, ndist As Long, ncode As Long, i As Long, sym As Long, rep As Long, prev As Long
    Dim order As Variant, lengths(0 To 318) As Long, cl(0 To 18) As Long
    Dim clCount(0 To 15) As Long, clSym(0 To 18) As Long, litLen(0 To 287) As Long, distLen(0 To 29) As Long
    order = Array(16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15)
    nlen = Bits(5) + 257
    ndist = Bits(5) + 1
    ncode = Bits(4) + 4
    If nlen > 286 Or ndist > 30 Then Err.Raise 13, , "Damaged Deflate data: too many codes"
    For i = 0 To ncode - 1
        cl(order(i)) = Bits(3)
    Next i
    BuildCode cl, 19, clCount, clSym
    i = 0
    Do While i < nlen + ndist
        sym = Decode(clCount, clSym)
        If sym < 16 Then
            lengths(i) = sym
            i = i + 1
        Else
            prev = 0
            Select Case sym
            Case 16
                If i = 0 Then Err.Raise 13, , "Damaged Deflate data: repeat with nothing before"
                prev = lengths(i - 1)
                rep = 3 + Bits(2)
            Case 17: rep = 3 + Bits(3)
            Case Else: rep = 11 + Bits(7)
            End Select
            If i + rep > nlen + ndist Then Err.Raise 13, , "Damaged Deflate data: too many lengths"
            Do While rep > 0
                lengths(i) = prev
                i = i + 1
                rep = rep - 1
            Loop
        End If
    Loop
    For i = 0 To nlen - 1
        litLen(i) = lengths(i)
    Next i
    For i = 0 To ndist - 1
        distLen(i) = lengths(nlen + i)
    Next i
    BuildCode litLen, nlen, mLenCount, mLenSym
    BuildCode distLen, ndist, mDistCount, mDistSym
End Sub

Private Sub CodesBlock()
    Dim sym As Long, length As Long, dist As Long, k As Long
    Do
        sym = Decode(mLenCount, mLenSym)
        If sym < 256 Then
            PutByte sym
        ElseIf sym = 256 Then
            Exit Do
        Else
            sym = sym - 257
            If sym >= 29 Then Err.Raise 13, , "Damaged Deflate data: bad length"
            length = mLenBase(sym) + Bits(mLenExtra(sym))
            sym = Decode(mDistCount, mDistSym)
            If sym >= 30 Then Err.Raise 13, , "Damaged Deflate data: bad distance"
            dist = mDistBase(sym) + Bits(mDistExtra(sym))
            If dist > mOutLen Then Err.Raise 13, , "Damaged Deflate data: distance too far back"
            For k = 1 To length
                PutByte mOut(mOutLen - dist)
            Next k
        End If
    Loop
End Sub
