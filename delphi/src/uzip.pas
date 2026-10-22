{ uZip - reads one file out of a ZIP archive, with its own Deflate decoder
  (RFC 1951: stored, fixed and dynamic Huffman blocks, canonical codes, one
  bit at a time). A port of the Windows version's modZip: in 1999 you
  couldn't assume the PC could open a ZIP, so we bring our own. }
unit uZip;

{$mode objfpc}{$H+}

interface

var
  ZipErr: string;

{ Reads AName out of the ZIP at APath into AOut (raw bytes). Returns its
  length, or -1 when the file isn't a ZIP or has no such entry; ZipErr is
  set if it's damaged. }
function ZipReadEntry(const APath, AName: string; out AOut: RawByteString): Integer;

implementation

uses SysUtils, Classes;

type
  EInflate = class(Exception);
  TCode = record
    Count: array[0..15] of Integer;
    Sym: array[0..287] of Integer;
  end;

const
  LenBase: array[0..28] of Integer = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LenExtra: array[0..28] of Integer = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DistBase: array[0..29] of Integer = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577);
  DistExtra: array[0..29] of Integer = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);

var
  zIn: PByte;
  zInPos, zInEnd: Integer;
  zBitBuf: LongWord;
  zBitCnt: Integer;
  zOut: array of Byte;
  zOutLen: Integer;
  zLen, zDist: TCode;

procedure Fail(const t: string);
begin
  raise EInflate.Create(t);
end;

function Bits(need: Integer): Integer;
begin
  while zBitCnt < need do
  begin
    if zInPos >= zInEnd then Fail('Deflate data ended early');
    zBitBuf := zBitBuf or (LongWord(zIn[zInPos]) shl zBitCnt);
    Inc(zInPos);
    Inc(zBitCnt, 8);
  end;
  Result := zBitBuf and ((1 shl need) - 1);
  zBitBuf := zBitBuf shr need;
  Dec(zBitCnt, need);
end;

procedure PutByte(v: Integer);
begin
  if zOutLen >= Length(zOut) then SetLength(zOut, Length(zOut) * 2 + 65536);
  zOut[zOutLen] := v;
  Inc(zOutLen);
end;

procedure StoredBlock;
var
  n, k: Integer;
begin
  zBitBuf := 0; zBitCnt := 0;            // skip to the byte boundary
  if zInPos + 4 > zInEnd then Fail('Deflate data ended early');
  n := zIn[zInPos] or (zIn[zInPos + 1] shl 8);
  Inc(zInPos, 4);                        // LEN and its complement
  if zInPos + n > zInEnd then Fail('Deflate data ended early');
  for k := 0 to n - 1 do PutByte(zIn[zInPos + k]);
  Inc(zInPos, n);
end;

procedure BuildCode(const lengths: array of Integer; n: Integer; var c: TCode);
var
  i: Integer;
  offs: array[0..15] of Integer;
begin
  for i := 0 to 15 do c.Count[i] := 0;
  for i := 0 to n - 1 do Inc(c.Count[lengths[i]]);
  offs[1] := 0;
  for i := 1 to 14 do offs[i + 1] := offs[i] + c.Count[i];
  for i := 0 to n - 1 do
    if lengths[i] <> 0 then
    begin
      c.Sym[offs[lengths[i]]] := i;
      Inc(offs[lengths[i]]);
    end;
end;

function Decode(const c: TCode): Integer;
var
  code, first, index, l, cnt: Integer;
begin
  code := 0; first := 0; index := 0;
  for l := 1 to 15 do
  begin
    code := code or Bits(1);
    cnt := c.Count[l];
    if code - cnt < first then Exit(c.Sym[index + (code - first)]);
    Inc(index, cnt);
    first := (first + cnt) * 2;
    code := code * 2;
  end;
  Fail('Damaged Deflate data: bad code');
  Result := 0;
end;

procedure FixedCodes;
var
  lengths: array[0..287] of Integer;
  i: Integer;
begin
  for i := 0 to 143 do lengths[i] := 8;
  for i := 144 to 255 do lengths[i] := 9;
  for i := 256 to 279 do lengths[i] := 7;
  for i := 280 to 287 do lengths[i] := 8;
  BuildCode(lengths, 288, zLen);
  for i := 0 to 29 do lengths[i] := 5;
  BuildCode(lengths, 30, zDist);
end;

procedure DynamicCodes;
const
  Order: array[0..18] of Integer = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);
var
  nlen, ndist, ncode, i, sym, rep, prev: Integer;
  lengths: array[0..318] of Integer;
  cl: array[0..18] of Integer;
  clc: TCode;
  lit: array[0..287] of Integer;
  dist: array[0..29] of Integer;
