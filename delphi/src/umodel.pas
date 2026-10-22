{ uModel - the design, and the .sc98 file.

  The file is byte for byte what the Windows version writes with VB's Put:
  a packed record, 2-byte SmallInts, 8-byte Doubles and fixed strings padded
  with spaces. Parts move freely between the editions. Versions 3 and 4
  (smaller records) are read and converted. }
unit uModel;

{$mode objfpc}{$H+}

interface

const
  FILE_MAGIC = 'SC98';
  FILE_VERSION = 5;
  MAX_FEATURES = 64;          // someone once had 41 features

  FK_NONE = 0;
  FK_SKETCH_RECT = 1;
  FK_SKETCH_CIRCLE = 2;
  FK_EXTRUDE = 3;
  FK_REVOLVE = 4;
  FK_HOLE = 5;
  FK_FOREIGN = 9;             // from a SolidCraft design; SolidCraft 98 can't build it

type
  TFeature = record
    Kind: Integer;
    Name: string;
    X, Y, Z: Double;          // sketch origin / hole centre, sketch height, mm
    P1: Double;               // width | radius | depth | angle | diameter
    P2: Double;               // height | - | - | - | hole depth (0 = through all)
    Ref: Integer;             // the feature this one is built on
    Suppressed: Integer;
    P3: Double;               // rectangle corner radius
    Info: string;             // FK_FOREIGN: what it was in SolidCraft ("fillet")
  end;

  TDesign = record
    Title: string;
    Count: Integer;
    F: array[1..MAX_FEATURES] of TFeature;
  end;

  TBoolArray = array of Boolean;

var
  Y2KHappened: Boolean;
  Y2KDimension: function: string = nil;   // set by uTurbo
  LastFileError: string;

procedure NewDesign(var d: TDesign; const ATitle: string);
function KindName(k: Integer): string;
function KindPrefix(k: Integer): string;
function IsSketch(k: Integer): Boolean;
function AddFeature(var d: TDesign; f: TFeature): Integer;
function FeatureName(const d: TDesign; i: Integer): string;
function LastFreeSketch(const d: TDesign): Integer;
function LastSolid(const d: TDesign): Integer;
function MarkDependents(const d: TDesign; i: Integer; out gone: TBoolArray): Integer;
procedure DeleteMarked(var d: TDesign; const gone: TBoolArray);
function Describe(const d: TDesign; i: Integer): string;
function FmtN(v: Double; places: Integer): string;
function Fmt(v: Double): string;
function Fmt0(v: Double): string;
function SaveDesign(const d: TDesign; const APath: string): Boolean;
{ 0 ok, 1 not a part, 2 too new, 3 too old, 4 couldn't read, 5 converted
  from version 3 (say so). LastFileError has the message. }
function LoadDesign(var d: TDesign; const APath: string): Integer;

implementation

uses SysUtils, Classes, Math, LConvEncoding;

type
  TFix24 = array[0..23] of AnsiChar;
  TFix32 = array[0..31] of AnsiChar;
  TFix64 = array[0..63] of AnsiChar;

  TFileFeature = packed record
    Kind: SmallInt;
    Name: TFix24;
    X, Y, Z, P1, P2: Double;
    Ref: SmallInt;
    Suppressed: SmallInt;
    P3: Double;
    Info: TFix32;
    Reserved: array[1..3] of Double;   // so the next version won't break every file (it will anyway)
  end;

  TFileFeatureV4 = packed record
    Kind: SmallInt;
    Name: TFix24;
    X, Y, Z, P1, P2: Double;
    Ref: SmallInt;
    Suppressed: SmallInt;
    P3: Double;
    Reserved: array[1..3] of Double;
  end;

  TFileFeatureV3 = packed record
    Kind: SmallInt;
    Name: TFix24;
    X, Y, Z, P1, P2: Double;
    Ref: SmallInt;
    Suppressed: SmallInt;
  end;

  TFileHeader = packed record
    Magic: array[0..3] of AnsiChar;
    Version: SmallInt;
    Title: TFix64;
    Count: SmallInt;
  end;

procedure NewDesign(var d: TDesign; const ATitle: string);
var
  i: Integer;
  blank: TFeature;
begin
  Finalize(blank);
  FillChar(blank, SizeOf(blank), 0);
  d.Title := ATitle;
  d.Count := 0;
  for i := 1 to MAX_FEATURES do
    d.F[i] := blank;
