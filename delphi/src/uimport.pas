{ uImport - File > Open on a real SolidCraft design (.solidcraft). A port of
  the Windows version's modImport.

  A .solidcraft file is a ZIP holding document.json, the design's feature
  history (a plain-JSON design works too). We rebuild what SolidCraft 98 can
  build: flat sketches of rectangles (rounded or not) and circles, extrudes,
  revolves about the sketch's Y axis, and straight-down holes. Everything
  else stays in the timeline as "Requires SolidCraft 2000". A feature comes
  over whole or not at all. }
unit uImport;

{$mode objfpc}{$H+}

interface

uses uModel;

function IsSolidCraftDesign(const APath: string): Boolean;
{ False if it can't be read: AError says why. ANotice is what to tell the
  user afterwards (features left out), or ''. }
function ImportSolidCraft(const APath: string; var d: TDesign; out ANotice, AError: string): Boolean;

implementation

uses SysUtils, Classes, Math, uKernel, uJson, uZip, uExpr;

const
  IEPS = 0.001;            // mm: "the same height"
  PK_RECT = 1; PK_CIRCLE = 2;

type
  TProfile = record
    Kind: Integer;
    X, Y: Double;          // rectangle: lower-left corner; circle: centre (world)
    W, H: Double;          // rectangle size, or circle radius in W
    R: Double;             // rectangle corner radius
    Parent: Integer;       // -1 for an outline, else the outline it's a hole in
  end;

  TSketchInfo = record
    Id: Integer;
    Name: string;
    Ok: Boolean;
    Why: string;
    Z, OX, OY: Double;
    OnFace, Used: Boolean;
    P: array of TProfile;
    NP: Integer;
  end;

  TIntArray = array of Integer;

var
  Sk: array of TSketchInfo;
  NSk: Integer;
  ParamName, ParamExpr: array of string;
  NParam: Integer;
  ForeignText: string;
  NForeign: Integer;
  Full: Boolean;

function FileTitle(const p: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(p), '');
end;

function IsSolidCraftDesign(const APath: string): Boolean;
var
  fs: TFileStream;
  b: array[0..3] of Byte;
  i: Integer;
begin
  Result := False;
  try
    fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    if fs.Read(b, 4) < 4 then Exit;
  finally
    fs.Free;
  end;
  if (b[0] = $50) and (b[1] = $4B) and (b[2] = 3) and (b[3] = 4) then Exit(True);   // a ZIP
  for i := 0 to 3 do                                                      // or plain JSON
  begin
    if b[i] = $7B then Exit(True);
    if not (b[i] in [32, 9, 10, 13, $EF, $BB, $BF]) then Break;
  end;
end;

function PrettyType(s: string): string;
begin
  s := StringReplace(s, '_', ' ', [rfReplaceAll]);
  Result := UpperCase(Copy(s, 1, 1)) + Copy(s, 2, MaxInt);
end;

function AddRaw(var d: TDesign; f: TFeature; const AName: string): Integer;
begin
  if d.Count >= MAX_FEATURES then
  begin
    Full := True;
    Exit(0);
  end;
  Inc(d.Count);
  f.Name := Copy(AName, 1, 24);
  d.F[d.Count] := f;
  Result := d.Count;
end;

procedure Foreign(var d: TDesign; fNode: Integer; const AWhat, AWhy: string);
var
  f: TFeature;
  nm: string;
begin
  f := Default(TFeature);
  nm := JStr(JGet(fNode, 'name'));
  if nm = '' then nm := AWhat;
  f.Kind := FK_FOREIGN;
  f.Info := Copy(AWhat, 1, 32);
  AddRaw(d, f, nm);
  Inc(NForeign);
  if NForeign <= 12 then
  begin
    ForeignText := ForeignText + '    ' + nm + ' (' + LowerCase(AWhat);
    if AWhy <> '' then ForeignText := ForeignText + ': ' + AWhy;
    ForeignText := ForeignText + ')' + LineEnding;
  end
  else if NForeign = 13 then
    ForeignText := ForeignText + '    ...and more.' + LineEnding;
