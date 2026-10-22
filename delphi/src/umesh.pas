{ uMesh - turns the part into triangles: for Export for Rapid Prototyping
  (.stl) and for the shaded view. A port of the Windows version's modMesh:
  closed and outward-facing, holes cut through, and a body standing wholly
  on another's top face joined to it. }
unit uMesh;

{$mode objfpc}{$H+}

interface

uses uModel, uKernel;

const
  MESH_SEGS = 64;

type
  TTri = record
    X1, Y1, Z1, X2, Y2, Z2, X3, Y3, Z3: Double;
    Body: Integer;            // the feature that made it (a hole's walls are the hole's)
  end;
  TTriArray = array of TTri;

{ Fills t with the part's triangles and returns how many. sErr says which
  bodies couldn't be meshed, if any (they're left out). }
function MeshDesign(const d: TDesign; out t: TTriArray; nSegs: Integer; out sErr: string): Integer;
procedure TriNormal(const t: TTri; out nx, ny, nz: Double);

implementation

uses SysUtils;

const
  EPS = 0.000001;

type
  THole = record
    X, Y, R, ZTop, ZBot: Double;
    Feat: Integer;
  end;
  THoleArray = array of THole;
  TLongArray = array of LongInt;

var
  mT: TTriArray;
  mN: Integer;
  mErr: string;
  mSegs: Integer;
  mJoin: array of Integer;
  mLX, mLY: TDoubleArray;
  mLS, mLN: array of Integer;
  mNL: Integer;

procedure TriNormal(const t: TTri; out nx, ny, nz: Double);
var
  ux, uy, uz, vx, vy, vz, l: Double;
begin
  ux := t.X2 - t.X1; uy := t.Y2 - t.Y1; uz := t.Z2 - t.Z1;
  vx := t.X3 - t.X1; vy := t.Y3 - t.Y1; vz := t.Z3 - t.Z1;
  nx := uy * vz - uz * vy; ny := uz * vx - ux * vz; nz := ux * vy - uy * vx;
  l := Sqrt(nx * nx + ny * ny + nz * nz);
  if l = 0 then l := 1;
  nx := nx / l; ny := ny / l; nz := nz / l;
end;

procedure AddTri(x1, y1, z1, x2, y2, z2, x3, y3, z3: Double; body: Integer);
begin
  // a corner on the axis of a revolve makes slivers with two corners the
  // same; they have no area, and leaving them out keeps the mesh closed
  if (x1 = x2) and (y1 = y2) and (z1 = z2) then Exit;
  if (x2 = x3) and (y2 = y3) and (z2 = z3) then Exit;
  if (x3 = x1) and (y3 = y1) and (z3 = z1) then Exit;
  if mN >= Length(mT) then SetLength(mT, Length(mT) * 2 + 64);
  // no "with" here: Pascal ignores case, so X1 := x1 would set a field to itself
  mT[mN].X1 := x1; mT[mN].Y1 := y1; mT[mN].Z1 := z1;
  mT[mN].X2 := x2; mT[mN].Y2 := y2; mT[mN].Z2 := z2;
  mT[mN].X3 := x3; mT[mN].Y3 := y3; mT[mN].Z3 := z3;
  mT[mN].Body := body;
  Inc(mN);
end;

procedure OrientOutward(a, b: Integer);
var
  i: Integer;
  v, t: Double;
begin
  v := 0;
  for i := a to b - 1 do
    with mT[i] do
      v := v + (X1 * (Y2 * Z3 - Y3 * Z2) - X2 * (Y1 * Z3 - Y3 * Z1) + X3 * (Y1 * Z2 - Y2 * Z1));
  if v >= 0 then Exit;
  for i := a to b - 1 do
    with mT[i] do
    begin
      t := X2; X2 := X3; X3 := t;
      t := Y2; Y2 := Y3; Y3 := t;
      t := Z2; Z2 := Z3; Z3 := t;
    end;
end;

function Orient(ax, ay, bx, by, cx, cy: Double): Double; inline;
begin
  Result := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
end;

function Crosses(ax, ay, bx, by, cx, cy, dx, dy: Double): Boolean;
var
  d1, d2, d3, d4: Double;
