{ uView - projection, orbit and the wireframe, one line at a time. A port of
  the Windows version's modView. }
unit uView;

{$mode objfpc}{$H+}

interface

uses Graphics, uModel, uKernel;

const
  ISO_YAW = 135;             // looking at the front, right and top
  ISO_PITCH = 35.264;

type
  TView = record
    Yaw, Pitch: Double;      // degrees
    Zoom: Double;            // pixels per mm
    PanX, PanY: Double;      // pixels
  end;

procedure ResetView(var v: TView);
procedure ProjectRaw(const v: TView; x, y, z: Double; out sx, sy: Double);
procedure ViewAxes(const v: TView; out ex, ey, ez, rx, ry, rz, ux, uy, uz: Double);
procedure ProjectPixel(const v: TView; vw, vh: Integer; x, y, z: Double; out px, py, dep: Double);
procedure FitView(var v: TView; vw, vh: Integer; const e: TEdgeArray; n: Integer);
procedure DrawEdge(c: TCanvas; const v: TView; vw, vh: Integer; const e: TEdge);
{ Background, grid, n of the edges (0 for none), triad. }
procedure DrawScene(c: TCanvas; const v: TView; vw, vh: Integer; const e: TEdgeArray; n: Integer);
function RGBCol(rgb: LongWord): TColor;

implementation

function RGBCol(rgb: LongWord): TColor;
begin
  Result := RGBToColor((rgb shr 16) and 255, (rgb shr 8) and 255, rgb and 255);
end;

procedure ResetView(var v: TView);
begin
  v.Yaw := ISO_YAW; v.Pitch := ISO_PITCH;
  v.Zoom := 3; v.PanX := 0; v.PanY := 0;
end;

procedure ProjectRaw(const v: TView; x, y, z: Double; out sx, sy: Double);
var
  cy, syw, cp, sp, x1, y1: Double;
begin
  cy := Cos(v.Yaw * Pi / 180); syw := Sin(v.Yaw * Pi / 180);
  cp := Cos(v.Pitch * Pi / 180); sp := Sin(v.Pitch * Pi / 180);
  x1 := x * cy - y * syw;
  y1 := x * syw + y * cy;
  sx := -x1;
  sy := z * cp - y1 * sp;
end;

procedure ViewAxes(const v: TView; out ex, ey, ez, rx, ry, rz, ux, uy, uz: Double);
var
  cy, syw, cp, sp: Double;
begin
  cy := Cos(v.Yaw * Pi / 180); syw := Sin(v.Yaw * Pi / 180);
  cp := Cos(v.Pitch * Pi / 180); sp := Sin(v.Pitch * Pi / 180);
  ex := syw * cp; ey := cy * cp; ez := sp;
  rx := -cy; ry := syw; rz := 0;
  ux := -syw * sp; uy := -cy * sp; uz := cp;
end;

procedure ToScreen(const v: TView; vw, vh: Integer; x, y, z: Double; out px, py: Integer);
var
  sx, sy: Double;
begin
  ProjectRaw(v, x, y, z, sx, sy);
  px := Round(vw / 2 + v.PanX + sx * v.Zoom);
  py := Round(vh / 2 + v.PanY - sy * v.Zoom);
end;

procedure ProjectPixel(const v: TView; vw, vh: Integer; x, y, z: Double; out px, py, dep: Double);
var
  sx, sy, ex, ey, ez, rx, ry, rz, ux, uy, uz: Double;
begin
  ProjectRaw(v, x, y, z, sx, sy);
  px := vw / 2 + v.PanX + sx * v.Zoom;
  py := vh / 2 + v.PanY - sy * v.Zoom;
  ViewAxes(v, ex, ey, ez, rx, ry, rz, ux, uy, uz);
  dep := x * ex + y * ey + z * ez;
end;

procedure GrowBox(x, y: Double; var minX, maxX, minY, maxY: Double);
begin
  if x < minX then minX := x;
  if x > maxX then maxX := x;
  if y < minY then minY := y;
  if y > maxY then maxY := y;
end;

procedure FitView(var v: TView; vw, vh: Integer; const e: TEdgeArray; n: Integer);
var
  i: Integer;
  sx, sy, minX, maxX, minY, maxY, w, h: Double;
begin
  if n = 0 then
  begin
    v.Zoom := 3; v.PanX := 0; v.PanY := 0;
    Exit;
  end;
  minX := 1E30; minY := 1E30; maxX := -1E30; maxY := -1E30;
  for i := 0 to n - 1 do
  begin
    ProjectRaw(v, e[i].X1, e[i].Y1, e[i].Z1, sx, sy); GrowBox(sx, sy, minX, maxX, minY, maxY);
    ProjectRaw(v, e[i].X2, e[i].Y2, e[i].Z2, sx, sy); GrowBox(sx, sy, minX, maxX, minY, maxY);
  end;
  w := maxX - minX; h := maxY - minY;
  if w < 1 then w := 1;
  if h < 1 then h := 1;
  v.Zoom := 0.8 * vw / w;
  if 0.8 * vh / h < v.Zoom then v.Zoom := 0.8 * vh / h;
  v.PanX := -(minX + maxX) / 2 * v.Zoom;
  v.PanY := (minY + maxY) / 2 * v.Zoom;
end;

procedure DrawEdge(c: TCanvas; const v: TView; vw, vh: Integer; const e: TEdge);
var
  ax, ay, bx, by: Integer;
begin
  ToScreen(v, vw, vh, e.X1, e.Y1, e.Z1, ax, ay);
  ToScreen(v, vw, vh, e.X2, e.Y2, e.Z2, bx, by);
  c.Pen.Color := RGBCol(e.Col);
  c.Line(ax, ay, bx, by);
end;

{ A faint floor grid, 10 mm squares, so an empty part isn't just grey. }
procedure DrawGrid(c: TCanvas; const v: TView; vw, vh: Integer);
const
  G = 50;
var
  i, ax, ay, bx, by: Integer;
begin
  c.Pen.Color := $B8B8B8;
  for i := -5 to 5 do
  begin
    ToScreen(v, vw, vh, i * 10, -G, 0, ax, ay);
    ToScreen(v, vw, vh, i * 10, G, 0, bx, by);
    c.Line(ax, ay, bx, by);
    ToScreen(v, vw, vh, -G, i * 10, 0, ax, ay);
    ToScreen(v, vw, vh, G, i * 10, 0, bx, by);
    c.Line(ax, ay, bx, by);
  end;
end;

{ X red, Y green, Z blue, bottom left. Drawn without zoom so it stays the same size. }
procedure DrawTriad(c: TCanvas; const v: TView; vh: Integer);
var
  ox, oy: Integer;
  sx, sy: Double;

  procedure Axis(x, y, z: Double; col: TColor; const t: string);
  begin
    ProjectRaw(v, x, y, z, sx, sy);
    c.Pen.Color := col;
    c.Line(ox, oy, ox + Round(sx), oy - Round(sy));
    c.Font.Color := col;
    c.TextOut(ox + Round(sx) + 2, oy - Round(sy) - 7, t);
  end;

begin
  ox := 40; oy := vh - 40;
  c.Brush.Style := bsClear;
  Axis(25, 0, 0, clRed, 'X');
  Axis(0, 25, 0, $008000, 'Y');
  Axis(0, 0, 25, clBlue, 'Z');
  c.Brush.Style := bsSolid;
end;

procedure DrawScene(c: TCanvas; const v: TView; vw, vh: Integer; const e: TEdgeArray; n: Integer);
var
  i: Integer;
begin
  c.Brush.Color := $E0E0E0;
  c.FillRect(0, 0, vw, vh);
  DrawGrid(c, v, vw, vh);
  for i := 0 to n - 1 do
    DrawEdge(c, v, vw, vh, e[i]);
  DrawTriad(c, v, vh);
end;

end.