end;

procedure LoadParams(ps: Integer);
var
  i, p: Integer;
begin
  NParam := JCount(ps);
  SetLength(ParamName, NParam + 1);
  SetLength(ParamExpr, NParam + 1);
  for i := 0 to NParam - 1 do
  begin
    p := JItem(ps, i);
    ParamName[i] := JStr(JGet(p, 'name'));
    ParamExpr[i] := JStr(JGet(p, 'expr'));
  end;
end;

{ The value of an expression like "6", "12 mm", "d1 / 2", "90 deg". }
function EvalExpr(s: string; out ok: Boolean; depth: Integer = 0): Double;
var
  outS, word: string;
  i, j, k: Integer;
  v: Double;
begin
  ok := False;
  Result := 0;
  if depth > 20 then Exit;
  s := StringReplace(s, #194#176, '', [rfReplaceAll]);       // the degree sign
  outS := '';
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] in ['A'..'Z', 'a'..'z', '_'] then
    begin
      j := i;
      while (j <= Length(s)) and (s[j] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(j);
      word := Copy(s, i, j - i);
      case LowerCase(word) of
        'mm', 'deg', 'degree', 'degrees': ;
        'cm': outS := outS + '*10';
        'm': outS := outS + '*1000';
        'in', 'inch': outS := outS + '*25.4';
        'rad': outS := outS + '*57.2957795130823';
        'pi': outS := outS + '3.14159265358979';
      else
        k := 0;
        while (k < NParam) and (ParamName[k] <> word) do Inc(k);
        if k >= NParam then Exit;
        v := EvalExpr(ParamExpr[k], ok, depth + 1);
        if not ok then Exit;
        outS := outS + '(' + StringReplace(FloatToStr(v), DefaultFormatSettings.DecimalSeparator, '.', []) + ')';
      end;
      i := j;
    end
    else
    begin
      outS := outS + s[i];
      Inc(i);
    end;
  end;
  Result := Evaluate(outS);
  ok := ExprError = 0;
end;

function NodeValue(n: Integer; out ok: Boolean): Double;
begin
  if JKind(n) = JS_NUM then
  begin
    ok := True;
    Exit(JNum(n));
  end;
  if JKind(n) = JS_STR then Exit(EvalExpr(JStr(n), ok));
  ok := False;
  Result := 0;
end;

function Near(a, b: Double): Boolean; inline;
begin
  Result := Abs(a - b) < IEPS;
end;

{ Floating-point dust from the source (5.9999999999999964) back to the round number. }
function Snap(v: Double): Double;
begin
  Result := RoundTo(v, -6);
  if Abs(Result) < 0.000001 then Result := 0;
end;

procedure NotOk(var s: TSketchInfo; const why: string);
begin
  if s.Ok then
  begin
    s.Ok := False;
    s.Why := why;
  end;
end;

procedure GrowBox(x, y: Double; var minX, maxX, minY, maxY: Double);
begin
  if x < minX then minX := x;
  if x > maxX then maxX := x;
  if y < minY then minY := y;
  if y > maxY then maxY := y;
end;

procedure AddProfile(var s: TSketchInfo; kind: Integer; x, y, w, h, r: Double);
begin
  if s.NP >= Length(s.P) then SetLength(s.P, s.NP * 2 + 8);
  s.P[s.NP].Kind := kind;
  s.P[s.NP].X := x; s.P[s.NP].Y := y; s.P[s.NP].W := w; s.P[s.NP].H := h; s.P[s.NP].R := r;
  s.P[s.NP].Parent := -1;
  Inc(s.NP);
end;

procedure ProfileAsFeature(const p: TProfile; out t: TFeature);
begin
  t := Default(TFeature);
  if p.Kind = PK_CIRCLE then
  begin
    t.Kind := FK_SKETCH_CIRCLE; t.X := p.X; t.Y := p.Y; t.P1 := p.W;
  end
  else
  begin
    t.Kind := FK_SKETCH_RECT; t.X := p.X; t.Y := p.Y; t.P1 := p.W; t.P2 := p.H; t.P3 := p.R;
  end;
end;

{ A circle inside another outline is a hole in it. One level deep. }
procedure FindHoles(var s: TSketchInfo);
var
  i, j: Integer;
  t: TFeature;
begin
  for i := 0 to s.NP - 1 do
    if s.P[i].Kind = PK_CIRCLE then
      for j := 0 to s.NP - 1 do
        if (j <> i) and (s.P[j].Parent = -1) then
        begin
          ProfileAsFeature(s.P[j], t);
          if ProfileContains(t, s.P[i].X, s.P[i].Y, s.P[i].W) then
            if not ((s.P[j].Kind = PK_CIRCLE) and (s.P[j].W <= s.P[i].W)) then
            begin
              s.P[i].Parent := j;
              Break;
            end;
        end;
  for i := 0 to s.NP - 1 do
    if (s.P[i].Parent >= 0) and (s.P[s.P[i].Parent].Parent >= 0) then NotOk(s, 'islands inside holes');
end;

procedure ReboxRounded(const px, py: TDoubleArray; curves: Integer; var minX, maxX, minY, maxY: Double);
var
  i, c, a: Integer;
  cx, cy, r: Double;
begin
  for i := 0 to JCount(curves) - 1 do
  begin
    c := JItem(curves, i);
    if (JStr(JGet(c, 'type')) = 'arc') and not JBool(JGet(c, 'construction')) and (JGet(c, 'link') = 0) then
    begin
      cx := px[Round(JNum(JGet(c, 'c')))]; cy := py[Round(JNum(JGet(c, 'c')))];
      a := Round(JNum(JGet(c, 'a')));
      r := Sqrt(Sqr(px[a] - cx) + Sqr(py[a] - cy));
      GrowBox(cx - r, cy - r, minX, maxX, minY, maxY);
      GrowBox(cx + r, cy + r, minX, maxX, minY, maxY);
    end;
  end;
end;

procedure ReadSketch(f: Integer);
var
  s: TSketchInfo;
  plane, pl, skn, pts, curves, np, i, c, nLine, nArc, a, b, ci: Integer;
  ok: Boolean;
  v, minX, maxX, minY, maxY, rr: Double;
  sType: string;
  px, py: TDoubleArray;
begin
  s := Default(TSketchInfo);
  s.Id := Round(JNum(JGet(f, 'id')));
  s.Name := JStr(JGet(f, 'name'));
  s.Ok := True;
  // where the sketch is: the XY plane, or a flat face pointing straight up
  plane := JGet(f, 'plane');
  case JStr(JGet(plane, 'type')) of
    'origin':
      if JStr(JGet(plane, 'name')) <> 'XY' then
        NotOk(s, 'drawn on the ' + JStr(JGet(plane, 'name')) + ' plane')
      else if JGet(plane, 'offset') > 0 then
      begin
        v := NodeValue(JGet(plane, 'offset'), ok);
        if ok then s.Z := v else NotOk(s, 'an offset SolidCraft 98 can''t work out');
      end;
    'face':
      begin
        pl := JGet(plane, 'plane');
        if not (Near(JNum(JItem(JGet(pl, 'x_dir'), 0)), 1) and Near(JNum(JItem(JGet(pl, 'y_dir'), 1)), 1)) then
          NotOk(s, 'drawn on a face that doesn''t point straight up')
        else
        begin
          s.OX := JNum(JItem(JGet(pl, 'origin'), 0));
          s.OY := JNum(JItem(JGet(pl, 'origin'), 1));
          s.Z := JNum(JItem(JGet(pl, 'origin'), 2));
          s.OnFace := True;
        end;
      end;
  else
    NotOk(s, 'drawn on a construction plane');
  end;
  if JBool(JGet(plane, 'flip')) then NotOk(s, 'drawn on a flipped plane');

  skn := JGet(f, 'sketch');
  pts := JGet(skn, 'points');
  np := JCount(pts);
  SetLength(px, Max(np, 1)); SetLength(py, Max(np, 1));
  for i := 0 to np - 1 do
  begin
    px[i] := s.OX + JNum(JItem(JGet(JItem(pts, i), 'pos'), 0));
    py[i] := s.OY + JNum(JItem(JGet(JItem(pts, i), 'pos'), 1));
  end;

  // circles are profiles of their own; lines and arcs have to make one rectangle
  curves := JGet(skn, 'curves');
  minX := 1E30; minY := 1E30; maxX := -1E30; maxY := -1E30; rr := -1;
  nLine := 0; nArc := 0;
  for i := 0 to JCount(curves) - 1 do
  begin
    c := JItem(curves, i);
    if JBool(JGet(c, 'construction')) or (JGet(c, 'link') <> 0) then Continue;
    sType := JStr(JGet(c, 'type'));
    case sType of
      'circle':
        begin
          ci := Round(JNum(JGet(c, 'c')));
          if (ci >= 0) and (ci < np) then AddProfile(s, PK_CIRCLE, px[ci], py[ci], JNum(JGet(c, 'r')), 0, 0);
        end;
      'line':
        begin
          a := Round(JNum(JGet(c, 'a'))); b := Round(JNum(JGet(c, 'b')));
          if (a < 0) or (a >= np) or (b < 0) or (b >= np) then begin NotOk(s, 'a broken line'); Continue; end;
          if not (Near(px[a], px[b]) or Near(py[a], py[b])) then NotOk(s, 'a line that isn''t horizontal or vertical');
          GrowBox(px[a], py[a], minX, maxX, minY, maxY);
          GrowBox(px[b], py[b], minX, maxX, minY, maxY);
          Inc(nLine);
        end;
      'arc':
        begin
          a := Round(JNum(JGet(c, 'a'))); b := Round(JNum(JGet(c, 'c')));
          if (a < 0) or (a >= np) or (b < 0) or (b >= np) then begin NotOk(s, 'a broken arc'); Continue; end;
          v := Sqrt(Sqr(px[a] - px[b]) + Sqr(py[a] - py[b]));
          if (rr >= 0) and not Near(v, rr) then NotOk(s, 'corners of different sizes');
          rr := v;
          Inc(nArc);
        end;
    else
      NotOk(s, 'a ' + sType);
    end;
  end;
  if (nLine > 0) or (nArc > 0) then
  begin
    if (nLine = 4) and ((nArc = 0) or (nArc = 4)) then
    begin
      if nArc = 0 then rr := 0;
      if rr > 0 then ReboxRounded(px, py, curves, minX, maxX, minY, maxY);
      AddProfile(s, PK_RECT, minX, minY, maxX - minX, maxY - minY, rr);
    end
    else
      NotOk(s, 'a shape that isn''t a rectangle or a circle');
  end;
  if (s.NP = 0) and s.Ok then NotOk(s, 'nothing SolidCraft 98 can draw');
  if s.Ok then FindHoles(s);
  if NSk >= Length(Sk) then SetLength(Sk, NSk * 2 + 16);
  Sk[NSk] := s;
  Inc(NSk);
end;

function FindSketch(id: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to NSk - 1 do
    if Sk[i].Id = id then Exit(i);
  Result := -1;
end;

function ExtrudeWithTopAt(const d: TDesign; z, x, y, r: Double): Integer;
var
  i: Integer;
  z0, z1: Double;
begin
  for i := d.Count downto 1 do
    if (d.F[i].Kind = FK_EXTRUDE) and RefOk(d, i) then
    begin
      ExtrudeRange(d, i, z0, z1);
      if (Abs(z1 - z) < IEPS) and ProfileContains(d.F[d.F[i].Ref], x, y, r) then Exit(i);
    end;
  Result := 0;
end;

function CountOutlines(k: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Sk[k].NP - 1 do
    if Sk[k].P[i].Parent = -1 then Inc(Result);
end;

function OutlineProfile(k, n: Integer): Integer;
var
  i, c: Integer;
begin
  c := 0;
  for i := 0 to Sk[k].NP - 1 do
    if Sk[k].P[i].Parent = -1 then
    begin
      if c = n then Exit(i);
      Inc(c);
    end;
  Result := 0;
end;

{ Adds one SolidCraft 98 sketch per outline of sketch k, at height z. A
  sketch on a face sits on the extrude under it. }
procedure EmitSketches(var d: TDesign; k: Integer; z: Double; out idx: TIntArray);
var
  i, n, onExt: Integer;
  z0, z1: Double;
  f: TFeature;
  nm: string;
begin
  SetLength(idx, CountOutlines(k) + 1);
  Sk[k].Used := True;
  n := 0;
  for i := 0 to Sk[k].NP - 1 do
    if Sk[k].P[i].Parent = -1 then
    begin
      ProfileAsFeature(Sk[k].P[i], f);
      onExt := 0;
      if Sk[k].OnFace and (Abs(z - Sk[k].Z) < IEPS) then onExt := ExtrudeWithTopAt(d, z, f.X, f.Y, 0);
      if onExt > 0 then
      begin
        ExtrudeRange(d, onExt, z0, z1);
        f.Ref := onExt;
        f.Z := Snap(z - z1);
      end
      else
        f.Z := Snap(z);
      Inc(n);
      nm := Sk[k].Name;
      if CountOutlines(k) > 1 then nm := Copy(nm, 1, 20) + ' ' + IntToStr(n);
      idx[n - 1] := AddRaw(d, f, nm);
    end;
end;

procedure ImportCut(var d: TDesign; f, k: Integer; dist: Double; through: Boolean);
var
  i, c, n: Integer;
  nm: string;
  targets: TIntArray;
  hole: TFeature;
begin
  nm := JStr(JGet(f, 'name'));
  n := Sk[k].NP;
  SetLength(targets, n + 1);
  // check every circle first: all or nothing
  for i := 0 to n - 1 do
  begin
    if Sk[k].P[i].Kind <> PK_CIRCLE then
    begin
      Sk[k].Used := True;
      Foreign(d, f, 'Extrude (cut)', 'a cut that isn''t round');
      Exit;
    end;
    targets[i] := ExtrudeWithTopAt(d, Sk[k].Z, Sk[k].P[i].X, Sk[k].P[i].Y, Sk[k].P[i].W);
    if targets[i] = 0 then
    begin
      Sk[k].Used := True;
      Foreign(d, f, 'Extrude (cut)', 'not into the top of a block');
      Exit;
    end;
  end;
  Sk[k].Used := True;
  c := 0;
  for i := 0 to n - 1 do
  begin
    hole := Default(TFeature);
    hole.Kind := FK_HOLE; hole.Ref := targets[i];
    hole.X := Sk[k].P[i].X; hole.Y := Sk[k].P[i].Y; hole.P1 := Sk[k].P[i].W * 2;
    if not through then hole.P2 := dist;
    Inc(c);
    if n > 1 then
    begin
      if AddRaw(d, hole, Copy(nm, 1, 20) + ' ' + IntToStr(c)) = 0 then Exit;
    end
    else if AddRaw(d, hole, nm) = 0 then Exit;
  end;
end;

procedure ImportExtrude(var d: TDesign; f: Integer);
var
  k, ext, n, i, j, h, c: Integer;
  dist, z: Double;
  ok, through: Boolean;
  nm, sDir, sOp: string;
  idx: TIntArray;
  e, hole: TFeature;
begin
  nm := JStr(JGet(f, 'name'));
  k := FindSketch(Round(JNum(JGet(f, 'sketch'))));
  if k < 0 then begin Foreign(d, f, 'Extrude', 'not from a sketch'); Exit; end;
  if not Sk[k].Ok then
  begin
    Sk[k].Used := True;
    Foreign(d, f, 'Extrude', 'its sketch has ' + Sk[k].Why);
    Exit;
  end;
  if JStr(JGet(JGet(f, 'profiles'), 'type')) <> 'all' then begin Foreign(d, f, 'Extrude', 'only some of its sketch''s profiles'); Exit; end;
  if JGet(f, 'taper') > 0 then begin Foreign(d, f, 'Extrude', 'tapered'); Exit; end;
  ext := JGet(f, 'extent');
  if (JGet(ext, 'distance2') > 0) or (JGet(ext, 'to') > 0) or (JGet(ext, 'start_offset') > 0) then
  begin
    Foreign(d, f, 'Extrude', 'an extent SolidCraft 98 doesn''t have');
    Exit;
  end;
  through := JBool(JGet(ext, 'through_all'));
  dist := 0;
  if not through then
  begin
    dist := NodeValue(JGet(ext, 'distance'), ok);
    if not ok or (dist <= 0) then begin Foreign(d, f, 'Extrude', 'a distance SolidCraft 98 can''t work out'); Exit; end;
  end;
  sDir := JStr(JGet(ext, 'direction'));
  sOp := JStr(JGet(f, 'operation'));
  case sOp of
    'cut':
      begin
        ImportCut(d, f, k, dist, through);
        Exit;
      end;
    'new_body', 'new', 'join', 'auto', '': ;
  else
    Foreign(d, f, 'Extrude', PrettyType(sOp));
    Exit;
  end;
  if through then begin Foreign(d, f, 'Extrude', 'through all'); Exit; end;
  z := Sk[k].Z;
  case sDir of
    'negative': z := z - dist;
    'symmetric': z := z - dist / 2;
  end;
  n := CountOutlines(k);
  EmitSketches(d, k, z, idx);
  c := 0;
  for i := 0 to n - 1 do
  begin
    if idx[i] = 0 then Exit;
    e := Default(TFeature);
    e.Kind := FK_EXTRUDE; e.Ref := idx[i]; e.P1 := dist;
    if n > 1 then j := AddRaw(d, e, Copy(nm, 1, 20) + ' ' + IntToStr(i + 1))
    else j := AddRaw(d, e, nm);
    if j = 0 then Exit;
    // circles inside this outline are holes right through it
    for h := 0 to Sk[k].NP - 1 do
      if Sk[k].P[h].Parent = OutlineProfile(k, i) then
      begin
        Inc(c);
        hole := Default(TFeature);
        hole.Kind := FK_HOLE; hole.Ref := j;
        hole.X := Sk[k].P[h].X; hole.Y := Sk[k].P[h].Y; hole.P1 := Sk[k].P[h].W * 2;
        hole.P2 := dist;                   // through this body, and no further
        AddRaw(d, hole, Copy(nm, 1, 17) + ' hole ' + IntToStr(c));
      end;
  end;
end;

procedure ImportRevolve(var d: TDesign; f: Integer);
var
  k, ax, n, i: Integer;
  ang: Double;
  ok: Boolean;
  nm, op: string;
  idx: TIntArray;
  e: TFeature;
begin
  nm := JStr(JGet(f, 'name'));
  k := FindSketch(Round(JNum(JGet(f, 'sketch'))));
  if k < 0 then begin Foreign(d, f, 'Revolve', 'not from a sketch'); Exit; end;
  if not Sk[k].Ok then
  begin
    Sk[k].Used := True;
    Foreign(d, f, 'Revolve', 'its sketch has ' + Sk[k].Why);
    Exit;
  end;
  ax := JGet(f, 'axis');
  if (JStr(JGet(ax, 'type')) <> 'sketch_axis') or (JStr(JGet(ax, 'axis')) <> 'y') then
  begin
    Foreign(d, f, 'Revolve', 'about an axis other than the sketch''s Y');
    Exit;
  end;
  if not Near(Sk[k].OX, 0) then begin Foreign(d, f, 'Revolve', 'about an axis off the origin'); Exit; end;
  op := JStr(JGet(f, 'operation'));
  if (op = 'cut') or (op = 'intersect') then begin Foreign(d, f, 'Revolve', PrettyType(op)); Exit; end;
  if (JStr(JGet(f, 'direction')) = 'symmetric') or (JGet(f, 'angle2') > 0) or (JGet(f, 'to') > 0) then
  begin
    Foreign(d, f, 'Revolve', 'a two-sided or symmetric angle');
    Exit;
  end;
  if JStr(JGet(JGet(f, 'profiles'), 'type')) <> 'all' then begin Foreign(d, f, 'Revolve', 'only some of its sketch''s profiles'); Exit; end;
  if JGet(f, 'angle') > 0 then
  begin
    ang := NodeValue(JGet(f, 'angle'), ok);
    if not ok then begin Foreign(d, f, 'Revolve', 'an angle SolidCraft 98 can''t work out'); Exit; end;
  end
  else
    ang := 360;
  if (ang = 0) or (Abs(ang) > 360) then begin Foreign(d, f, 'Revolve', 'an angle over 360 degrees'); Exit; end;
  for i := 0 to Sk[k].NP - 1 do
    with Sk[k].P[i] do
    begin
      if Parent >= 0 then begin Foreign(d, f, 'Revolve', 'a profile with a hole in it'); Exit; end;
      if Kind = PK_CIRCLE then
      begin
        if (X - W < -IEPS) and (X + W > IEPS) then begin Foreign(d, f, 'Revolve', 'a profile across the axis'); Exit; end;
      end
      else if (X < -IEPS) and (X + W > IEPS) then begin Foreign(d, f, 'Revolve', 'a profile across the axis'); Exit; end;
    end;
  n := CountOutlines(k);
  EmitSketches(d, k, Sk[k].Z, idx);
  for i := 0 to n - 1 do
  begin
    if idx[i] = 0 then Exit;
    e := Default(TFeature);
    e.Kind := FK_REVOLVE; e.Ref := idx[i];
    e.P1 := -ang;          // SolidCraft turns +X towards +Z; SolidCraft 98 the other way
    if n > 1 then
    begin
      if AddRaw(d, e, Copy(nm, 1, 20) + ' ' + IntToStr(i + 1)) = 0 then Exit;
    end
    else if AddRaw(d, e, nm) = 0 then Exit;
  end;
end;

procedure ImportHole(var d: TDesign; f: Integer);
var
  pos_, dirn, t: Integer;
  x, y, z, dia, depth: Double;
  ok: Boolean;
  kind: string;
  h: TFeature;
begin
  pos_ := JGet(f, 'position');
  if JKind(pos_) <> JS_ARR then begin Foreign(d, f, 'Hole', 'placed on sketch points'); Exit; end;
  dirn := JGet(f, 'direction');
  if dirn > 0 then
    if not (Near(JNum(JItem(dirn, 0)), 0) and Near(JNum(JItem(dirn, 1)), 0) and (JNum(JItem(dirn, 2)) < 0)) then
    begin
      Foreign(d, f, 'Hole', 'not straight down');
      Exit;
    end;
  kind := JStr(JGet(JGet(f, 'hole'), 'type'));
  if (kind <> '') and (kind <> 'simple') and (kind <> 'drilled') then begin Foreign(d, f, 'Hole', PrettyType(kind)); Exit; end;
  if JGet(f, 'diameter') = 0 then begin Foreign(d, f, 'Hole', 'a clearance or tapped size'); Exit; end;
  dia := NodeValue(JGet(f, 'diameter'), ok);
  if not ok or (dia <= 0) then begin Foreign(d, f, 'Hole', 'a diameter SolidCraft 98 can''t work out'); Exit; end;
  depth := 0;
  if JGet(f, 'depth') > 0 then
  begin
    depth := NodeValue(JGet(f, 'depth'), ok);
    if not ok or (depth <= 0) then begin Foreign(d, f, 'Hole', 'a depth SolidCraft 98 can''t work out'); Exit; end;
  end;
  if JGet(f, 'to') > 0 then begin Foreign(d, f, 'Hole', 'drilled to an object'); Exit; end;
  x := NodeValue(JItem(pos_, 0), ok); y := NodeValue(JItem(pos_, 1), ok); z := NodeValue(JItem(pos_, 2), ok);
  t := ExtrudeWithTopAt(d, z, x, y, dia / 2);
  if t = 0 then begin Foreign(d, f, 'Hole', 'not on the top of a block SolidCraft 98 built'); Exit; end;
  h := Default(TFeature);
  h.Kind := FK_HOLE; h.Ref := t; h.X := x; h.Y := y; h.P1 := dia; h.P2 := depth;
  AddRaw(d, h, JStr(JGet(f, 'name')));
end;

function ImportSolidCraft(const APath: string; var d: TDesign; out ANotice, AError: string): Boolean;
var
  txt: RawByteString;
  n, root, feats, k, f: Integer;
  fmt, sType: string;
  ms: TMemoryStream;
  unused: TIntArray;
begin
  Result := False;
  ANotice := ''; AError := '';
  n := ZipReadEntry(APath, 'document.json', txt);
  if ZipErr <> '' then
  begin
    AError := 'Can''t read ''' + APath + ''' as a SolidCraft design.' + LineEnding + LineEnding + ZipErr;
    Exit;
  end;
  if n < 0 then                         // not a ZIP: a plain JSON design
  begin
    ms := TMemoryStream.Create;
    try
      try
        ms.LoadFromFile(APath);
      except
        AError := 'File not found: ' + APath;
        Exit;
      end;
      SetLength(txt, ms.Size);
      if ms.Size > 0 then Move(ms.Memory^, txt[1], ms.Size);
    finally
      ms.Free;
    end;
  end;
  root := JsonParse(txt);
  if JsonErr <> '' then
  begin
    AError := 'Can''t read ''' + APath + ''' as a SolidCraft design.' + LineEnding + LineEnding + JsonErr;
    Exit;
  end;
  fmt := JStr(JGet(root, 'format'));
  feats := JGet(root, 'features');
  if (JKind(feats) <> JS_ARR) or ((Copy(fmt, 1, 11) <> 'solidcraft/') and (Copy(fmt, 1, 11) <> 'solvecraft/')) then
  begin
    AError := '''' + APath + ''' isn''t a SolidCraft design that SolidCraft 98 can read.';
    Exit;
  end;
  NewDesign(d, Copy(JStr(JGet(root, 'name')), 1, 64));
  if Trim(d.Title) = '' then d.Title := FileTitle(APath);
  LoadParams(JGet(root, 'params'));
  NSk := 0;
  SetLength(Sk, 16);
  ForeignText := ''; NForeign := 0; Full := False;
  for k := 0 to JCount(feats) - 1 do
  begin
    f := JItem(feats, k);
    sType := JStr(JGet(f, 'type'));
    case sType of
      'sketch': ReadSketch(f);
      'extrude': ImportExtrude(d, f);
      'revolve': ImportRevolve(d, f);
      'hole': ImportHole(d, f);
    else
      Foreign(d, f, PrettyType(sType), '');
    end;
  end;
  // sketches nothing was built from still show up, if they can be drawn
  for k := 0 to NSk - 1 do
    if Sk[k].Ok and not Sk[k].Used then EmitSketches(d, k, Sk[k].Z, unused);
  if NForeign > 0 then
    ANotice := 'This design was made in SolidCraft. SolidCraft 98 has opened what it can build.' + LineEnding + LineEnding +
      'These features require SolidCraft 2000 and have been left out:' + LineEnding + ForeignText + LineEnding +
      'They''re still in the timeline.';
  if Full then
  begin
    if ANotice <> '' then ANotice := ANotice + LineEnding + LineEnding;
    ANotice := ANotice + 'The design has more features than a SolidCraft 98 part can hold (' + IntToStr(MAX_FEATURES) + ').' +
      LineEnding + 'The rest have been left out.';
  end;
  Result := True;
end;

end.