begin
  if ((ax = cx) and (ay = cy)) or ((ax = dx) and (ay = dy)) or ((bx = cx) and (by = cy)) or ((bx = dx) and (by = dy)) then
    Exit(False);
  d1 := Orient(cx, cy, dx, dy, ax, ay);
  d2 := Orient(cx, cy, dx, dy, bx, by);
  d3 := Orient(ax, ay, bx, by, cx, cy);
  d4 := Orient(ax, ay, bx, by, dx, dy);
  Result := ((d1 > 0) <> (d2 > 0)) and ((d3 > 0) <> (d4 > 0));
end;

function CleanOutline(var ox, oy: TDoubleArray; n: Integer): Integer;
var
  i, m: Integer;
  a, t: Double;
begin
  m := 0;
  for i := 0 to n - 1 do
    if (m = 0) or (Abs(ox[i] - ox[m - 1]) > 1e-9) or (Abs(oy[i] - oy[m - 1]) > 1e-9) then
    begin
      ox[m] := ox[i]; oy[m] := oy[i]; Inc(m);
    end;
  while m > 1 do
  begin
    if (Abs(ox[m - 1] - ox[0]) > 1e-9) or (Abs(oy[m - 1] - oy[0]) > 1e-9) then Break;
    Dec(m);
  end;
  a := 0;
  for i := 0 to m - 1 do
    a := a + ox[i] * oy[(i + 1) mod m] - ox[(i + 1) mod m] * oy[i];
  if a < 0 then
    for i := 0 to m div 2 - 1 do
    begin
      t := ox[i]; ox[i] := ox[m - 1 - i]; ox[m - 1 - i] := t;
      t := oy[i]; oy[i] := oy[m - 1 - i]; oy[m - 1 - i] := t;
    end;
  Result := m;
end;

procedure CircleLoop(cx, cy, r: Double; out px, py: TDoubleArray);
var
  k: Integer;
begin
  SetLength(px, mSegs); SetLength(py, mSegs);
  for k := 0 to mSegs - 1 do
  begin
    px[k] := cx + r * Cos(2 * Pi * k / mSegs);
    py[k] := cy + r * Sin(2 * Pi * k / mSegs);
  end;
end;

function Inside(const px, py: TDoubleArray; n: Integer; x, y: Double): Integer;
const
  TOL = 0.0000001;
var
  k: Integer;
  o: Double;
  onEdge: Boolean;
begin
  onEdge := False;
  for k := 0 to n - 1 do
  begin
    o := Orient(px[k], py[k], px[(k + 1) mod n], py[(k + 1) mod n], x, y);
    if o < -TOL then Exit(-1);
    if o <= TOL then onEdge := True;
  end;
  if onEdge then Result := 0 else Result := 1;
end;