end;

function KindName(k: Integer): string;
begin
  case k of
    FK_SKETCH_RECT: Result := 'Sketch (Rectangle)';
    FK_SKETCH_CIRCLE: Result := 'Sketch (Circle)';
    FK_EXTRUDE: Result := 'Extrude';
    FK_REVOLVE: Result := 'Revolve';
    FK_HOLE: Result := 'Hole';
    FK_FOREIGN: Result := 'SolidCraft';
  else
    Result := '?';
  end;
end;

function KindPrefix(k: Integer): string;
begin
  case k of
    FK_SKETCH_RECT, FK_SKETCH_CIRCLE: Result := 'Sketch';
    FK_EXTRUDE: Result := 'Extrude';
    FK_REVOLVE: Result := 'Revolve';
    FK_HOLE: Result := 'Hole';
  else
    Result := '';
  end;
end;

function IsSketch(k: Integer): Boolean;
begin
  Result := (k = FK_SKETCH_RECT) or (k = FK_SKETCH_CIRCLE);
end;

function AddFeature(var d: TDesign; f: TFeature): Integer;
var
  i, n: Integer;
begin
  if d.Count >= MAX_FEATURES then Exit(0);
  n := 0;
  for i := 1 to d.Count do
    if KindPrefix(d.F[i].Kind) = KindPrefix(f.Kind) then Inc(n);
  Inc(d.Count);
  f.Name := KindPrefix(f.Kind) + IntToStr(n + 1);
  d.F[d.Count] := f;
  Result := d.Count;
end;

function FeatureName(const d: TDesign; i: Integer): string;
begin
  if (i < 1) or (i > d.Count) then Exit('');
  Result := d.F[i].Name;
end;

function LastFreeSketch(const d: TDesign): Integer;
var
  i, j: Integer;
  used: Boolean;
begin
  for i := d.Count downto 1 do
    if IsSketch(d.F[i].Kind) then
    begin
      used := False;
      for j := i + 1 to d.Count do
        if (d.F[j].Ref = i) and ((d.F[j].Kind = FK_EXTRUDE) or (d.F[j].Kind = FK_REVOLVE)) then used := True;
      if not used then Exit(i);
    end;
  Result := 0;
end;

function LastSolid(const d: TDesign): Integer;
var
  i: Integer;
begin
  for i := d.Count downto 1 do
    if d.F[i].Kind = FK_EXTRUDE then Exit(i);
  Result := 0;
end;

function MarkDependents(const d: TDesign; i: Integer; out gone: TBoolArray): Integer;
var
  j: Integer;
begin
  SetLength(gone, d.Count + 1);
  for j := 0 to d.Count do gone[j] := False;
  gone[i] := True;
  Result := 1;
  for j := i + 1 to d.Count do
    if (d.F[j].Ref >= 1) and (d.F[j].Ref <= d.Count) then
      if gone[d.F[j].Ref] then
      begin
        gone[j] := True;
        Inc(Result);
      end;
end;

procedure DeleteMarked(var d: TDesign; const gone: TBoolArray);
var
  i, n: Integer;
  newIndex: array of Integer;
  blank: TFeature;
begin
  FillChar(blank, SizeOf(blank), 0);
  SetLength(newIndex, d.Count + 1);
  n := 0;
  for i := 1 to d.Count do
    if not gone[i] then
    begin
      Inc(n);
      newIndex[i] := n;
      d.F[n] := d.F[i];
      if d.F[n].Ref >= 1 then d.F[n].Ref := newIndex[d.F[n].Ref];
    end;
  for i := n + 1 to d.Count do
    d.F[i] := blank;
  d.Count := n;
end;

{ 12.5 -> "12.5", 3 -> "3", -0.001 -> "0": a few decimals at most. }
function FmtN(v: Double; places: Integer): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  v := RoundTo(v, -places);
  if Abs(v) < Power(10, -places) / 2 then v := 0;
  Result := FloatToStrF(v, ffFixed, 15, places, fs);
  if Pos('.', Result) > 0 then
  begin
    while Result[Length(Result)] = '0' do Delete(Result, Length(Result), 1);
    if Result[Length(Result)] = '.' then Delete(Result, Length(Result), 1);
  end;
  if Result = '-0' then Result := '0';
