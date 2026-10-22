{ uShade - View > Shaded, the software renderer. A port of the Windows
  version's modShade: every triangle is filled in pixel by pixel with a depth
  per pixel; lines go where two faces meet at a corner, and round the
  outline. The slow reveal, a few rows at a time, is the part window's. }
unit uShade;

{$mode objfpc}{$H+}
{$Q-}{$R-}   // the hash wraps round on purpose

interface

uses Graphics, uModel, uMesh, uView;

type
  TIntArray = array of Integer;

{ Which triangles make one face: neighbours from the same feature that meet
  nearly flat (a cylinder's facets do; a wall and a top don't). }
procedure FaceGroups(const t: TTriArray; n: Integer; out g: TIntArray);
{ Renders the triangles over what bmp shows now (the grid). }
procedure RenderShaded(bmp: TBitmap; const v: TView; const t: TTriArray; n: Integer; const g: TIntArray; const d: TDesign);

implementation

uses SysUtils, Classes, IntfGraphics, FPImage, GraphType;

type
  TKey = record
    a, b: array[0..2] of Double;
  end;

function SameCorner(const t: TTri; k: Integer; out x, y, z: Double): Boolean;
begin
  case k of
    0: begin x := t.X1; y := t.Y1; z := t.Z1; end;
    1: begin x := t.X2; y := t.Y2; z := t.Z2; end;
  else
    x := t.X3; y := t.Y3; z := t.Z3;
  end;
  Result := True;
end;

function HashD(v: Double; h: QWord): QWord; inline;
begin
  h := h xor PQWord(@v)^;
  h := h * QWord($100000001B3);
  h := h xor (h shr 29);
  Result := h;
end;

function EdgeHash(ax, ay, az, bx, by, bz: Double): QWord;
begin
  Result := QWord($CBF29CE484222325);
  Result := HashD(ax, Result); Result := HashD(ay, Result); Result := HashD(az, Result);
  Result := HashD(bx, Result); Result := HashD(by, Result); Result := HashD(bz, Result);
end;

function Smooth(const a, b: TTri): Boolean;
var
  ax, ay, az, bx, by, bz: Double;
begin
  if a.Body <> b.Body then Exit(False);
  TriNormal(a, ax, ay, az);
  TriNormal(b, bx, by, bz);
  Result := ax * bx + ay * by + az * bz > 0.9;      // within about 25 degrees
end;

function Root(var par: TIntArray; i: Integer): Integer;
begin
  while par[i] <> i do
  begin
    par[i] := par[par[i]];
    i := par[i];
  end;
  Result := i;
end;

procedure FaceGroups(const t: TTriArray; n: Integer; out g: TIntArray);
var
  par, slotT, slotK: TIntArray;
  size, i, k, slot, j, a, b, mask: Integer;
  ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz: Double;
begin
  SetLength(g, n);
  if n = 0 then Exit;
  SetLength(par, n);
  for i := 0 to n - 1 do par[i] := i;
  size := 1;
  while size < n * 6 do size := size * 2;
  mask := size - 1;
  SetLength(slotT, size); SetLength(slotK, size);
  for i := 0 to size - 1 do slotT[i] := -1;
  // every directed edge into the table
  for i := 0 to n - 1 do
    for k := 0 to 2 do
    begin
      SameCorner(t[i], k, ax, ay, az);
      SameCorner(t[i], (k + 1) mod 3, bx, by, bz);
      slot := EdgeHash(ax, ay, az, bx, by, bz) and mask;
      while slotT[slot] >= 0 do slot := (slot + 1) and mask;
      slotT[slot] := i; slotK[slot] := k;
    end;
  // each edge's twin runs the other way
  for i := 0 to n - 1 do
    for k := 0 to 2 do
    begin
      SameCorner(t[i], k, ax, ay, az);
      SameCorner(t[i], (k + 1) mod 3, bx, by, bz);
      slot := EdgeHash(bx, by, bz, ax, ay, az) and mask;
      while slotT[slot] >= 0 do
      begin
        j := slotT[slot];
        SameCorner(t[j], slotK[slot], cx, cy, cz);
        SameCorner(t[j], (slotK[slot] + 1) mod 3, dx, dy, dz);
        if (cx = bx) and (cy = by) and (cz = bz) and (dx = ax) and (dy = ay) and (dz = az) then
        begin
          if (j > i) and Smooth(t[i], t[j]) then
          begin
            a := Root(par, i); b := Root(par, j);
            if a <> b then par[a] := b;
          end;
          Break;
        end;
        slot := (slot + 1) and mask;
      end;
    end;
  for i := 0 to n - 1 do g[i] := Root(par, i) + 1;
end;

procedure RenderShaded(bmp: TBitmap; const v: TView; const t: TTriArray; n: Integer; const g: TIntArray; const d: TDesign);
const
  EDGE_COL = $202020;
var
  img: TLazIntfImage;
  w, h, i, x, y, p, q, x0, xe, y0, ye: Integer;
  zbuf: array of Single;
  gbuf: array of Integer;
  pix: array of LongWord;               // $RRGGBB
  ex, ey, ez, rx, ry, rz, ux, uy, uz, lx, ly, lz, l, nx, ny, nz, k: Double;
  x1, y1, d1, x2, y2, d2, x3, y3, d3, area, cx, cy, a1, a2, a3: Double;
  dep: Single;
  col: LongWord;
  c: TFPColor;

  function Shade(r, gg, b: Integer; kk: Double): LongWord;
  begin
    Result := (LongWord(Round(r * kk)) shl 16) or (LongWord(Round(gg * kk)) shl 8) or LongWord(Round(b * kk));
  end;

begin
  w := bmp.Width; h := bmp.Height;
  if (w < 2) or (h < 2) then Exit;
  img := bmp.CreateIntfImage;
  try
    SetLength(pix, w * h); SetLength(zbuf, w * h); SetLength(gbuf, w * h);
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        c := img.Colors[x, y];
        pix[y * w + x] := (LongWord(c.red shr 8) shl 16) or (LongWord(c.green shr 8) shl 8) or (c.blue shr 8);
      end;
    for i := 0 to w * h - 1 do begin zbuf[i] := -1E30; gbuf[i] := 0; end;

    // which way is the eye, and the light over the viewer's left shoulder
    ViewAxes(v, ex, ey, ez, rx, ry, rz, ux, uy, uz);
    lx := ex + 0.6 * ux - 0.4 * rx; ly := ey + 0.6 * uy - 0.4 * ry; lz := ez + 0.6 * uz - 0.4 * rz;
    l := Sqrt(lx * lx + ly * ly + lz * lz);
    lx := lx / l; ly := ly / l; lz := lz / l;

    for i := 0 to n - 1 do
    begin
      TriNormal(t[i], nx, ny, nz);
      if nx * ex + ny * ey + nz * ez <= 0.000001 then Continue;      // facing away
      k := nx * lx + ny * ly + nz * lz;
      if k < 0 then k := 0;
      k := 0.3 + 0.7 * k;
      if d.F[t[i].Body].Kind = FK_HOLE then col := Shade(205, 135, 125, k) else col := Shade(165, 178, 200, k);
      ProjectPixel(v, w, h, t[i].X1, t[i].Y1, t[i].Z1, x1, y1, d1);
      ProjectPixel(v, w, h, t[i].X2, t[i].Y2, t[i].Z2, x2, y2, d2);
      ProjectPixel(v, w, h, t[i].X3, t[i].Y3, t[i].Z3, x3, y3, d3);
      area := (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1);
      if Abs(area) < 0.000001 then Continue;
      x0 := Trunc(x1); if x2 < x0 then x0 := Trunc(x2); if x3 < x0 then x0 := Trunc(x3);
      y0 := Trunc(y1); if y2 < y0 then y0 := Trunc(y2); if y3 < y0 then y0 := Trunc(y3);
      xe := Trunc(x1); if x2 > xe then xe := Trunc(x2); if x3 > xe then xe := Trunc(x3); Inc(xe);
      ye := Trunc(y1); if y2 > ye then ye := Trunc(y2); if y3 > ye then ye := Trunc(y3); Inc(ye);
      if x0 < 0 then x0 := 0;
      if y0 < 0 then y0 := 0;
      if xe > w - 1 then xe := w - 1;
      if ye > h - 1 then ye := h - 1;
      for y := y0 to ye do
      begin
        cy := y + 0.5;
        for x := x0 to xe do
        begin
          cx := x + 0.5;
          a1 := ((x3 - x2) * (cy - y2) - (y3 - y2) * (cx - x2)) / area;
          a2 := ((x1 - x3) * (cy - y3) - (y1 - y3) * (cx - x3)) / area;
          a3 := 1 - a1 - a2;
          if (a1 >= 0) and (a2 >= 0) and (a3 >= 0) then
          begin
            dep := a1 * d1 + a2 * d2 + a3 * d3;
            p := y * w + x;
            if dep > zbuf[p] then
            begin
              zbuf[p] := dep;
              pix[p] := col;
              gbuf[p] := g[i];
            end;
          end;
        end;
      end;
    end;

    // lines where one face meets another, or meets the background
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        p := y * w + x;
        if x < w - 1 then
        begin
          q := p + 1;
          if gbuf[p] <> gbuf[q] then
            if gbuf[p] <> 0 then pix[p] := EDGE_COL else pix[q] := EDGE_COL;
        end;
        if y < h - 1 then
        begin
          q := p + w;
          if gbuf[p] <> gbuf[q] then
            if gbuf[p] <> 0 then pix[p] := EDGE_COL else pix[q] := EDGE_COL;
        end;
      end;

    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        col := pix[y * w + x];
        c.red := ((col shr 16) and 255) * 257;
        c.green := ((col shr 8) and 255) * 257;
        c.blue := (col and 255) * 257;
        c.alpha := $FFFF;
        img.Colors[x, y] := c;
      end;
    bmp.LoadFromIntfImage(img);
  finally
    img.Free;
  end;
end;

end.
