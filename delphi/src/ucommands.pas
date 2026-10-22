{ uCommands - everything is a command.

  The toolbar, the menus and the keyboard all call RunCommand with the same
  key, so there is exactly one copy of each command. (The 1999 way was three
  copies, one per OnClick, all subtly different.) }
unit uCommands;

{$mode objfpc}{$H+}

interface

uses fPart;

procedure RunCommand(const ACmd: string);
{ Double-click in the tree or the timeline: change a feature's numbers. }
procedure EditFeature(p: TPartWindow; i: Integer);
procedure SetTurbo(AOn: Boolean);

implementation

uses Classes, SysUtils, Forms, Controls, Graphics, IntfGraphics, FPImage,
  uModel, uKernel, uMesh, uStl, uImport, uDocs, uArt, uGif, fDialogs, fMain;

procedure Status(const s: string);
begin
  SetStatus(s);
end;

function NeedPart(out p: TPartWindow): Boolean;
begin
  p := MainForm.ActivePart;
  Result := p <> nil;
  if not Result then
    MsgBox('There is no part open.' + LineEnding + 'Choose File, New Part first.', MB_EXCLAMATION);
end;

procedure SetTurbo(AOn: Boolean);
begin
  Turbo := AOn;
  if not Turbo then Y2KHappened := False;
  MainForm.TurboChanged;
  MainForm.RefreshAllParts;
  if Turbo then Status('Turbo on: 33 MHz. Authentic 1999 behaviour enabled.')
  else Status('Turbo off: 66 MHz. Everything works again.');
end;

{ ---- File ---- }

procedure CmdNew;
var
  slot: Integer;
begin
  slot := NewDocSlot;
  if slot = 0 then
  begin
    MsgBox('Too many parts open. Sixteen ought to be enough for anybody.', MB_EXCLAMATION);
    Exit;
  end;
  MainForm.AddPart(slot);
  Status('New part created.');
end;

{ Opens a part (or a SolidCraft design, rebuilt here). True if it worked. }
function OpenPath(const APath: string): Boolean;
var
  slot, r: Integer;
  notice, err: string;
  p: TPartWindow;
begin
  Result := False;
  slot := NewDocSlot;
  if slot = 0 then
  begin
    MsgBox('Too many parts open. Close one first.', MB_EXCLAMATION);
    Exit;
  end;
  if IsSolidCraftDesign(APath) then
  begin
    // a design from SolidCraft itself: rebuilt here, saved as a new .sc98
    Screen.Cursor := crHourGlass;
    try
      if not ImportSolidCraft(APath, Docs[slot], notice, err) then
      begin
        Screen.Cursor := crDefault;
        FreeDocSlot(slot);
        MsgBox(err, MB_EXCLAMATION, 'Open');
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    DocPath[slot] := '';
  end
  else
  begin
    r := LoadDesign(Docs[slot], APath);
    if (r <> 0) and (r <> 5) then
    begin
      FreeDocSlot(slot);
      MsgBox(LastFileError, MB_EXCLAMATION);
      Exit;
    end;
    if r = 5 then MsgBox(LastFileError, MB_INFO);
    DocPath[slot] := APath;
    Docs[slot].Title := FileTitle(APath);
    notice := '';
  end;
  p := MainForm.AddPart(slot);
  p.ZoomFit;
  Status('Opened ' + APath);
  if notice <> '' then MsgBox(notice, MB_INFO, 'Open');
  Result := True;
end;

procedure CmdOpen;
var
  path: string;
begin
  path := MainForm.AskFileName(False, '',
    'All SolidCraft files (*.sc98, *.solidcraft)|*.sc98;*.solidcraft|SolidCraft 98 Parts (*.sc98)|*.sc98|SolidCraft Designs (*.solidcraft)|*.solidcraft',
    PART_EXT);
  if path <> '' then OpenPath(path);
end;

function FileLen(const APath: string): Int64;
var
  sr: TSearchRec;
begin
  Result := 0;
  if FindFirst(APath, faAnyFile, sr) = 0 then Result := sr.Size;
  FindClose(sr);
end;

function SaveTo(p: TPartWindow; const APath: string): Boolean;
var
  slot: Integer;
begin
  slot := p.Slot;
  Result := SaveDesign(Docs[slot], APath);
  if not Result then
  begin
    MsgBox(LastFileError, MB_CRITICAL);
    Exit;
  end;
  DocPath[slot] := APath;
  Docs[slot].Title := FileTitle(APath);
  DocDirty[slot] := False;
  p.RefreshNames;
  MainForm.PartsChanged;
end;

{ My Documents/<name>, with (2), (3)... if that's taken. }
function SafeDocumentsPath(const AName: string): string;
var
  dir, base: string;
  n: Integer;
begin
  dir := IncludeTrailingPathDelimiter(GetUserDir) + 'Documents' + PathDelim;
  if not DirectoryExists(dir) then dir := ExtractFilePath(ParamStr(0));
  base := FileTitle(AName);
  Result := dir + base + '.' + PART_EXT;
  n := 1;
  while FileExists(Result) do
  begin
    Inc(n);
    Result := dir + base + ' (' + IntToStr(n) + ').' + PART_EXT;
  end;
end;

{ Saving to drive A:. There isn't one, so the part goes to the hard disk
  first, and with Turbo on we put on a show of floppies for it. }
procedure FloppySave(p: TPartWindow; const AName: string);
const
  PREVIEW_BYTES = 3686454;   // a 1280 x 960 24-bit BMP, "for faster opening"
var
  slot: Integer;
  real: string;
  bytes: Double;
begin
  slot := p.Slot;
  if DirectoryExists('A:\') then
  begin
    // a real floppy drive, in this day and age: save to it
    real := 'A:\' + FileTitle(AName) + '.' + PART_EXT;
    if not SaveTo(p, real) then Exit;
    Status('Saved ' + real + ' (' + IntToStr(FileLen(real)) + ' bytes). Remember to label the disk.');
    Exit;
  end;
  if not Turbo then
  begin
    MsgBox('There is no drive A: on this PC.' + LineEnding + LineEnding +
      'Use File, Save As to save the part to the hard disk.', MB_EXCLAMATION);
    Exit;
  end;
  real := DocPath[slot];
  if real = '' then real := SafeDocumentsPath(AName);
  if not SaveTo(p, real) then Exit;
  bytes := FileLen(real) + PREVIEW_BYTES;
  if RunFloppy(FileTitle(real) + '.' + PART_EXT, bytes) then
    MsgBox('Copied ' + FormatFloat('#,##0', bytes) + ' bytes to ' + IntToStr(-Trunc(-bytes / FLOPPY_BYTES)) + ' disks.' +
      LineEnding + LineEnding + 'Turbo saves include an uncompressed preview bitmap, for speed.' + LineEnding +
      '(This PC has no drive A:, so the part itself is safe in' + LineEnding + real + ')', MB_INFO)
  else
    MsgBox('Copy cancelled. The part is safe in' + LineEnding + real, MB_INFO);
  Status('Saved ' + real);
end;

procedure CmdSave(AAs: Boolean);
var
  p: TPartWindow;
  path: string;
begin
  if not NeedPart(p) then Exit;
  path := DocPath[p.Slot];
  if AAs or (path = '') then
  begin
    path := MainForm.AskFileName(True, Docs[p.Slot].Title, '', '');
    if path = '' then Exit;
  end;
  // A:\ with no floppy drive is the pretend floppy; a real A: is just a drive
  if (UpperCase(Copy(path, 1, 3)) = 'A:\') and not DirectoryExists('A:\') then
  begin
    FloppySave(p, Copy(path, 4, MaxInt));
    Exit;
  end;
  if SaveTo(p, path) then
    Status('Saved ' + path + ' (' + IntToStr(FileLen(path)) + ' bytes)');
end;

procedure CmdFloppy;
var
  p: TPartWindow;
begin
  if not NeedPart(p) then Exit;
  FloppySave(p, Docs[p.Slot].Title + '.' + PART_EXT);
end;

{ ---- File > Publish to Web ----
  A home page for your part, in the style of the day: a marquee, a hit
  counter, an "under construction" GIF and a picture of the part. Three
  files in the folder you pick; nothing goes near a network. }

function MakeFileName(const s: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    if s[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-'] then Result := Result + s[i];
  if Result = '' then Result := 'mypart';
end;

function HtmlText(const s: string): string;
begin
  Result := StringReplace(s, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

{ The viewport as it is now, squeezed into the 16 colours. }
procedure WritePartGif(bmp: TBitmap; const APath: string);
var
  img: TLazIntfImage;
  px: TPixels;
  x, y, w, h: Integer;
  c: TFPColor;
begin
  w := bmp.Width; h := bmp.Height;
  SetLength(px, w, h);
  img := bmp.CreateIntfImage;
  try
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        c := img.Colors[x, y];
        px[x, y] := NearestQB(c.red shr 8, c.green shr 8, c.blue shr 8);
      end;
  finally
    img.Free;
  end;
  GifBegin(w, h, False);
  GifFrame(px, w, h, 0, -1);
  GifSave(APath);
end;

{ Two frames of the road sign, at 3x, blinking twice a second. }
procedure AddSignFrame(const AKey: string);
var
  px: TPixels;
  x, y: Integer;
  ch: Char;
begin
  SetLength(px, 48, 48);
  for y := 0 to 47 do
    for x := 0 to 47 do
    begin
      ch := IconRow(AKey, y div 3)[x div 3 + 1];
      if ch = '.' then px[x, y] := 13
      else if ch <= '9' then px[x, y] := Ord(ch) - Ord('0')
      else px[x, y] := Ord(ch) - Ord('A') + 10;
    end;
  GifFrame(px, 48, 48, 50, 13);          // magenta is see-through
end;

procedure WriteHtml(slot: Integer; const APath, AGif: string);
var
  sl: TStringList;
  i: Integer;
  t, hits: string;
begin
  t := HtmlText(Docs[slot].Title);
  hits := FormatFloat('000000', 427 + Random(9000));    // nobody wants to be visitor 1
  sl := TStringList.Create;
  try
    sl.Add('<HTML>');
    sl.Add('<HEAD><TITLE>' + t + ' - My SolidCraft 98 Part!!!</TITLE></HEAD>');
    sl.Add('<BODY BGCOLOR="#000080" TEXT="#FFFF00" LINK="#00FFFF" VLINK="#FF00FF">');
    sl.Add('<CENTER>');
    sl.Add('<MARQUEE BEHAVIOR="alternate"><FONT FACE="Comic Sans MS" SIZE="6"><B>Welcome to ' + t + '!!!</B></FONT></MARQUEE>');
    sl.Add('<P><IMG SRC="construction.gif" WIDTH="48" HEIGHT="48"> <FONT SIZE="5"><B>This page is under construction!</B></FONT> <IMG SRC="construction.gif" WIDTH="48" HEIGHT="48"></P>');
    sl.Add('<HR WIDTH="80%">');
    sl.Add('<P><IMG SRC="' + AGif + '" BORDER="4" ALT="' + t + ' (wireframe)"></P>');
    sl.Add('<TABLE BORDER="3" CELLPADDING="4" BGCOLOR="#C0C0C0">');
    sl.Add('<TR><TH><FONT COLOR="#000000">#</FONT></TH><TH><FONT COLOR="#000000">Feature</FONT></TH><TH><FONT COLOR="#000000">What it is</FONT></TH></TR>');
    for i := 1 to Docs[slot].Count do
      sl.Add('<TR><TD><FONT COLOR="#000000">' + IntToStr(i) + '</FONT></TD><TD><FONT COLOR="#000000">' +
        HtmlText(FeatureName(Docs[slot], i)) + '</FONT></TD><TD><FONT COLOR="#000000">' +
        HtmlText(Describe(Docs[slot], i)) + '</FONT></TD></TR>');
    sl.Add('</TABLE>');
    sl.Add('<P>You are visitor number');
    sl.Add('<TABLE BORDER="1" CELLPADDING="2" CELLSPACING="0" BGCOLOR="#000000"><TR>');
    for i := 1 to Length(hits) do
      sl.Add('<TD><FONT FACE="Courier New" COLOR="#00FF00" SIZE="5"><B>' + hits[i] + '</B></FONT></TD>');
    sl.Add('</TR></TABLE></P>');
    sl.Add('<P><A HREF="#">Sign my guestbook!</A> | <A HREF="#">View my guestbook!</A> | <A HREF="#">Next site in the CAD Web Ring &gt;&gt;</A></P>');
    sl.Add('<HR WIDTH="80%">');
    sl.Add('<FONT SIZE="2">Best viewed in IE5 at 800x600. Made with SolidCraft 98 ' + HtmlText(APP_EDITION) + ', ' + HtmlText(APP_VERSION) + '.<BR>');
    sl.Add('Last updated ' + FormatDateTime('mmmm d, yyyy', ClockNow) + '.</FONT>');
    sl.Add('</CENTER>');
    sl.Add('</BODY>');
    sl.Add('</HTML>');
    sl.WriteBOM := False;
    sl.SaveToFile(APath);
  finally
    sl.Free;
  end;
end;

procedure CmdPublish;
var
  p: TPartWindow;
  html, dir, base: string;
begin
  if not NeedPart(p) then Exit;
  html := MainForm.AskFileName(True, MakeFileName(Docs[p.Slot].Title) + '.htm', 'Web Pages (*.htm)|*.htm', 'htm');
  if html = '' then Exit;
  dir := ExtractFilePath(html);
  base := FileTitle(html);
  Screen.Cursor := crHourGlass;
  try
    Status('Rendering ' + base + '.gif...');
    Application.ProcessMessages;
    WritePartGif(p.ViewBitmap, dir + base + '.gif');
    GifBegin(48, 48, True);
    AddSignFrame('Construction');
    AddSignFrame('Construction2');
    GifSave(dir + 'construction.gif');
    try
      WriteHtml(p.Slot, html, base + '.gif');
    except
      on e: Exception do
      begin
        Screen.Cursor := crDefault;
        MsgBox('Could not write ' + html + LineEnding + LineEnding + e.Message, MB_CRITICAL);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  Status('Published ' + html);
  MsgBox('Your part is on the World Wide Web!*' + LineEnding + LineEnding + html + LineEnding + LineEnding +
    '* On your hard disk. Upload it with your FTP program.', MB_INFO, 'Publish to Web');
end;

{ ---- File > Export for Rapid Prototyping ---- }

procedure CmdExportStl;
var
  p: TPartWindow;
  t: TTriArray;
  n: Integer;
  err, path: string;
begin
  if not NeedPart(p) then Exit;
  n := MeshDesign(Docs[p.Slot], t, MESH_SEGS, err);
  if n = 0 then
  begin
    MsgBox('There is nothing solid to export.' + LineEnding + LineEnding +
      'Sketches are flat. Extrude or revolve one first.', MB_EXCLAMATION);
    Exit;
  end;
  path := MainForm.AskFileName(True, Docs[p.Slot].Title + '.stl', 'Stereolithography (*.stl)|*.stl', 'stl');
  if path = '' then Exit;
  Screen.Cursor := crHourGlass;
  Status('Writing ' + IntToStr(n) + ' triangles...');
  try
    if not WriteStl(t, n, path, Docs[p.Slot].Title) then
    begin
      Screen.Cursor := crDefault;
      MsgBox('Could not write ' + path, MB_CRITICAL);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  Status('Exported ' + path + ' (' + IntToStr(n) + ' triangles)');
  if err <> '' then
    MsgBox('Exported ' + IntToStr(n) + ' triangles, but left out: ' + err, MB_EXCLAMATION, 'Export for Rapid Prototyping')
  else
    MsgBox('Exported ' + IntToStr(n) + ' triangles to' + LineEnding + path + LineEnding + LineEnding +
      'Send it to your service bureau. Allow 3 to 5 working days.', MB_INFO, 'Export for Rapid Prototyping');
end;

procedure CmdShaded;
begin
  ViewShaded := not ViewShaded;
  MainForm.ShadedChanged;
  if not ViewShaded then Status('Wireframe.');
  MainForm.RefreshAllParts;
end;

procedure CmdClose;
var
  p: TPartWindow;
begin
  if NeedPart(p) then MainForm.ClosePart(p);
end;

{ ---- Features ---- }

function PlacePrompts: string;
begin
  Result := 'On feature # (0 = ground)|Height above that (mm)';
end;

{ The "on top of" number must be 0 or an extrude that comes before this sketch. }
function PlaceOk(const d: TDesign; i: Integer; v: Double): Boolean;
var
  n, last: Integer;
begin
  if v = 0 then Exit(True);
  if i = 0 then last := d.Count else last := i - 1;
  n := Trunc(v);
  if (n = v) and (n >= 1) and (n <= last) and (d.F[n].Kind = FK_EXTRUDE) then Exit(True);
  MsgBox('A sketch can sit on the ground (0) or on top of an extrude that comes before it.' + LineEnding +
    'Use the number from the # column of the timeline.', MB_EXCLAMATION);
  Result := False;
end;

function Min2(a, b: Double): Double;
begin
  if a < b then Result := a else Result := b;
end;

procedure SketchCentre(const s: TFeature; out x, y: Double);
begin
  if s.Kind = FK_SKETCH_CIRCLE then
  begin
    x := s.X; y := s.Y;
  end
  else
  begin
    x := s.X + s.P1 / 2; y := s.Y + s.P2 / 2;
  end;
end;

function OneSideOfY(const s: TFeature): Boolean;
begin
  if s.Kind = FK_SKETCH_CIRCLE then
    Result := (s.X - s.P1 >= 0) or (s.X + s.P1 <= 0)
  else
    Result := (s.X >= 0) or (s.X + s.P1 <= 0);
end;

{ The one dialog per kind of feature, for New and for Edit. i is the feature
  being edited (0 for a new one). Fills f and returns True on OK, if the
  numbers make sense. }
function AskFeature(const d: TDesign; i: Integer; var f: TFeature): Boolean;
var
  title: string;
  s, b: TFeature;
  k: Integer;
  v: array[0..MAX_FIELDS - 1] of Double absolute ParamValue;
begin
  Result := False;
  if i = 0 then title := '' else title := 'Edit ' + FeatureName(d, i) + ': ';
  case f.Kind of
    FK_SKETCH_RECT:
      begin
        if not AskParams(title + 'Sketch Rectangle',
          'Width (mm)|Height (mm)|Corner X (mm)|Corner Y (mm)|Corner radius (mm)|' + PlacePrompts,
          Fmt0(f.P1) + '|' + Fmt0(f.P2) + '|' + Fmt0(f.X) + '|' + Fmt0(f.Y) + '|' + Fmt0(f.P3) + '|' +
          Fmt0(f.Ref) + '|' + Fmt0(f.Z)) then Exit;
        if not PlaceOk(d, i, v[5]) then Exit;
        if (v[0] <= 0) or (v[1] <= 0) then
        begin
          MsgBox('Width and height must be more than zero.', MB_EXCLAMATION);
          Exit;
        end;
        if (v[4] < 0) or (v[4] * 2 > Min2(v[0], v[1])) then
        begin
          MsgBox('The corner radius must be between 0 and half the shorter side.', MB_EXCLAMATION);
          Exit;
        end;
        f.P1 := v[0]; f.P2 := v[1];
        f.X := v[2]; f.Y := v[3];
        f.P3 := v[4];
        f.Ref := Trunc(v[5]); f.Z := v[6];
      end;

    FK_SKETCH_CIRCLE:
      begin
        if not AskParams(title + 'Sketch Circle', 'Radius (mm)|Centre X (mm)|Centre Y (mm)|' + PlacePrompts,
          Fmt0(f.P1) + '|' + Fmt0(f.X) + '|' + Fmt0(f.Y) + '|' + Fmt0(f.Ref) + '|' + Fmt0(f.Z)) then Exit;
        if not PlaceOk(d, i, v[3]) then Exit;
        if v[0] <= 0 then
        begin
          MsgBox('The radius must be more than zero.', MB_EXCLAMATION);
          Exit;
        end;
        f.P1 := v[0];
        f.X := v[1]; f.Y := v[2];
        f.Ref := Trunc(v[3]); f.Z := v[4];
      end;

    FK_EXTRUDE:
      begin
        if not AskParams(title + 'Extrude ' + FeatureName(d, f.Ref), 'Depth (mm)', Fmt0(f.P1)) then Exit;
        if v[0] <= 0 then
        begin
          MsgBox('The depth must be more than zero.', MB_EXCLAMATION);
          Exit;
        end;
        f.P1 := v[0];
      end;

    FK_REVOLVE:
      begin
        if not AskParams(title + 'Revolve ' + FeatureName(d, f.Ref) + ' about Y', 'Angle (degrees)', Fmt0(f.P1)) then Exit;
        if (v[0] = 0) or (Abs(v[0]) > 360) then
        begin
          MsgBox('The angle must be between 1 and 360 degrees.', MB_EXCLAMATION);
          Exit;
        end;
        s := d.F[f.Ref];
        if not OneSideOfY(s) then
        begin
          MsgBox('The sketch crosses the Y axis, so revolving it would turn the part inside out.' + LineEnding +
            'Move the sketch so it''s all on one side of X = 0.', MB_EXCLAMATION);
          Exit;
        end;
        f.P1 := v[0];
      end;

    FK_FOREIGN:
      begin
        MsgBox(f.Name + ' is a ' + LowerCase(f.Info) + ' from SolidCraft.' + LineEnding + LineEnding +
          'Requires SolidCraft 2000.', MB_INFO);
        Exit;
      end;

    FK_HOLE:
      begin
        b := d.F[f.Ref];
        s := d.F[b.Ref];
        if not AskParams(title + 'Hole on top face of ' + FeatureName(d, f.Ref),
          'Diameter (mm)|Depth (mm, 0 = through all)|Centre X (mm)|Centre Y (mm)',
          Fmt0(f.P1) + '|' + Fmt0(f.P2) + '|' + Fmt0(f.X) + '|' + Fmt0(f.Y)) then Exit;
        if (v[0] <= 0) or (v[1] < 0) then
        begin
          MsgBox('The diameter must be more than zero, and the depth zero or more.', MB_EXCLAMATION);
          Exit;
        end;
        if not ProfileContains(s, v[2], v[3], v[0] / 2) then
        begin
          MsgBox('That hole doesn''t fit on the face. It would fall off the edge.', MB_EXCLAMATION);
          Exit;
        end;
        if v[1] > b.P1 + 0.000001 then
        begin
          MsgBox('That''s deeper than ' + FeatureName(d, f.Ref) + ' is tall.' + LineEnding +
            'Use depth 0 for a hole all the way through.', MB_EXCLAMATION);
          Exit;
        end;
        for k := 1 to d.Count do
          if (k <> i) and (d.F[k].Kind = FK_HOLE) and (d.F[k].Ref = f.Ref) then
            if Sqrt(Sqr(d.F[k].X - v[2]) + Sqr(d.F[k].Y - v[3])) < (d.F[k].P1 + v[0]) / 2 + 0.01 then
            begin
              MsgBox('That hole would run into ' + FeatureName(d, k) + '.', MB_EXCLAMATION);
              Exit;
            end;
        f.P1 := v[0]; f.P2 := v[1];
        f.X := v[2]; f.Y := v[3];
      end;
  end;
  Result := True;
end;

function Commit(p: TPartWindow; const f: TFeature): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := AddFeature(Docs[p.Slot], f);
  if i = 0 then
  begin
    MsgBox('Subscript out of range.' + LineEnding + LineEnding + 'A part can have ' + IntToStr(MAX_FEATURES) +
      ' features. Nobody will ever need more.', MB_CRITICAL);
    Exit;
  end;
  DocDirty[p.Slot] := True;
  p.RefreshAll(True);
  MainForm.PartsChanged;
  Status(FeatureName(Docs[p.Slot], i) + ' created: ' + Describe(Docs[p.Slot], i));
  Result := True;
  if f.Kind = FK_SKETCH_RECT then MainForm.CalPop('It looks like you''re drawing a box.');
end;

function BlankFeature(AKind: Integer): TFeature;
begin
  Result := Default(TFeature);
  Result.Kind := AKind;
end;

{ The extrude picked in the tree or timeline (a hole counts as its extrude), or 0. }
function SelectedExtrude(p: TPartWindow): Integer;
var
  b: Integer;
begin
  Result := 0;
  b := p.Selected;
  if (b < 1) or (b > Docs[p.Slot].Count) then Exit;
  if Docs[p.Slot].F[b].Kind = FK_HOLE then b := Docs[p.Slot].F[b].Ref;
  if Docs[p.Slot].F[b].Kind = FK_EXTRUDE then Result := b;
end;

procedure CmdSketchRect;
var
  p: TPartWindow;
  f: TFeature;
begin
  if not NeedPart(p) then Exit;
  f := BlankFeature(FK_SKETCH_RECT);
  f.P1 := 40; f.P2 := 30;
  f.Ref := SelectedExtrude(p);
  if AskFeature(Docs[p.Slot], 0, f) then Commit(p, f);
end;

procedure CmdSketchCircle;
var
  p: TPartWindow;
  f: TFeature;
begin
  if not NeedPart(p) then Exit;
  f := BlankFeature(FK_SKETCH_CIRCLE);
  f.P1 := 15;
  f.Ref := SelectedExtrude(p);
  if AskFeature(Docs[p.Slot], 0, f) then Commit(p, f);
end;

procedure CmdExtrude;
var
  p: TPartWindow;
  f: TFeature;
begin
  if not NeedPart(p) then Exit;
  f := BlankFeature(FK_EXTRUDE);
  f.Ref := LastFreeSketch(Docs[p.Slot]);
  if f.Ref = 0 then
  begin
    MsgBox('Extrude needs a sketch to extrude.' + LineEnding + 'Sketch a rectangle or a circle first.', MB_EXCLAMATION);
    Exit;
  end;
  f.P1 := 20;
  if AskFeature(Docs[p.Slot], 0, f) then Commit(p, f);
end;

procedure CmdRevolve;
var
  p: TPartWindow;
  f: TFeature;
begin
  if not NeedPart(p) then Exit;
  f := BlankFeature(FK_REVOLVE);
  f.Ref := LastFreeSketch(Docs[p.Slot]);
  if f.Ref = 0 then
  begin
    MsgBox('Revolve needs a sketch to revolve.' + LineEnding + 'Sketch a rectangle or a circle first.', MB_EXCLAMATION);
    Exit;
  end;
  f.P1 := 360;
  if AskFeature(Docs[p.Slot], 0, f) then Commit(p, f);
end;

{ A hole goes on the top face of the selected extrude, or the last one. }
procedure CmdHole;
var
  p: TPartWindow;
  f: TFeature;
  b: Integer;
begin
  if not NeedPart(p) then Exit;
  b := SelectedExtrude(p);
  if b = 0 then b := LastSolid(Docs[p.Slot]);
  if b = 0 then
  begin
    MsgBox('A hole goes on the top face of an extrude.' + LineEnding + 'Sketch something and extrude it first.', MB_EXCLAMATION);
    Exit;
  end;
  f := BlankFeature(FK_HOLE);
  f.Ref := b;
  f.P1 := 8;
  SketchCentre(Docs[p.Slot].F[Docs[p.Slot].F[b].Ref], f.X, f.Y);
  if AskFeature(Docs[p.Slot], 0, f) then Commit(p, f);
end;

procedure EditFeature(p: TPartWindow; i: Integer);
var
  slot, j: Integer;
  f: TFeature;
  bad: string;
begin
  slot := p.Slot;
  if (i < 1) or (i > Docs[slot].Count) then Exit;
  f := Docs[slot].F[i];
  if not AskFeature(Docs[slot], i, f) then Exit;
  Docs[slot].F[i] := f;
  DocDirty[slot] := True;
  p.RefreshAll(False);
  MainForm.PartsChanged;
  Status(FeatureName(Docs[slot], i) + ' changed: ' + Describe(Docs[slot], i));
  // anything built on it may not fit any more; say so instead of hiding it
  bad := '';
  for j := i + 1 to Docs[slot].Count do
    if not RefOk(Docs[slot], j) then bad := bad + LineEnding + '    ' + FeatureName(Docs[slot], j);
  if bad <> '' then
    MsgBox('These features no longer fit and have been left out of the part:' + LineEnding + bad + LineEnding + LineEnding +
      'Edit them, or edit ' + FeatureName(Docs[slot], i) + ' back.', MB_EXCLAMATION);
end;

procedure CmdEdit;
var
  p: TPartWindow;
begin
  if not NeedPart(p) then Exit;
  if p.Selected = 0 then
  begin
    MsgBox('Select a feature in the tree or the timeline first.', MB_INFO);
    Exit;
  end;
  EditFeature(p, p.Selected);
end;

{ Delete the selected feature, and whatever is built on it. }
procedure CmdDelete;
var
  p: TPartWindow;
  slot, i, j, n: Integer;
  gone: TBoolArray;
  list: string;
begin
  if not NeedPart(p) then Exit;
  slot := p.Slot;
  i := p.Selected;
  if i = 0 then
  begin
    MsgBox('Select a feature in the tree or the timeline first.', MB_INFO);
    Exit;
  end;
  n := MarkDependents(Docs[slot], i, gone);
  list := '';
  for j := 1 to Docs[slot].Count do
    if gone[j] and (j <> i) then list := list + LineEnding + '    ' + FeatureName(Docs[slot], j);
  if n > 1 then
    if MsgBox('These are built on ' + FeatureName(Docs[slot], i) + ' and will be deleted too:' + LineEnding + list +
      LineEnding + LineEnding + 'Delete all ' + IntToStr(n) + ' features?',
      MB_EXCLAMATION or MB_YESNO or MB_DEFBUTTON2) = IDNO then Exit;
  list := FeatureName(Docs[slot], i);
  DeleteMarked(Docs[slot], gone);
  DocDirty[slot] := True;
  p.Selected := 0;
  p.RefreshAll(False);
  MainForm.PartsChanged;
  if n > 1 then Status('Deleted ' + list + ' and ' + IntToStr(n - 1) + ' more.')
  else Status('Deleted ' + list + '.');
end;

procedure CmdUndo;
var
  p: TPartWindow;
  slot, i: Integer;
begin
  if not NeedPart(p) then Exit;
  slot := p.Slot;
  i := Docs[slot].Count;
  if i = 0 then
  begin
    Status('Nothing to undo.');
    Exit;
  end;
  // Features only ever build on earlier ones, so the last one is always safe to drop.
  Status('Removed ' + FeatureName(Docs[slot], i) + '.');
  Docs[slot].F[i].Kind := FK_NONE;
  Docs[slot].Count := i - 1;
  DocDirty[slot] := True;
  p.RefreshAll(False);
  MainForm.PartsChanged;
end;

procedure CmdHelp;
begin
  MsgBox('Cannot find the file ''SOLIDCRAFT.HLP'' (or one of its components).' + LineEnding + LineEnding +
    'Make sure the path and filename are correct and that all required libraries are available.',
    MB_EXCLAMATION, 'WinHelp');
end;

procedure RunCommand(const ACmd: string);
var
  p: TPartWindow;
begin
  case ACmd of
    'New': CmdNew;
    'Open': CmdOpen;
    'Save': CmdSave(False);
    'SaveAs': CmdSave(True);
    'Close': CmdClose;
    'SaveFloppy': CmdFloppy;
    'Publish': CmdPublish;
    'ExportStl': CmdExportStl;
    'Exit': MainForm.Close;

    'SketchRect': CmdSketchRect;
    'SketchCircle': CmdSketchCircle;
    'Extrude': CmdExtrude;
    'Revolve': CmdRevolve;
    'Hole': CmdHole;
    'Undo': CmdUndo;
    'Edit': CmdEdit;
    'Delete': CmdDelete;

    'Orbit', 'ViewIso': if NeedPart(p) then p.ViewIso;
    'ZoomFit': if NeedPart(p) then p.ZoomFit;
    'Regen': if NeedPart(p) then p.Regen;

    'Shaded': CmdShaded;
    'Turbo': SetTurbo(not Turbo);

    'Cascade': MainForm.Arrange(0);
    'TileH': MainForm.Arrange(1);
    'TileV': MainForm.Arrange(2);

    'Help': CmdHelp;
    'About': ShowAbout;
  else
    if Copy(ACmd, 1, 5) = 'Open:' then OpenPath(Copy(ACmd, 6, MaxInt))
    else
      MsgBox('Command ''' + ACmd + ''' is not implemented yet.' + LineEnding +
        'It is scheduled for SolidCraft 2000.', MB_INFO);
  end;
end;

procedure HelpFromDialog;
begin
  CmdHelp;
end;

initialization
  HelpProc := @HelpFromDialog;
end.
