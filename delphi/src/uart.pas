{ uArt - the 16-colour icons, the logo, gradients: everything drawn from
  code, so the program ships no bitmaps. }
unit uArt;

{$mode objfpc}{$H+}

interface

uses Graphics, Controls, ImgList;

const
  APP_NAME = 'SolidCraft 98';
  APP_EDITION = 'Delphi Edition';
  APP_BUILD = 'Build 1998.1023';
  APP_VERSION = 'Version 1.2.0';

var
  QB: array[0..15] of TColor;

function IconIndex(const AKey: string): Integer;
{ A 16 x 16 icon, s times the size; see-through pixels are clFuchsia. }
function IconBitmap(const AKey: string; s: Integer = 1): TBitmap;
procedure PaintIcon(c: TCanvas; const AKey: string; x, y: Integer; s: Integer = 1);
{ Row y of an icon: 16 hex digits (palette indexes), '.' for see-through. }
function IconRow(const AKey: string; y: Integer): string;
procedure AddIcons(il: TImageList; const Keys: array of string);
procedure GradientV(c: TCanvas; x, y, w, h: Integer; c1, c2: TColor);
procedure GradientH(c: TCanvas; x, y, w, h: Integer; c1, c2: TColor);
{ The logo: an isometric block with a hole in the top (our own art). }
procedure DrawLogo(c: TCanvas; ox, oy: Integer; s: Double; col: TColor);

implementation

{$I icondata.inc}

function IconIndex(const AKey: string): Integer;
var
  i: Integer;
begin
  for i := 0 to ICON_COUNT - 1 do
    if IconNames[i] = AKey then Exit(i);
  Result := -1;
end;

function IconRow(const AKey: string; y: Integer): string;
var
  k: Integer;
begin
  k := IconIndex(AKey);
  if k < 0 then Exit(StringOfChar('.', 16));
  Result := IconArt[k, y];
end;

function HexVal(ch: Char): Integer;
begin
  if ch <= '9' then Result := Ord(ch) - Ord('0') else Result := Ord(ch) - Ord('A') + 10;
end;

procedure PaintIcon(c: TCanvas; const AKey: string; x, y: Integer; s: Integer);
var
  k, r, col: Integer;
begin
  k := IconIndex(AKey);
  if k < 0 then Exit;
  for r := 0 to 15 do
    for col := 0 to 15 do
      if IconArt[k, r][col + 1] <> '.' then
      begin
        c.Brush.Color := QB[HexVal(IconArt[k, r][col + 1])];
        c.FillRect(x + col * s, y + r * s, x + col * s + s, y + r * s + s);
      end;
end;

function IconBitmap(const AKey: string; s: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(16 * s, 16 * s);
  Result.Canvas.Brush.Color := clFuchsia;
  Result.Canvas.FillRect(0, 0, 16 * s, 16 * s);
  PaintIcon(Result.Canvas, AKey, 0, 0, s);
  Result.TransparentColor := clFuchsia;
  Result.Transparent := True;
end;

procedure AddIcons(il: TImageList; const Keys: array of string);
var
  i: Integer;
  b: TBitmap;
begin
  for i := 0 to High(Keys) do
  begin
    b := IconBitmap(Keys[i]);
    il.AddMasked(b, clFuchsia);
    b.Free;
  end;
end;

function Mix(c1, c2: TColor; t: Double): TColor;
var
  r1, g1, b1, r2, g2, b2: Integer;
begin
  c1 := ColorToRGB(c1); c2 := ColorToRGB(c2);
  r1 := Red(c1); g1 := Green(c1); b1 := Blue(c1);
  r2 := Red(c2); g2 := Green(c2); b2 := Blue(c2);
  Result := RGBToColor(Round(r1 + (r2 - r1) * t), Round(g1 + (g2 - g1) * t), Round(b1 + (b2 - b1) * t));
end;

procedure GradientV(c: TCanvas; x, y, w, h: Integer; c1, c2: TColor);
var
  i: Integer;
begin
  for i := 0 to h - 1 do
  begin
    if h > 1 then c.Pen.Color := Mix(c1, c2, i / (h - 1)) else c.Pen.Color := c1;
    c.Line(x, y + i, x + w, y + i);
  end;
end;

procedure GradientH(c: TCanvas; x, y, w, h: Integer; c1, c2: TColor);
var
  i: Integer;
begin
  for i := 0 to w - 1 do
  begin
    if w > 1 then c.Pen.Color := Mix(c1, c2, i / (w - 1)) else c.Pen.Color := c1;
    c.Line(x + i, y, x + i, y + h);
  end;
end;

procedure IsoPt(x, y, z, s: Double; ox, oy: Integer; out sx, sy: Integer);
begin
  sx := ox + Round((x - y) * 0.866 * s);
  sy := oy + Round((x + y) * 0.5 * s - z * s);
end;

procedure DrawLogo(c: TCanvas; ox, oy: Integer; s: Double; col: TColor);
var
  px, py: array[0..7] of Integer;
  i, hx, hy, rx, ry: Integer;
begin
  IsoPt(0, 0, 0, s, ox, oy, px[0], py[0]); IsoPt(4, 0, 0, s, ox, oy, px[1], py[1]);
  IsoPt(4, 3, 0, s, ox, oy, px[2], py[2]); IsoPt(0, 3, 0, s, ox, oy, px[3], py[3]);
  IsoPt(0, 0, 1.5, s, ox, oy, px[4], py[4]); IsoPt(4, 0, 1.5, s, ox, oy, px[5], py[5]);
  IsoPt(4, 3, 1.5, s, ox, oy, px[6], py[6]); IsoPt(0, 3, 1.5, s, ox, oy, px[7], py[7]);
  c.Pen.Color := col;
  c.Pen.Width := 2;
  for i := 0 to 3 do
  begin
    c.Line(px[i], py[i], px[(i + 1) mod 4], py[(i + 1) mod 4]);
    c.Line(px[i + 4], py[i + 4], px[(i + 1) mod 4 + 4], py[(i + 1) mod 4 + 4]);
    c.Line(px[i], py[i], px[i + 4], py[i + 4]);
  end;
  IsoPt(2, 1.5, 1.5, s, ox, oy, hx, hy);
  rx := Round(s * 0.75); ry := Round(s * 0.75 * 0.55);
  c.Brush.Style := bsClear;
  c.Ellipse(hx - rx, hy - ry, hx + rx, hy + ry);
  c.Brush.Style := bsSolid;
  c.Pen.Width := 1;
end;

initialization
  QB[0] := $000000; QB[1] := $800000; QB[2] := $008000; QB[3] := $808000;
  QB[4] := $000080; QB[5] := $800080; QB[6] := $008080; QB[7] := $C0C0C0;
  QB[8] := $808080; QB[9] := $FF0000; QB[10] := $00FF00; QB[11] := $FFFF00;
  QB[12] := $0000FF; QB[13] := $FF00FF; QB[14] := $00FFFF; QB[15] := $FFFFFF;
end.