end;

function Fmt(v: Double): string;
begin
  if Y2KHappened and Assigned(Y2KDimension) then Exit(Y2KDimension());  // two-digit years were a mistake
  Result := FmtN(v, 2);
end;

function Fmt0(v: Double): string;
begin
  Result := FmtN(v, 3);
end;

function SketchPlace(const d: TDesign; const f: TFeature): string;
begin
  Result := '';
  if f.Ref > 0 then
  begin
    Result := ', on ' + FeatureName(d, f.Ref);
    if f.Z <> 0 then
    begin
      if f.Z > 0 then Result := Result + ' +' else Result := Result + ' ';
      Result := Result + Fmt(f.Z);
    end;
  end
  else if f.Z <> 0 then
    Result := ', Z ' + Fmt(f.Z);
end;

function Describe(const d: TDesign; i: Integer): string;
begin
  Result := '';
  with d.F[i] do
    case Kind of
      FK_SKETCH_RECT:
        begin
          Result := Fmt(P1) + ' x ' + Fmt(P2) + ' mm at (' + Fmt(X) + ', ' + Fmt(Y) + ')';
          if P3 > 0 then Result := Result + ', R' + Fmt(P3) + ' corners';
          Result := Result + SketchPlace(d, d.F[i]);
        end;
      FK_SKETCH_CIRCLE:
        Result := 'R ' + Fmt(P1) + ' mm at (' + Fmt(X) + ', ' + Fmt(Y) + ')' + SketchPlace(d, d.F[i]);
      FK_EXTRUDE:
        Result := FeatureName(d, Ref) + ', ' + Fmt(P1) + ' mm';
      FK_REVOLVE:
        Result := FeatureName(d, Ref) + ', ' + Fmt(P1) + #194#176 + ' about Y';
      FK_FOREIGN:
        Result := 'From SolidCraft. Not in SolidCraft 98.';
      FK_HOLE:
        begin
          Result := 'D ' + Fmt(P1) + ' mm on ' + FeatureName(d, Ref) + ' top face, ';
          if P2 <= 0 then Result := Result + 'through all'
          else Result := Result + Fmt(P2) + ' mm deep';
        end;
    end;
end;

{ ---- Save and Open, byte-compatible with the Windows version ---- }

