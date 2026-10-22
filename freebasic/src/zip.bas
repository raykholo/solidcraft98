' zip.bas - reads one file out of a ZIP archive, with its own Deflate
' decoder (RFC 1951: stored, fixed and dynamic Huffman blocks, canonical
' codes, one bit at a time). A port of the Windows version's modZip.
' Errors go in ZipErr; a function that hits one returns at once.

Dim Shared ZipErr As String

Dim Shared zIn As UByte Ptr
Dim Shared zInPos As Long, zInEnd As Long
Dim Shared zBitBuf As ULong, zBitCnt As Long
Dim Shared zOut() As UByte
Dim Shared zOutLen As Long
Dim Shared zLenCount(0 To 15) As Long, zLenSym(0 To 287) As Long
Dim Shared zDistCount(0 To 15) As Long, zDistSym(0 To 29) As Long
Dim Shared zLenBase(0 To 28) As Long = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
Dim Shared zLenExtra(0 To 28) As Long = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
Dim Shared zDistBase(0 To 29) As Long = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577}
Dim Shared zDistExtra(0 To 29) As Long = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13}

Sub ZFail(ByRef t As String)
    If Len(ZipErr) = 0 Then ZipErr = t
End Sub

Function U16(ByVal b As UByte Ptr, ByVal i As Long) As Long
    Return b[i] Or (CLng(b[i + 1]) Shl 8)
End Function

Function U32(ByVal b As UByte Ptr, ByVal i As Long) As ULong
    Return b[i] Or (CULng(b[i + 1]) Shl 8) Or (CULng(b[i + 2]) Shl 16) Or (CULng(b[i + 3]) Shl 24)
End Function

Function ZBits(ByVal need As Long) As Long
    Do While zBitCnt < need
        If zInPos >= zInEnd Then ZFail "Deflate data ended early": Return 0
        zBitBuf Or= CULng(zIn[zInPos]) Shl zBitCnt
        zInPos += 1
        zBitCnt += 8
    Loop
    Dim As Long v = zBitBuf And ((1 Shl need) - 1)
    zBitBuf Shr= need
    zBitCnt -= need
    Return v
End Function

Sub ZPut(ByVal v As Long)
    If zOutLen > UBound(zOut) Then ReDim Preserve zOut(0 To UBound(zOut) * 2 + 1)
    zOut(zOutLen) = v
    zOutLen += 1
End Sub

Sub StoredBlock()
    zBitBuf = 0: zBitCnt = 0             ' skip to the byte boundary
    If zInPos + 4 > zInEnd Then ZFail "Deflate data ended early": Exit Sub
    Dim As Long n = zIn[zInPos] Or (CLng(zIn[zInPos + 1]) Shl 8), k
    zInPos += 4                          ' LEN and its complement
    If zInPos + n > zInEnd Then ZFail "Deflate data ended early": Exit Sub
    For k = 0 To n - 1: ZPut zIn[zInPos + k]: Next
    zInPos += n
End Sub

' Builds a canonical code from code lengths.
Sub BuildCode(lengths() As Long, ByVal n As Long, cnt() As Long, sym() As Long)
    Dim As Long i, offs(0 To 15)
    For i = 0 To 15: cnt(i) = 0: Next
    For i = 0 To n - 1: cnt(lengths(i)) += 1: Next
    offs(1) = 0
    For i = 1 To 14: offs(i + 1) = offs(i) + cnt(i): Next
    For i = 0 To n - 1
        If lengths(i) <> 0 Then sym(offs(lengths(i))) = i: offs(lengths(i)) += 1
    Next
End Sub

Function Decode(cnt() As Long, sym() As Long) As Long
    Dim As Long code, first, index, l, c
    For l = 1 To 15
        code Or= ZBits(1)
        If Len(ZipErr) Then Return 0
        c = cnt(l)
        If code - c < first Then Return sym(index + (code - first))
        index += c
        first = (first + c) * 2
        code *= 2
    Next
    ZFail "Damaged Deflate data: bad code"
    Return 0
End Function

Sub FixedCodes()
    Dim As Long lengths(0 To 287), i
    For i = 0 To 143: lengths(i) = 8: Next
    For i = 144 To 255: lengths(i) = 9: Next
    For i = 256 To 279: lengths(i) = 7: Next
    For i = 280 To 287: lengths(i) = 8: Next
    BuildCode lengths(), 288, zLenCount(), zLenSym()
    For i = 0 To 29: lengths(i) = 5: Next
    BuildCode lengths(), 30, zDistCount(), zDistSym()
End Sub

