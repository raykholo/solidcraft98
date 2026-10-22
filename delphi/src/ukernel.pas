{ uKernel - turns the features into edges (the "geometry kernel").
  A line-for-line port of the Windows version's modKernel. }
unit uKernel;

{$mode objfpc}{$H+}

interface

uses uModel;

const
  CIRCLE_SEGS = 32;

  // colours as $RRGGBB
  COL_SKETCH = $0000C0;        // blue
  COL_SKETCH_USED = $80A0C0;   // faded, once a feature consumes it
  COL_SOLID = $000000;
  COL_HOLE = $800000;          // dark red
  COL_AXIS = $808080;

type
  TEdge = record
    X1, Y1, Z1, X2, Y2, Z2: Double;
    Col: LongWord;
  end;
  TEdgeArray = array of TEdge;
  TDoubleArray = array of Double;

function ProfilePoints(const f: TFeature; out px, py: TDoubleArray; out seam: TBoolArray;
  nCircle: Integer = CIRCLE_SEGS): Integer;
function ProfileContains(const s: TFeature; x, y, rr: Double): Boolean;
function SketchZ(const d: TDesign; i: Integer): Double;
procedure ExtrudeRange(const d: TDesign; i: Integer; out z0, z1: Double);
procedure HoleSpan(const d: TDesign; i: Integer; out zTop, zBot: Double);
function Regenerate(const d: TDesign; out e: TEdgeArray): Integer;
function RefOk(const d: TDesign; i: Integer): Boolean;

implementation

procedure AddEdge(var e: TEdgeArray; var n: Integer; x1, y1, z1, x2, y2, z2: Double; c: LongWord);
begin
  if n >= Length(e) then SetLength(e, Length(e) * 2 + 16);
  e[n].X1 := x1; e[n].Y1 := y1; e[n].Z1 := z1;
  e[n].X2 := x2; e[n].Y2 := y2; e[n].Z2 := z2;
  e[n].Col := c;
  Inc(n);
end;

procedure AddCircle(var e: TEdgeArray; var n: Integer; cx, cy, z, r: Double; c: LongWord);
var
  i: Integer;
  a0, a1: Double;
begin
  for i := 0 to CIRCLE_SEGS - 1 do
  begin
    a0 := 2 * Pi * i / CIRCLE_SEGS;
    a1 := 2 * Pi * (i + 1) / CIRCLE_SEGS;
    AddEdge(e, n, cx + r * Cos(a0), cy + r * Sin(a0), z, cx + r * Cos(a1), cy + r * Sin(a1), z, c);
  end;
end;

{ Profile points of a sketch, counter-clockwise, in its own plane. seam[j] is
  True where a solid built on it should show a vertical edge. }
function ProfilePoints(const f: TFeature; out px, py: TDoubleArray; out seam: TBoolArray;
  nCircle: Integer): Integer;
var
  i, c, j, k, n: Integer;
  r, cx, cy, a: Double;
begin
  n := 0;
  cx := 0; cy := 0;
  if f.Kind = FK_SKETCH_RECT then
  begin
    r := f.P3;
    if r <= 0 then
    begin
      SetLength(px, 4); SetLength(py, 4); SetLength(seam, 4);
      px[0] := f.X; py[0] := f.Y;
      px[1] := f.X + f.P1; py[1] := f.Y;
      px[2] := f.X + f.P1; py[2] := f.Y + f.P2;
      px[3] := f.X; py[3] := f.Y + f.P2;
      for i := 0 to 3 do seam[i] := True;
      Exit(4);
    end;
    k := nCircle div 4;
    if k < 2 then k := 2;
    SetLength(px, 4 * (k + 1)); SetLength(py, 4 * (k + 1)); SetLength(seam, 4 * (k + 1));
    for c := 0 to 3 do
    begin
      case c of
        0: begin cx := f.X + f.P1 - r; cy := f.Y + r; end;
        1: begin cx := f.X + f.P1 - r; cy := f.Y + f.P2 - r; end;
        2: begin cx := f.X + r; cy := f.Y + f.P2 - r; end;
        3: begin cx := f.X + r; cy := f.Y + r; end;
      end;
      for j := 0 to k do
      begin
        a := (c * 90 - 90 + 90 * j / k) * Pi / 180;
        px[n] := cx + r * Cos(a); py[n] := cy + r * Sin(a);
        seam[n] := (j = 0) or (j = k);
        Inc(n);
      end;
    end;
    Result := n;
  end
  else
  begin
    SetLength(px, nCircle); SetLength(py, nCircle); SetLength(seam, nCircle);
    for i := 0 to nCircle - 1 do
    begin
      px[i] := f.X + f.P1 * Cos(2 * Pi * i / nCircle);
      py[i] := f.Y + f.P1 * Sin(2 * Pi * i / nCircle);
      seam[i] := (i mod 4) = 0;
    end;
    Result := nCircle;
  end;
end;

function ProfileContains(const s: TFeature; x, y, rr: Double): Boolean;
const
  EPS = 0.000001;
var
  r, cx, cy: Double;
begin
  if s.Kind = FK_SKETCH_CIRCLE then
    Exit(Sqrt(Sqr(x - s.X) + Sqr(y - s.Y)) + rr <= s.P1 + EPS);
  if (x - rr < s.X - EPS) or (x + rr > s.X + s.P1 + EPS) or (y - rr < s.Y - EPS) or (y + rr > s.Y + s.P2 + EPS) then
    Exit(False);
  r := s.P3;
  if r > 0 then
  begin
    cx := x; cy := y;
    if x < s.X + r then cx := s.X + r;
    if x > s.X + s.P1 - r then cx := s.X + s.P1 - r;
    if y < s.Y + r then cy := s.Y + r;
    if y > s.Y + s.P2 - r then cy := s.Y + s.P2 - r;
    if Sqrt(Sqr(x - cx) + Sqr(y - cy)) + rr > r + EPS then
      if ((x < s.X + r) or (x > s.X + s.P1 - r)) and ((y < s.Y + r) or (y > s.Y + s.P2 - r)) then
        Exit(False);
  end;
  Result := True;
end;

function SketchZ(const d: TDesign; i: Integer): Double;
var
  r: Integer;
  z0, z1: Double;
begin
  Result := d.F[i].Z;
  r := d.F[i].Ref;
  if (r >= 1) and (r < i) then
    if d.F[r].Kind = FK_EXTRUDE then
    begin
      ExtrudeRange(d, r, z0, z1);
      Result := Result + z1;
    end;
end;

procedure ExtrudeRange(const d: TDesign; i: Integer; out z0, z1: Double);
begin
  z0 := SketchZ(d, d.F[i].Ref);
  z1 := z0 + d.F[i].P1;
end;

procedure HoleSpan(const d: TDesign; i: Integer; out zTop, zBot: Double);
const
  EPS = 0.000001;
var
  j: Integer;
  b0, b1: Double;
  moved: Boolean;
begin
  ExtrudeRange(d, d.F[i].Ref, zBot, zTop);
  if d.F[i].P2 > 0 then
  begin
    zBot := zTop - d.F[i].P2;
    Exit;
  end;
  repeat
    moved := False;
    for j := 1 to i - 1 do
      if (d.F[j].Kind = FK_EXTRUDE) and (d.F[j].Suppressed = 0) and (j <> d.F[i].Ref) then
        if RefOk(d, j) then
        begin
          ExtrudeRange(d, j, b0, b1);
          if (b0 < zBot - EPS) and (b1 >= zBot - EPS) and (b1 <= zTop + EPS) then
            if ProfileContains(d.F[d.F[j].Ref], d.F[i].X, d.F[i].Y, d.F[i].P1 / 2) then
            begin
              zBot := b0;
              moved := True;
            end;
        end;
  until not moved;
end;

function MaxAbs(const v: TDoubleArray; n: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to n - 1 do
    if Abs(v[i]) > Result then Result := Abs(v[i]);
end;

function Regenerate(const d: TDesign; out e: TEdgeArray): Integer;
var
  n, i, j, k, np, steps, sk: Integer;
  z0, z1, zt, r, a0, a1, sz: Double;
  px, py: TDoubleArray;
  seam: TBoolArray;
  used: array[0..MAX_FEATURES] of Boolean;
  c: LongWord;
begin
  SetLength(e, 256);
  n := 0;
  FillChar(used, SizeOf(used), 0);
  for i := 1 to d.Count do
    if (d.F[i].Kind = FK_EXTRUDE) or (d.F[i].Kind = FK_REVOLVE) then
      if (d.F[i].Ref >= 1) and (d.F[i].Ref <= d.Count) then used[d.F[i].Ref] := True;

  for i := 1 to d.Count do
    if (d.F[i].Suppressed = 0) and RefOk(d, i) then
      with d.F[i] do
        case Kind of
          FK_SKETCH_RECT:
            begin
              sz := SketchZ(d, i);
              np := ProfilePoints(d.F[i], px, py, seam);
              if used[i] then c := COL_SKETCH_USED else c := COL_SKETCH;
              for j := 0 to np - 1 do
              begin
                k := (j + 1) mod np;
                AddEdge(e, n, px[j], py[j], sz, px[k], py[k], sz, c);
              end;
            end;
          FK_SKETCH_CIRCLE:
            begin
              if used[i] then c := COL_SKETCH_USED else c := COL_SKETCH;
              AddCircle(e, n, X, Y, SketchZ(d, i), P1, c);
            end;
          FK_EXTRUDE:
            begin
              ExtrudeRange(d, i, z0, z1);
              np := ProfilePoints(d.F[Ref], px, py, seam);
              for j := 0 to np - 1 do
              begin
                k := (j + 1) mod np;
                AddEdge(e, n, px[j], py[j], z0, px[k], py[k], z0, COL_SOLID);
                AddEdge(e, n, px[j], py[j], z1, px[k], py[k], z1, COL_SOLID);
                if seam[j] then AddEdge(e, n, px[j], py[j], z0, px[j], py[j], z1, COL_SOLID);
              end;
            end;
          FK_REVOLVE:
            begin
              // spin the profile about the Y axis of its plane
              sk := Ref;
              sz := SketchZ(d, sk);
              np := ProfilePoints(d.F[sk], px, py, seam);
              steps := Trunc(Abs(P1) / 15 + 0.5);
              if steps < 1 then steps := 1;
              for k := 0 to steps do
              begin
                a0 := (P1 * Pi / 180) * k / steps;
                if (k = 0) or (k = steps) or ((k mod 3) = 0) then
                  for j := 0 to np - 1 do
                    AddEdge(e, n, px[j] * Cos(a0), py[j], sz - px[j] * Sin(a0),
                      px[(j + 1) mod np] * Cos(a0), py[(j + 1) mod np], sz - px[(j + 1) mod np] * Sin(a0), COL_SOLID);
                if k < steps then
                begin
                  a1 := (P1 * Pi / 180) * (k + 1) / steps;
                  for j := 0 to np - 1 do
                    if seam[j] and ((np <= 4) or (d.F[sk].Kind = FK_SKETCH_RECT) or ((j mod 8) = 0)) then
                      AddEdge(e, n, px[j] * Cos(a0), py[j], sz - px[j] * Sin(a0),
                        px[j] * Cos(a1), py[j], sz - px[j] * Sin(a1), COL_SOLID);
                end;
              end;
              AddEdge(e, n, 0, -10, sz, 0, 10 + MaxAbs(py, np), sz, COL_AXIS);
            end;
          FK_HOLE:
            begin
              HoleSpan(d, i, zt, z0);
              r := P1 / 2;
              AddCircle(e, n, X, Y, zt, r, COL_HOLE);
              AddCircle(e, n, X, Y, z0, r, COL_HOLE);
              for j := 0 to 3 do
              begin
                a0 := j * Pi / 2;
                AddEdge(e, n, X + r * Cos(a0), Y + r * Sin(a0), zt, X + r * Cos(a0), Y + r * Sin(a0), z0, COL_HOLE);
              end;
            end;
        end;
  SetLength(e, n);
  Result := n;
end;

function RefOk(const d: TDesign; i: Integer): Boolean;
begin
  Result := False;
  with d.F[i] do
    case Kind of
      FK_SKETCH_RECT, FK_SKETCH_CIRCLE:
        if Ref = 0 then Result := True
        else if (Ref >= 1) and (Ref < i) then
          if d.F[Ref].Kind = FK_EXTRUDE then Result := RefOk(d, Ref);
      FK_EXTRUDE, FK_REVOLVE:
        if (Ref >= 1) and (Ref < i) then Result := IsSketch(d.F[Ref].Kind);
      FK_FOREIGN:
        Result := True;         // nothing to build, nothing to break
      FK_HOLE:
        if (Ref >= 1) and (Ref < i) then
          if d.F[Ref].Kind = FK_EXTRUDE then
            if RefOk(d, Ref) then
              Result := ProfileContains(d.F[d.F[Ref].Ref], X, Y, P1 / 2);
    end;
end;

end.