{ Text into a fixed field: padded with spaces, or NULs if it was never set
  (VB leaves a fixed string nobody assigned as NULs). UTF-8 is narrowed to
  Windows-1252, the Windows version's code page. }
procedure ToFix(const s: string; var buf; n: Integer);
var
  a: RawByteString;
  p: PAnsiChar;
  i: Integer;
begin
  p := @buf;
  if s = '' then
  begin
    FillChar(p^, n, 0);
    Exit;
  end;
  a := UTF8ToCP1252(s);
  for i := 0 to n - 1 do
    if i < Length(a) then p[i] := a[i + 1] else p[i] := ' ';
end;

function FromFix(const buf; n: Integer): string;
var
  p: PAnsiChar;
  a: RawByteString;
  k: Integer;
begin
  p := @buf;
  k := n;
  while (k > 0) and ((p[k - 1] = ' ') or (p[k - 1] = #0)) do Dec(k);
  SetLength(a, k);
  if k > 0 then Move(p^, a[1], k);
  Result := CP1252ToUTF8(a);
end;

function SaveDesign(const d: TDesign; const APath: string): Boolean;
var
  fs: TFileStream;
  h: TFileHeader;
  r: TFileFeature;
  i: Integer;
begin
  Result := False;
  LastFileError := '';
  try
    if FileExists(APath) and not DeleteFile(APath) then
    begin
      LastFileError := 'Permission denied' + LineEnding + '(While replacing the old file: ' + APath + ')';
      Exit;
    end;
    fs := TFileStream.Create(APath, fmCreate);
  except
    LastFileError := 'Path/File access error' + LineEnding + '(While creating the file: ' + APath + ')';
    Exit;
  end;
  try
    Move(FILE_MAGIC[1], h.Magic, 4);
    h.Version := FILE_VERSION;
    ToFix(d.Title, h.Title, 64);
    h.Count := d.Count;
    fs.WriteBuffer(h, SizeOf(h));
    for i := 1 to MAX_FEATURES do
    begin
      FillChar(r, SizeOf(r), 0);
      r.Kind := d.F[i].Kind;
      ToFix(d.F[i].Name, r.Name, 24);
      r.X := d.F[i].X; r.Y := d.F[i].Y; r.Z := d.F[i].Z;
      r.P1 := d.F[i].P1; r.P2 := d.F[i].P2;
      r.Ref := d.F[i].Ref;
      r.Suppressed := d.F[i].Suppressed;
      r.P3 := d.F[i].P3;
      ToFix(d.F[i].Info, r.Info, 32);
      fs.WriteBuffer(r, SizeOf(r));
    end;
    Result := True;
  finally
    fs.Free;
  end;
end;

function LoadDesign(var d: TDesign; const APath: string): Integer;
var
  fs: TFileStream;
  h: TFileHeader;
  r5: TFileFeature;
  r4: TFileFeatureV4;
  r3: TFileFeatureV3;
  i: Integer;
begin
  try
    fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    LastFileError := 'File not found: ' + APath;
    Exit(4);
  end;
  try
    if fs.Read(h, SizeOf(h)) < 6 then
    begin
      LastFileError := '''' + APath + ''' is not a SolidCraft 98 part.';
      Exit(1);
    end;
    if h.Magic <> FILE_MAGIC then
    begin
      LastFileError := '''' + APath + ''' is not a SolidCraft 98 part.';
      Exit(1);
    end;
    if h.Version > FILE_VERSION then
    begin
      LastFileError := 'This file was saved by a newer version of SolidCraft.' + LineEnding + LineEnding +
        'Please upgrade to SolidCraft 98 Second Edition.';
      Exit(2);
    end;
    if h.Version < 3 then
    begin
      LastFileError := 'This file was saved by an older version of SolidCraft.' + LineEnding + LineEnding +
        'Versions before 3 are not supported. They never were.';
      Exit(3);
    end;
    NewDesign(d, FromFix(h.Title, 64));
    for i := 1 to MAX_FEATURES do
    begin
      case h.Version of
        3: begin
             FillChar(r3, SizeOf(r3), 0);
             fs.Read(r3, SizeOf(r3));
             FillChar(r5, SizeOf(r5), 0);
             r5.Kind := r3.Kind; r5.Name := r3.Name; r5.X := r3.X; r5.Y := r3.Y; r5.Z := r3.Z;
             r5.P1 := r3.P1; r5.P2 := r3.P2; r5.Ref := r3.Ref; r5.Suppressed := r3.Suppressed;
           end;
        4: begin
             FillChar(r4, SizeOf(r4), 0);
             fs.Read(r4, SizeOf(r4));
             FillChar(r5, SizeOf(r5), 0);
             r5.Kind := r4.Kind; r5.Name := r4.Name; r5.X := r4.X; r5.Y := r4.Y; r5.Z := r4.Z;
             r5.P1 := r4.P1; r5.P2 := r4.P2; r5.Ref := r4.Ref; r5.Suppressed := r4.Suppressed; r5.P3 := r4.P3;
           end;
      else
        FillChar(r5, SizeOf(r5), 0);
        fs.Read(r5, SizeOf(r5));
      end;
      d.F[i].Kind := r5.Kind;
      d.F[i].Name := FromFix(r5.Name, 24);
      d.F[i].X := r5.X; d.F[i].Y := r5.Y; d.F[i].Z := r5.Z;
      d.F[i].P1 := r5.P1; d.F[i].P2 := r5.P2;
      d.F[i].Ref := r5.Ref;
      d.F[i].Suppressed := r5.Suppressed;
      d.F[i].P3 := r5.P3;
      if h.Version >= 5 then d.F[i].Info := FromFix(r5.Info, 32);
    end;
    d.Count := h.Count;
    if (d.Count < 0) or (d.Count > MAX_FEATURES) then d.Count := 0;
    for i := d.Count + 1 to MAX_FEATURES do d.F[i].Kind := FK_NONE;
    if h.Version = 3 then
    begin
      LastFileError := 'This file was saved by an older version of SolidCraft.' + LineEnding + LineEnding +
        'It has been converted. Save it to keep the new format.' + LineEnding + '(This has never happened before.)';
      Exit(5);
    end;
    Result := 0;
  finally
    fs.Free;
  end;
end;

end.