begin
  nlen := Bits(5) + 257; ndist := Bits(5) + 1; ncode := Bits(4) + 4;
  if (nlen > 286) or (ndist > 30) then Fail('Damaged Deflate data: too many codes');
  FillChar(cl, SizeOf(cl), 0);
  for i := 0 to ncode - 1 do cl[Order[i]] := Bits(3);
  BuildCode(cl, 19, clc);
  i := 0;
  while i < nlen + ndist do
  begin
    sym := Decode(clc);
    if sym < 16 then
    begin
      lengths[i] := sym;
      Inc(i);
    end
    else
    begin
      prev := 0;
      case sym of
        16: begin
              if i = 0 then Fail('Damaged Deflate data: repeat with nothing before');
              prev := lengths[i - 1];
              rep := 3 + Bits(2);
            end;
        17: rep := 3 + Bits(3);
      else
        rep := 11 + Bits(7);
      end;
      if i + rep > nlen + ndist then Fail('Damaged Deflate data: too many lengths');
      while rep > 0 do
      begin
        lengths[i] := prev;
        Inc(i);
        Dec(rep);
      end;
    end;
  end;
  for i := 0 to nlen - 1 do lit[i] := lengths[i];
  for i := 0 to ndist - 1 do dist[i] := lengths[nlen + i];
  BuildCode(lit, nlen, zLen);
  BuildCode(dist, ndist, zDist);
end;

procedure CodesBlock;
var
  sym, len, dist, k: Integer;
begin
  repeat
    sym := Decode(zLen);
    if sym < 256 then PutByte(sym)
    else if sym = 256 then Break
    else
    begin
      Dec(sym, 257);
      if sym >= 29 then Fail('Damaged Deflate data: bad length');
      len := LenBase[sym] + Bits(LenExtra[sym]);
      sym := Decode(zDist);
      if sym >= 30 then Fail('Damaged Deflate data: bad distance');
      dist := DistBase[sym] + Bits(DistExtra[sym]);
      if dist > zOutLen then Fail('Damaged Deflate data: distance too far back');
      for k := 1 to len do PutByte(zOut[zOutLen - dist]);
    end;
  until False;
end;

function Inflate(src: PByte; i, n: Integer): Integer;
var
  fin, btype: Integer;
begin
  zIn := src; zInPos := i; zInEnd := i + n;
  zBitBuf := 0; zBitCnt := 0; zOutLen := 0;
  SetLength(zOut, 65536);
  repeat
    fin := Bits(1);
    btype := Bits(2);
    case btype of
      0: StoredBlock;
      1: begin FixedCodes; CodesBlock; end;
      2: begin DynamicCodes; CodesBlock; end;
    else
      Fail('Damaged Deflate data');
    end;
  until fin = 1;
  Result := zOutLen;
end;

function U16(b: PByte; i: Integer): Integer; inline;
begin
  Result := b[i] or (b[i + 1] shl 8);
end;

function U32(b: PByte; i: Integer): LongWord; inline;
begin
  Result := b[i] or (LongWord(b[i + 1]) shl 8) or (LongWord(b[i + 2]) shl 16) or (LongWord(b[i + 3]) shl 24);
end;

function ZipReadEntry(const APath, AName: string; out AOut: RawByteString): Integer;
var
  ms: TMemoryStream;
  b: PByte;
  n, i, eocd, cdCount, p, nameLen, extraLen, commentLen, method, dataStart, got: Integer;
  cdOff, compSize, size, lho: LongWord;
  entry: RawByteString;
begin
  Result := -1;
  ZipErr := '';
  AOut := '';
  ms := TMemoryStream.Create;
  try
    try
      ms.LoadFromFile(APath);
    except
      Exit;
    end;
    n := ms.Size;
    if n < 22 then Exit;
    b := ms.Memory;
    if U32(b, 0) <> $04034B50 then Exit;          // "PK", 3, 4
    try
      // the end-of-central-directory record is in the last 64 KB
      eocd := -1;
      i := n - 22;
      while (i >= 0) and (i >= n - 65558) do
      begin
        if U32(b, i) = $06054B50 then begin eocd := i; Break; end;
        Dec(i);
      end;
      if eocd < 0 then Fail('Damaged ZIP: no central directory');
      cdCount := U16(b, eocd + 10);
      cdOff := U32(b, eocd + 16);
      p := cdOff;
      for i := 1 to cdCount do
      begin
        if (p + 46 > n) or (U32(b, p) <> $02014B50) then Fail('Damaged ZIP: bad directory entry');
        method := U16(b, p + 10);
        compSize := U32(b, p + 20);
        size := U32(b, p + 24);
        nameLen := U16(b, p + 28); extraLen := U16(b, p + 30); commentLen := U16(b, p + 32);
        lho := U32(b, p + 42);
        SetLength(entry, nameLen);
        if nameLen > 0 then Move(b[p + 46], entry[1], nameLen);
        if entry = AName then
        begin
          if U32(b, lho) <> $04034B50 then Fail('Damaged ZIP: bad local header');
          dataStart := lho + 30 + U16(b, lho + 26) + U16(b, lho + 28);
          case method of
            0: begin                       // stored
                 SetLength(AOut, size);
                 if size > 0 then Move(b[dataStart], AOut[1], size);
                 Exit(size);
               end;
            8: begin                       // deflated
                 got := Inflate(b, dataStart, compSize);
                 if got <> Integer(size) then Fail('Damaged ZIP: wrong size after inflating');
                 SetLength(AOut, got);
                 if got > 0 then Move(zOut[0], AOut[1], got);
                 Exit(got);
               end;
          else
            Fail('Unsupported ZIP compression method ' + IntToStr(method));
          end;
        end;
        Inc(p, 46 + nameLen + extraLen + commentLen);
      end;
    except
      on e: EInflate do
      begin
        ZipErr := e.Message;
        Result := -1;
      end;
    end;
  finally
    ms.Free;
  end;
end;

end.