Sub DynamicCodes()
    Static order(0 To 18) As Long = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}
    Dim As Long nlen, ndist, ncode, i, sym, rep, prev
    Dim As Long lengths(0 To 318), cl(0 To 18), clCount(0 To 15), clSym(0 To 18), litLen(0 To 287), distLen(0 To 29)
    nlen = ZBits(5) + 257: ndist = ZBits(5) + 1: ncode = ZBits(4) + 4
    If nlen > 286 Or ndist > 30 Then ZFail "Damaged Deflate data: too many codes": Exit Sub
    For i = 0 To ncode - 1: cl(order(i)) = ZBits(3): Next
    BuildCode cl(), 19, clCount(), clSym()
    i = 0
    Do While i < nlen + ndist
        If Len(ZipErr) Then Exit Sub
        sym = Decode(clCount(), clSym())
        If sym < 16 Then
            lengths(i) = sym: i += 1
        Else
            prev = 0
            Select Case sym
            Case 16
                If i = 0 Then ZFail "Damaged Deflate data: repeat with nothing before": Exit Sub
                prev = lengths(i - 1): rep = 3 + ZBits(2)
            Case 17: rep = 3 + ZBits(3)
            Case Else: rep = 11 + ZBits(7)
            End Select
            If i + rep > nlen + ndist Then ZFail "Damaged Deflate data: too many lengths": Exit Sub
            Do While rep > 0: lengths(i) = prev: i += 1: rep -= 1: Loop
        End If
    Loop
    For i = 0 To nlen - 1: litLen(i) = lengths(i): Next
    For i = 0 To ndist - 1: distLen(i) = lengths(nlen + i): Next
    BuildCode litLen(), nlen, zLenCount(), zLenSym()
    BuildCode distLen(), ndist, zDistCount(), zDistSym()
End Sub

Sub CodesBlock()
    Dim As Long sym, length, dist, k
    Do
        If Len(ZipErr) Then Exit Sub
        sym = Decode(zLenCount(), zLenSym())
        If sym < 256 Then
            ZPut sym
        ElseIf sym = 256 Then
            Exit Do
        Else
            sym -= 257
            If sym >= 29 Then ZFail "Damaged Deflate data: bad length": Exit Sub
            length = zLenBase(sym) + ZBits(zLenExtra(sym))
            sym = Decode(zDistCount(), zDistSym())
            If sym >= 30 Then ZFail "Damaged Deflate data: bad distance": Exit Sub
            dist = zDistBase(sym) + ZBits(zDistExtra(sym))
            If dist > zOutLen Then ZFail "Damaged Deflate data: distance too far back": Exit Sub
            For k = 1 To length: ZPut zOut(zOutLen - dist): Next
        End If
    Loop
End Sub

Function Inflate(ByVal src As UByte Ptr, ByVal i As Long, ByVal n As Long) As Long
    Dim As Long fin, btype
    zIn = src: zInPos = i: zInEnd = i + n
    zBitBuf = 0: zBitCnt = 0: zOutLen = 0
    ReDim zOut(0 To 65535)
    Do
        fin = ZBits(1): btype = ZBits(2)
        If Len(ZipErr) Then Return -1
        Select Case btype
        Case 0: StoredBlock
        Case 1: FixedCodes: CodesBlock
        Case 2: DynamicCodes: CodesBlock
        Case Else: ZFail "Damaged Deflate data"
        End Select
        If Len(ZipErr) Then Return -1
    Loop Until fin = 1
    Return zOutLen
End Function

' Reads sName out of the ZIP at sPath into the string sOut (raw bytes).
' Returns its length, or -1 when the file isn't a ZIP or has no such entry;
' ZipErr is set if it's damaged.
Function ZipReadEntry(ByRef sPath As String, ByRef sName As String, ByRef sOut As String) As Long
    Dim As Long fh = FreeFile, n, i, eocd = -1, cdCount, p, nameLen, extraLen, commentLen, method, k
    Dim As ULong cdOff, compSize, size, lho
    ZipErr = ""
    If Open(sPath For Binary Access Read As #fh) <> 0 Then Return -1
    n = LOF(fh)
    If n < 22 Then Close #fh: Return -1
    Dim As String all = String(n, 0)
    Get #fh, , all
    Close #fh
    Dim As UByte Ptr b = StrPtr(all)
    If U32(b, 0) <> &h04034B50 Then Return -1          ' "PK", 3, 4
    ' the end-of-central-directory record is in the last 64 KB
    For i = n - 22 To IIf(n - 65558 > 0, n - 65558, 0) Step -1
        If U32(b, i) = &h06054B50 Then eocd = i: Exit For
    Next
    If eocd < 0 Then ZFail "Damaged ZIP: no central directory": Return -1
    cdCount = U16(b, eocd + 10)
    cdOff = U32(b, eocd + 16)
    p = cdOff
    For i = 1 To cdCount
        If p + 46 > n OrElse U32(b, p) <> &h02014B50 Then ZFail "Damaged ZIP: bad directory entry": Return -1
        method = U16(b, p + 10)
        compSize = U32(b, p + 20): size = U32(b, p + 24)
        nameLen = U16(b, p + 28): extraLen = U16(b, p + 30): commentLen = U16(b, p + 32)
        lho = U32(b, p + 42)
        If Mid(all, p + 47, nameLen) = sName Then
            If U32(b, lho) <> &h04034B50 Then ZFail "Damaged ZIP: bad local header": Return -1
            Dim As Long dataStart = lho + 30 + U16(b, lho + 26) + U16(b, lho + 28)
            Select Case method
            Case 0                    ' stored
                sOut = Mid(all, dataStart + 1, size)
                Return size
            Case 8                    ' deflated
                Dim As Long got = Inflate(b, dataStart, compSize)
                If got < 0 Then Return -1
                If got <> size Then ZFail "Damaged ZIP: wrong size after inflating": Return -1
                sOut = String(got, 0)
                For k = 0 To got - 1: sOut[k] = zOut(k): Next
                Return got
            Case Else
                ZFail "Unsupported ZIP compression method " & method: Return -1
            End Select
        End If
        p += 46 + nameLen + extraLen + commentLen
    Next
    Return -1
End Function