{ Two convex anticlockwise outlines: 1 if B is wholly inside A, 0 if they
  don't meet, -1 if they overlap or touch. }
function Relation(const ax, ay: TDoubleArray; na: Integer; const bx, by: TDoubleArray; nb: Integer): Integer;
var
  k, j: Integer;
  allIn, anyIn: Boolean;
begin
  allIn := True; anyIn := False;
  for k := 0 to nb - 1 do
    case Inside(ax, ay, na, bx[k], by[k]) of
      1: anyIn := True;
      0: begin anyIn := True; allIn := False; end;
    else
      allIn := False;
    end;
  if allIn then Exit(1);
  if anyIn then Exit(-1);
  for k := 0 to na - 1 do
    if Inside(bx, by, nb, ax[k], ay[k]) >= 0 then Exit(-1);
  for k := 0 to na - 1 do
    for j := 0 to nb - 1 do
      if Crosses(ax[k], ay[k], ax[(k + 1) mod na], ay[(k + 1) mod na], bx[j], by[j], bx[(j + 1) mod nb], by[(j + 1) mod nb]) then
        Exit(-1);
  Result := 0;
end;

function GetBody(const d: TDesign; i: Integer; out z0, z1: Double; out ox, oy: TDoubleArray; out no: Integer): Boolean;
var
  seam: TBoolArray;
  t: Double;
begin
  no := 0;
  ExtrudeRange(d, i, z0, z1);
  if z1 < z0 then begin t := z0; z0 := z1; z1 := t; end;
  if z1 - z0 < EPS then Exit(False);
  no := ProfilePoints(d.F[d.F[i].Ref], ox, oy, seam, mSegs);
  no := CleanOutline(ox, oy, no);
  Result := no >= 3;
end;

function IsBody(const d: TDesign; i: Integer): Boolean;
begin
  Result := (d.F[i].Kind = FK_EXTRUDE) and (d.F[i].Suppressed = 0) and RefOk(d, i);
end;

function CollectHoles(const d: TDesign; i: Integer; z1: Double; out h: THoleArray): Integer;
var
  j, n: Integer;
  zt, zb, r: Double;
begin
  SetLength(h, 8);
  n := 0;
  for j := i + 1 to d.Count do
    if (d.F[j].Kind = FK_HOLE) and (d.F[j].Suppressed = 0) and RefOk(d, j) then
    begin
      r := d.F[j].P1 / 2;
      if ProfileContains(d.F[d.F[i].Ref], d.F[j].X, d.F[j].Y, r) then
      begin
        HoleSpan(d, j, zt, zb);
        if (zt >= z1 - EPS) and (zb <= z1 + EPS) then
        begin
          if n >= Length(h) then SetLength(h, n * 2);
          h[n].X := d.F[j].X; h[n].Y := d.F[j].Y; h[n].R := r;
          h[n].ZTop := zt; h[n].ZBot := zb; h[n].Feat := j;
          Inc(n);
        end;
      end;
    end;
  Result := n;
end;

procedure FindJoins(const d: TDesign);
var
  i, j, k, na, nb, nc, nh: Integer;
  ok: Boolean;
  az0, az1, bz0, bz1, cz0, cz1: Double;
  ax, ay, bx, by, cx, cy, hx, hy: TDoubleArray;
  h: THoleArray;
begin
  SetLength(mJoin, d.Count + 1);
  for j := 0 to d.Count do mJoin[j] := 0;
  for j := 1 to d.Count do
    if IsBody(d, j) and GetBody(d, j, bz0, bz1, bx, by, nb) then
      for i := 1 to d.Count do
        if (i <> j) and IsBody(d, i) and GetBody(d, i, az0, az1, ax, ay, na) then
          if Abs(az1 - bz0) < EPS then
          begin
            ok := Relation(ax, ay, na, bx, by, nb) = 1;
            if ok then
            begin
              nh := CollectHoles(d, i, az1, h);
              for k := 0 to nh - 1 do
              begin
                CircleLoop(h[k].X, h[k].Y, h[k].R, hx, hy);
                if Relation(bx, by, nb, hx, hy, mSegs) = -1 then begin ok := False; Break; end;
              end;
            end;
            if ok then
              for k := 1 to j - 1 do
                if mJoin[k] = i then
                begin
                  GetBody(d, k, cz0, cz1, cx, cy, nc);
                  if Relation(cx, cy, nc, bx, by, nb) <> 0 then begin ok := False; Break; end;
                end;
            if ok then
            begin
              mJoin[j] := i;
              Break;
            end;
          end;
end;

procedure HoleWall(cx, cy, r, za, zb: Double; body: Integer);
var
  k, k2: Integer;
  px, py: TDoubleArray;
begin
  CircleLoop(cx, cy, r, px, py);
  for k := 0 to mSegs - 1 do
  begin
    k2 := (k + 1) mod mSegs;
    // wound the other way from an outside wall, so it faces into the hole
    AddTri(px[k2], py[k2], za, px[k], py[k], za, px[k], py[k], zb, body);
    AddTri(px[k2], py[k2], za, px[k], py[k], zb, px[k2], py[k2], zb, body);
  end;
end;

procedure HoleDisc(cx, cy, r, z: Double; bUp: Boolean; body: Integer);
var
  k, k2: Integer;
  px, py: TDoubleArray;
begin
  CircleLoop(cx, cy, r, px, py);
  for k := 0 to mSegs - 1 do
  begin
    k2 := (k + 1) mod mSegs;
    if bUp then AddTri(cx, cy, z, px[k], py[k], z, px[k2], py[k2], z, body)
    else AddTri(cx, cy, z, px[k2], py[k2], z, px[k], py[k], z, body);
  end;
end;

procedure ClearLoops;
begin
  SetLength(mLX, 256); SetLength(mLY, 256);
  SetLength(mLS, 8); SetLength(mLN, 8);
  mNL := 0;
end;

procedure AddLoop(const px, py: TDoubleArray; n: Integer);
var
  k, at: Integer;
begin
  if mNL >= Length(mLS) then begin SetLength(mLS, mNL * 2); SetLength(mLN, mNL * 2); end;
  if mNL = 0 then at := 0 else at := mLS[mNL - 1] + mLN[mNL - 1];
  while at + n > Length(mLX) do begin SetLength(mLX, Length(mLX) * 2); SetLength(mLY, Length(mLY) * 2); end;
  for k := 0 to n - 1 do
  begin
    mLX[at + k] := px[k]; mLY[at + k] := py[k];
  end;
  mLS[mNL] := at; mLN[mNL] := n;
  Inc(mNL);
end;

procedure AddCircleLoop(cx, cy, r: Double);
var
  px, py: TDoubleArray;
begin
  CircleLoop(cx, cy, r, px, py);
  AddLoop(px, py, mSegs);
end;

function SlitIsClear(ax, ay, bx, by: Double; const px, py: TDoubleArray; np: Integer;
  const cx, cy: TDoubleArray; nc: Integer; const done: TBoolArray): Boolean;
var
  k, L, a, b: Integer;
begin
  for k := 0 to np - 1 do
    if Crosses(ax, ay, bx, by, px[k], py[k], px[(k + 1) mod np], py[(k + 1) mod np]) then Exit(False);
  for k := 0 to nc - 1 do
    if Crosses(ax, ay, bx, by, cx[k], cy[k], cx[(k + 1) mod nc], cy[(k + 1) mod nc]) then Exit(False);
  for L := 0 to mNL - 1 do
    if not done[L] then
      for k := 0 to mLN[L] - 1 do
      begin
        a := mLS[L] + k; b := mLS[L] + (k + 1) mod mLN[L];
        if Crosses(ax, ay, bx, by, mLX[a], mLY[a], mLX[b], mLY[b]) then Exit(False);
      end;
  Result := True;
end;

function BridgeLoops(const ox, oy: TDoubleArray; no: Integer; out px, py: TDoubleArray; out np: Integer): Boolean;
var
  i, j, L, pick, nc, k, m, s, bestK, attempt, nn: Integer;
  best, mx, my, dd: Double;
  ok: Boolean;
  cx, cy, nx, ny: TDoubleArray;
  tried, done: TBoolArray;
begin
  px := Copy(ox, 0, no); py := Copy(oy, 0, no);
  np := no;
  if mNL = 0 then Exit(True);
  SetLength(done, mNL);
  for L := 0 to mNL - 1 do done[L] := False;
  s := 0;
  for j := 1 to mNL do
  begin
    best := -1E30; pick := -1;
    for L := 0 to mNL - 1 do
      if not done[L] then
        for k := mLS[L] to mLS[L] + mLN[L] - 1 do
          if mLX[k] > best then begin best := mLX[k]; pick := L; s := k; end;
    done[pick] := True;
    nc := mLN[pick];
    SetLength(cx, nc); SetLength(cy, nc);
    for k := 0 to nc - 1 do
    begin
      i := mLS[pick] + ((s - mLS[pick]) - k + nc) mod nc;
      cx[k] := mLX[i]; cy[k] := mLY[i];
    end;
    mx := cx[0]; my := cy[0];
    SetLength(tried, np);
    for k := 0 to np - 1 do tried[k] := False;
    ok := False;
    bestK := -1;
    for attempt := 1 to np do
    begin
      best := 1E30; bestK := -1;
      for k := 0 to np - 1 do
        if not tried[k] then
        begin
          dd := Sqr(px[k] - mx) + Sqr(py[k] - my);
          if dd < best then begin best := dd; bestK := k; end;
        end;
      if bestK < 0 then Break;
      tried[bestK] := True;
      if SlitIsClear(mx, my, px[bestK], py[bestK], px, py, np, cx, cy, nc, done) then
      begin
        ok := True;
        Break;
      end;
    end;
    if not ok then Exit(False);
    nn := np + nc + 2;
    SetLength(nx, nn); SetLength(ny, nn);
    m := 0;
    for k := 0 to bestK do begin nx[m] := px[k]; ny[m] := py[k]; Inc(m); end;
    for k := 0 to nc - 1 do begin nx[m] := cx[k]; ny[m] := cy[k]; Inc(m); end;
    nx[m] := cx[0]; ny[m] := cy[0]; Inc(m);
    for k := bestK to np - 1 do begin nx[m] := px[k]; ny[m] := py[k]; Inc(m); end;
    px := nx; py := ny;
    nx := nil; ny := nil;
    np := nn;
  end;
  Result := True;
end;

function SamePt(const px, py: TDoubleArray; i, j: Integer): Boolean; inline;
begin
  Result := (px[i] = px[j]) and (py[i] = py[j]);
end;

function EarClip(const px, py: TDoubleArray; n: Integer; out tri: TLongArray; out nt: Integer): Boolean;
var
  i, a, b, c, nLeft, p, guard: Integer;
  isEar, found: Boolean;
  nxt, prv: TLongArray;
begin
  SetLength(nxt, n); SetLength(prv, n);
  SetLength(tri, 3 * n + 3);
  for i := 0 to n - 1 do
  begin
    nxt[i] := (i + 1) mod n;
    prv[i] := (i + n - 1) mod n;
  end;
  nLeft := n; b := 0; nt := 0;
  while nLeft > 3 do
  begin
    found := False;
    for guard := 1 to nLeft do
    begin
      a := prv[b]; c := nxt[b];
      if Orient(px[a], py[a], px[b], py[b], px[c], py[c]) > 1e-9 then
      begin
        // an ear if no other corner pokes into the triangle (every corner,
        // since the slits make the polygon touch itself)
        isEar := True;
        p := nxt[c];
        while p <> a do
        begin
          if not (SamePt(px, py, p, a) or SamePt(px, py, p, b) or SamePt(px, py, p, c)) then
            if (Orient(px[a], py[a], px[b], py[b], px[p], py[p]) >= 0) and
               (Orient(px[b], py[b], px[c], py[c], px[p], py[p]) >= 0) and
               (Orient(px[c], py[c], px[a], py[a], px[p], py[p]) >= 0) then
            begin
              isEar := False;
              Break;
            end;
          p := nxt[p];
        end;
        if isEar then
        begin
          tri[3 * nt] := a; tri[3 * nt + 1] := b; tri[3 * nt + 2] := c;
          Inc(nt);
          nxt[a] := c; prv[c] := a;
          Dec(nLeft);
          b := c;
          found := True;
          Break;
        end;
      end;
      b := nxt[b];
    end;
    if not found then Exit(False);
  end;
  a := prv[b]; c := nxt[b];
  tri[3 * nt] := a; tri[3 * nt + 1] := b; tri[3 * nt + 2] := c;
  Inc(nt);
  Result := True;
end;

function CapLoops(const ox, oy: TDoubleArray; no: Integer; z: Double; bUp: Boolean; body: Integer): Boolean;
var
  px, py: TDoubleArray;
  np, nt, k, a, b, c: Integer;
  tri: TLongArray;
begin
  if not BridgeLoops(ox, oy, no, px, py, np) then Exit(False);
  if not EarClip(px, py, np, tri, nt) then Exit(False);
  for k := 0 to nt - 1 do
  begin
    a := tri[3 * k]; b := tri[3 * k + 1]; c := tri[3 * k + 2];
    if bUp then AddTri(px[a], py[a], z, px[b], py[b], z, px[c], py[c], z, body)
    else AddTri(px[a], py[a], z, px[c], py[c], z, px[b], py[b], z, body);
  end;
  Result := True;
end;

procedure MeshExtrude(const d: TDesign; i: Integer);
var
  z0, z1, fz0, fz1, zb: Double;
  ox, oy, fx, fy, hx, hy: TDoubleArray;
  no, nh, j, k, k2, nf: Integer;
  h: THoleArray;
  inFoot: TBoolArray;
begin
  if not GetBody(d, i, z0, z1, ox, oy, no) then Exit;
  nh := CollectHoles(d, i, z1, h);
  SetLength(inFoot, nh + 1);
  for k := 0 to nh do inFoot[k] := False;

  // the top: the outline less the holes and the bodies standing on it
  ClearLoops;
  for j := 1 to d.Count do
    if mJoin[j] = i then
    begin
      GetBody(d, j, fz0, fz1, fx, fy, nf);
      AddLoop(fx, fy, nf);
      for k := 0 to nh - 1 do
      begin
        CircleLoop(h[k].X, h[k].Y, h[k].R, hx, hy);
        if Relation(fx, fy, nf, hx, hy, mSegs) = 1 then inFoot[k] := True;
      end;
    end;
  for k := 0 to nh - 1 do
    if (not inFoot[k]) and (h[k].ZBot < z1 - EPS) then AddCircleLoop(h[k].X, h[k].Y, h[k].R);
  if not CapLoops(ox, oy, no, z1, True, i) then
  begin
    mErr := mErr + FeatureName(d, i) + ' (its holes are too close together to cap). ';
    Exit;
  end;

  // the bottom, unless it stands on (and is joined to) another body
  if mJoin[i] = 0 then
  begin
    ClearLoops;
    for k := 0 to nh - 1 do
      if h[k].ZBot <= z0 + EPS then AddCircleLoop(h[k].X, h[k].Y, h[k].R);
    CapLoops(ox, oy, no, z0, False, i);
  end;

  // the outside walls
  for k := 0 to no - 1 do
  begin
    k2 := (k + 1) mod no;
    AddTri(ox[k], oy[k], z0, ox[k2], oy[k2], z0, ox[k2], oy[k2], z1, i);
    AddTri(ox[k], oy[k], z0, ox[k2], oy[k2], z1, ox[k], oy[k], z1, i);
  end;

  // the holes: walls facing into them, floors where they stop, and a roof
  // where one starts on this top under a body that stands on it
  for k := 0 to nh - 1 do
  begin
    zb := h[k].ZBot;
    if zb < z0 then zb := z0;
    if zb < z1 - EPS then
    begin
      HoleWall(h[k].X, h[k].Y, h[k].R, zb, z1, h[k].Feat);
      if zb > z0 + EPS then HoleDisc(h[k].X, h[k].Y, h[k].R, zb, True, h[k].Feat);
      if inFoot[k] and (h[k].ZTop <= z1 + EPS) then HoleDisc(h[k].X, h[k].Y, h[k].R, z1, False, h[k].Feat);
    end
    else if inFoot[k] then
      HoleDisc(h[k].X, h[k].Y, h[k].R, z1, True, h[k].Feat);
  end;
end;

procedure MeshRevolve(const d: TDesign; i, nSegs: Integer);
var
  sz, ang, a0, a1: Double;
  px, py: TDoubleArray;
  seam: TBoolArray;
  np, steps, k, j, j2: Integer;
  full: Boolean;
begin
  sz := SketchZ(d, d.F[i].Ref);
  np := ProfilePoints(d.F[d.F[i].Ref], px, py, seam, nSegs);
  np := CleanOutline(px, py, np);
  if (np < 3) or (Abs(d.F[i].P1) < 0.000001) then Exit;
  ang := d.F[i].P1 * Pi / 180;
  full := Abs(Abs(d.F[i].P1) - 360) < 0.000001;
  steps := Trunc(Abs(d.F[i].P1) / 360 * nSegs + 0.5);
  if steps < 2 then steps := 2;
  for k := 0 to steps - 1 do
  begin
    a0 := ang * k / steps;
    if full and (k + 1 = steps) then a1 := 0 else a1 := ang * (k + 1) / steps;
    for j := 0 to np - 1 do
    begin
      j2 := (j + 1) mod np;
      AddTri(px[j] * Cos(a0), py[j], sz - px[j] * Sin(a0),
             px[j2] * Cos(a0), py[j2], sz - px[j2] * Sin(a0),
             px[j2] * Cos(a1), py[j2], sz - px[j2] * Sin(a1), i);
      AddTri(px[j] * Cos(a0), py[j], sz - px[j] * Sin(a0),
             px[j2] * Cos(a1), py[j2], sz - px[j2] * Sin(a1),
             px[j] * Cos(a1), py[j], sz - px[j] * Sin(a1), i);
    end;
  end;
  if not full then
    for j := 1 to np - 2 do
    begin
      AddTri(px[0], py[0], sz, px[j + 1], py[j + 1], sz, px[j], py[j], sz, i);
      AddTri(px[0] * Cos(ang), py[0], sz - px[0] * Sin(ang),
             px[j] * Cos(ang), py[j], sz - px[j] * Sin(ang),
             px[j + 1] * Cos(ang), py[j + 1], sz - px[j + 1] * Sin(ang), i);
    end;
end;

function MeshDesign(const d: TDesign; out t: TTriArray; nSegs: Integer; out sErr: string): Integer;
var
  i, first: Integer;
begin
  SetLength(mT, 1024);
  mN := 0; mErr := ''; mSegs := nSegs;
  FindJoins(d);
  for i := 1 to d.Count do
    if (d.F[i].Suppressed = 0) and RefOk(d, i) then
      case d.F[i].Kind of
        FK_EXTRUDE: MeshExtrude(d, i);
        FK_REVOLVE:
          begin
            first := mN;
            MeshRevolve(d, i, nSegs);
            if mN > first then OrientOutward(first, mN);
          end;
      end;
  t := Copy(mT, 0, mN);
  sErr := mErr;
  Result := mN;
end;

end.
