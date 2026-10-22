{ uGif - writes 16-colour GIF89a files, animated if you like.

  A real LZW compressor is a weekend. This one sends a Clear code every few
  pixels so the code table never grows: every pixel goes out as its own
  5-bit code. The files are bigger than they need to be, which in 1999 was
  called "web-ready". Any browser can read them. }
unit uGif;

{$mode objfpc}{$H+}

interface

type
  TPixels = array of array of Byte;     // [x, y], a palette index 0-15

{ Begin a GIF of w x h with the 16-colour QBColor palette. }
procedure GifBegin(w, h: Integer; ALoop: Boolean);
{ Add one frame; ATransparent is -1 or a palette index. }
procedure GifFrame(const px: TPixels; w, h, ADelay, ATransparent: Integer);
function GifSave(const APath: string): Boolean;
{ The nearest of the 16 colours. }
function NearestQB(r, g, b: Integer): Byte;

implementation

uses Classes, SysUtils, Graphics, uArt;

var
  Buf: array of Byte;
  Len: Integer;
  BitBuf: LongWord;
  BitCount: Integer;
  Block: array[0..254] of Byte;
  BlockLen: Integer;

procedure PutByte(b: Integer);
begin
  if Len >= Length(Buf) then SetLength(Buf, Length(Buf) * 2 + 4096);
  Buf[Len] := b and 255;
  Inc(Len);
end;

procedure PutWord(v: Integer);
begin
  PutByte(v and 255);
  PutByte((v shr 8) and 255);
end;

procedure PutStr(const s: string);
var
  i: Integer;
begin
  for i := 1 to Length(s) do PutByte(Ord(s[i]));
end;

procedure FlushBlock;
var
  i: Integer;
begin
  if BlockLen = 0 then Exit;
  PutByte(BlockLen);
  for i := 0 to BlockLen - 1 do PutByte(Block[i]);
  BlockLen := 0;
end;

procedure BlockByte(b: Integer);
begin
  Block[BlockLen] := b;
  Inc(BlockLen);
  if BlockLen = 255 then FlushBlock;
end;

procedure PutCode(code: Integer);
begin
  BitBuf := BitBuf or (LongWord(code) shl BitCount);
  Inc(BitCount, 5);
  while BitCount >= 8 do
  begin
    BlockByte(BitBuf and 255);
    BitBuf := BitBuf shr 8;
    Dec(BitCount, 8);
  end;
end;

procedure GifBegin(w, h: Integer; ALoop: Boolean);
var
  i: Integer;
  c: TColor;
begin
  SetLength(Buf, 4096);
  Len := 0;
  PutStr('GIF89a');
  PutWord(w); PutWord(h);
  PutByte($F3);         // global colour table, 4 bits per colour, 16 entries
  PutByte(0);           // background colour
  PutByte(0);           // square pixels
  for i := 0 to 15 do
  begin
    c := QB[i];
    PutByte(Red(c)); PutByte(Green(c)); PutByte(Blue(c));
  end;
  if ALoop then         // loop forever
  begin
    PutByte($21); PutByte($FF); PutByte(11);
    PutStr('NETSCAPE2.0');
    PutByte(3); PutByte(1); PutWord(0); PutByte(0);
  end;
end;

procedure GifFrame(const px: TPixels; w, h, ADelay, ATransparent: Integer);
var
  x, y, run: Integer;
begin
  // graphic control extension: delay in 1/100 s, optional transparency
  PutByte($21); PutByte($F9); PutByte(4);
  if ATransparent >= 0 then PutByte(9) else PutByte(8);    // dispose to background (+ transparent flag)
  PutWord(ADelay);
  if ATransparent >= 0 then PutByte(ATransparent) else PutByte(0);
  PutByte(0);
  // image descriptor
  PutByte($2C);
  PutWord(0); PutWord(0); PutWord(w); PutWord(h);
  PutByte(0);
  // image data: minimum code size 4, so Clear = 16, End = 17, codes are 5 bits
  PutByte(4);
  BitBuf := 0; BitCount := 0; BlockLen := 0;
  run := 0;
  PutCode(16);
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
    begin
      PutCode(px[x, y]);
      Inc(run);
      if run = 12 then       // before the table would need 6-bit codes
      begin
        PutCode(16);
        run := 0;
      end;
    end;
  PutCode(17);
  if BitCount > 0 then BlockByte(BitBuf and 255);
  FlushBlock;
  PutByte(0);                // end of image data
end;

function GifSave(const APath: string): Boolean;
var
  fs: TFileStream;
begin
  PutByte($3B);              // trailer
  try
    fs := TFileStream.Create(APath, fmCreate);
    try
      fs.WriteBuffer(Buf[0], Len);
    finally
      fs.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

function NearestQB(r, g, b: Integer): Byte;
var
  i: Integer;
  d, best: LongInt;
  c: TColor;
begin
  best := MaxLongInt;
  Result := 0;
  for i := 0 to 15 do
  begin
    c := QB[i];
    d := Sqr(r - Red(c)) + Sqr(g - Green(c)) + Sqr(b - Blue(c));
    if d < best then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

end.
