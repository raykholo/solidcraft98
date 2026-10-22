{ fDialogs - the number dialog every command uses, About (with the WIN98
  credits, DLL Hell and the DELPHI component palette), the splash, the
  floppy copy and the blue screen. Forms built in code, at runtime. }
unit fDialogs;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics;

const
  MAX_FIELDS = 7;

var
  ParamValue: array[0..MAX_FIELDS - 1] of Double;
  HelpProc: procedure = nil;           // RunCommand('Help'), from the main window

{ Shows the number dialog. Prompts and defaults are '|'-separated. True if
  OK; the numbers are in ParamValue. }
function AskParams(const ATitle, APrompts, ADefaults: string): Boolean;
procedure ShowAbout;
procedure ShowFatal;
{ Shows the copy of AName, ABytes long. True if it got to the last disk. }
function RunFloppy(const AName: string; ABytes: Double): Boolean;
function ShowSplash: TForm;
procedure SplashProgress(f: TForm; const s: string);

implementation

uses LCLType, uDocs, uExpr, uArt, uModel;

{ ---- the number dialog ---- }

type
  TParamsForm = class(TForm)
  public
    Count: Integer;
    Labels: array[0..MAX_FIELDS - 1] of TLabel;
    Edits: array[0..MAX_FIELDS - 1] of TEdit;
    Mismatches: Integer;              // Turbo: how many type mismatches in a row
    procedure OkClick(Sender: TObject);
    procedure HelpClick(Sender: TObject);
    procedure EditEnter(Sender: TObject);
    procedure SelectBox(i: Integer);
  end;

procedure TParamsForm.SelectBox(i: Integer);
begin
  Edits[i].SetFocus;
  Edits[i].SelectAll;
end;

procedure TParamsForm.EditEnter(Sender: TObject);
begin
  // tabbing into a box selects what's in it, so typing replaces it
  TEdit(Sender).SelectAll;
end;

procedure TParamsForm.HelpClick(Sender: TObject);
begin
  if Assigned(HelpProc) then HelpProc();
end;

procedure TParamsForm.OkClick(Sender: TObject);
var
  i: Integer;
  t: string;
  v: Double;
begin
  i := 0;
  while i < Count do
  begin
    ParamValue[i] := Evaluate(Edits[i].Text);
    if ExprError <> 0 then Break;
    Inc(i);
  end;
  if ExprError = 0 then
  begin
    Mismatches := 0;
    ModalResult := mrOk;
    Exit;
  end;
  t := Edits[i].Text;
  if ExprError = 11 then
  begin
    if Turbo then ShowFatal
    else MsgBox('Run-time error ''11'':' + LineEnding + LineEnding + 'Division by zero', MB_CRITICAL);
  end
  else if not Turbo then
    MsgBox('Run-time error ''13'':' + LineEnding + LineEnding + 'Type mismatch', MB_CRITICAL)
  else
  begin
    // with Turbo on it gets more personal each time, and on the fifth try
    // it gives up and does what you meant
    Inc(Mismatches);
    v := ValLike(t);
    case Mismatches of
      1: MsgBox('Run-time error ''13'':' + LineEnding + LineEnding + 'Type mismatch', MB_CRITICAL);
      2: MsgBox('Run-time error ''13'':' + LineEnding + LineEnding + 'Still a type mismatch', MB_CRITICAL);
      3: MsgBox('Run-time error ''13'':' + LineEnding + LineEnding + 'It''s a TextBox, not a mind reader.', MB_CRITICAL);
      4: MsgBox('Did you know?' + LineEnding + LineEnding +
           'Val("' + t + '") returns ' + FmtN(v, 6) + '. Val reads digits until it meets' + LineEnding +
           'something it doesn''t understand, then stops and pretends' + LineEnding +
           'that''s all you typed.' + LineEnding + LineEnding +
           'CDbl("' + t + '") is stricter. It raises error 13. We use CDbl.' + LineEnding +
           'Usually.', MB_INFO, 'Tip of the Day');
    else
      MsgBox('Fine. ' + FmtN(v, 6) + ' it is.', MB_INFO);
      i := 0;
      while (i < Count) and (Edits[i].Text <> t) do Inc(i);
      if i < Count then Edits[i].Text := FmtN(v, 6);
      Mismatches := 0;
      OkClick(Sender);
      Exit;
    end;
    i := 0;
    while (i < Count) and (Edits[i].Text <> t) do Inc(i);
    if i >= Count then i := 0;
  end;
  if i < Count then SelectBox(i);
end;

function AskParams(const ATitle, APrompts, ADefaults: string): Boolean;
var
  f: TParamsForm;
  prompts, defaults: TStringList;
  i, y: Integer;
  b: TButton;
begin
  prompts := TStringList.Create;
  defaults := TStringList.Create;
  f := TParamsForm.CreateNew(Application);
  try
    prompts.StrictDelimiter := True; prompts.Delimiter := '|'; prompts.DelimitedText := APrompts;
    defaults.StrictDelimiter := True; defaults.Delimiter := '|'; defaults.DelimitedText := ADefaults;
    f.Caption := ATitle;
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.Count := prompts.Count;
    if f.Count > MAX_FIELDS then f.Count := MAX_FIELDS;
    y := 14;
    for i := 0 to f.Count - 1 do
    begin
      f.Labels[i] := TLabel.Create(f);
      f.Labels[i].Parent := f;
      f.Labels[i].SetBounds(14, y + 4, 190, 20);
      f.Labels[i].Caption := prompts[i];
      f.Edits[i] := TEdit.Create(f);
      f.Edits[i].Parent := f;
      f.Edits[i].SetBounds(212, y, 110, 24);
      if i < defaults.Count then f.Edits[i].Text := defaults[i] else f.Edits[i].Text := '0';
      f.Edits[i].OnEnter := @f.EditEnter;
      f.Edits[i].TabOrder := i;
      Inc(y, 32);
    end;
    Inc(y, 6);
    b := TButton.Create(f); b.Parent := f; b.Caption := 'OK'; b.Default := True;
    b.SetBounds(86, y, 76, 26); b.OnClick := @f.OkClick; b.TabOrder := f.Count;
    b := TButton.Create(f); b.Parent := f; b.Caption := 'Cancel'; b.Cancel := True; b.ModalResult := mrCancel;
    b.SetBounds(166, y, 76, 26); b.TabOrder := f.Count + 1;
    b := TButton.Create(f); b.Parent := f; b.Caption := '&Help';
    b.SetBounds(246, y, 76, 26); b.OnClick := @f.HelpClick; b.TabOrder := f.Count + 2;
    f.ClientWidth := 336;
    f.ClientHeight := y + 40;
    f.ActiveControl := f.Edits[0];
    f.Edits[0].SelectAll;
    Result := f.ShowModal = mrOk;
  finally
    f.Free;
    prompts.Free;
    defaults.Free;
  end;
end;

{ ---- the blue screen: Turbo on, divide by zero ---- }

type
  TFatalForm = class(TForm)
  public
    procedure DoPaint(Sender: TObject);
    procedure DoKey(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

procedure TFatalForm.DoPaint(Sender: TObject);
const
  Lines: array[0..8] of string = (
    'A fatal exception 0E has occurred at 0028:SOLIDCRAFT+00000D1V0.',
    'Something somewhere was divided by zero, which even a Pascal program',
    'knows better than to do.', '',
    'The current part will not be terminated. It is fine. It was',
    'never in any danger.', '',
    '*  Press any key to return to SolidCraft 98.',
    '*  Then type a number that isn''t zero.');
var
  c: TCanvas;
  i, y, x, tw: Integer;
begin
  c := Canvas;
  c.Brush.Color := $AA0000;
  c.FillRect(0, 0, ClientWidth, ClientHeight);
  c.Font.Name := 'Courier New';
  c.Font.Size := 13;
  c.Font.Style := [fsBold];
  y := ClientHeight div 2 - 160;
  x := (ClientWidth - c.TextWidth(Lines[1])) div 2;
  tw := c.TextWidth(' SolidCraft ');
  c.Brush.Color := $AAAAAA;
  c.FillRect((ClientWidth - tw) div 2 - 4, y, (ClientWidth + tw) div 2 + 4, y + c.TextHeight('X') + 4);
  c.Font.Color := $AA0000;
  c.TextOut((ClientWidth - tw) div 2, y + 2, ' SolidCraft ');
  c.Brush.Style := bsClear;
  c.Font.Color := clWhite;
  for i := 0 to 8 do
    c.TextOut(x, y + 50 + i * 26, Lines[i]);
  c.TextOut((ClientWidth - c.TextWidth('Press any key to continue _')) div 2, y + 50 + 10 * 26, 'Press any key to continue _');
  c.Brush.Style := bsSolid;
end;

procedure TFatalForm.DoKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ModalResult := mrOk;
end;

procedure ShowFatal;
var
  f: TFatalForm;
begin
  f := TFatalForm.CreateNew(Application);
  try
    f.BorderStyle := bsNone;
    f.SetBounds(0, 0, Screen.Width, Screen.Height);
    f.WindowState := wsFullScreen;
    f.Color := $AA0000;
    f.KeyPreview := True;
    f.OnPaint := @f.DoPaint;
    f.OnKeyDown := @f.DoKey;
    f.ShowModal;
  finally
    f.Free;
  end;
end;

{ ---- the floppy: "copying" a part to a stack of 1.44 MB disks ---- }

type
  TFloppyForm = class(TForm)
  public
    Nm: string;
    Total, Done: Double;
    Disks, Disk: Integer;
    Finished: Boolean;
    Box, Bar: TPaintBox;
    Info: TLabel;
    Timer: TTimer;
    procedure DoTick(Sender: TObject);
    procedure PaintDisk(Sender: TObject);
    procedure PaintBar(Sender: TObject);
    procedure ShowWhat;
  end;

procedure TFloppyForm.PaintDisk(Sender: TObject);
var
  c: TCanvas;
begin
  // a 3 1/2" disk: blue body, metal shutter, white label
  c := Box.Canvas;
  c.Brush.Color := clBtnFace; c.FillRect(0, 0, 48, 48);
  c.Brush.Color := $802000; c.FillRect(4, 2, 45, 46);
  c.Brush.Color := $C0C0C0; c.FillRect(14, 2, 37, 17);
  c.Brush.Color := $404040; c.FillRect(28, 4, 33, 15);
  c.Brush.Color := clWhite; c.FillRect(9, 24, 41, 46);
  c.Pen.Color := $C0C0C0;
  c.Line(12, 29, 37, 29); c.Line(12, 34, 37, 34); c.Line(12, 39, 31, 39);
end;

procedure TFloppyForm.PaintBar(Sender: TObject);
var
  c: TCanvas;
  f: Double;
  x, w: Integer;
begin
  // chunky blocks, like the progress bars of the time
  c := Bar.Canvas;
  c.Brush.Color := clWhite;
  c.FillRect(0, 0, Bar.Width, Bar.Height);
  f := (Done - (Disk - 1) * FLOPPY_BYTES) / FLOPPY_BYTES;
  if f > 1 then f := 1;
  w := Round((Bar.Width - 4) * f);
  c.Brush.Color := $800000;
  x := 2;
  while x <= w do
  begin
    c.FillRect(x, 3, x + 7, Bar.Height - 3);
    Inc(x, 9);
  end;
end;

procedure TFloppyForm.ShowWhat;
begin
  Info.Caption := 'Copying ' + Nm + ' to A:\' + LineEnding + LineEnding +
    'Disk ' + IntToStr(Disk) + ' of ' + IntToStr(Disks) + '   (' + FormatFloat('#,##0', Done / 1024) + ' KB of ' +
    FormatFloat('#,##0', Total / 1024) + ' KB)';
  Bar.Invalidate;
end;

procedure TFloppyForm.DoTick(Sender: TObject);
var
  diskEnd: Double;
begin
  Done := Done + 23000 + Random * 9000;       // about 500 KB a second, which was fast
  diskEnd := Disk * FLOPPY_BYTES;
  if Done >= Total then
  begin
    Done := Total;
    Timer.Enabled := False;
    Finished := True;
    ModalResult := mrOk;
    Exit;
  end;
  if Done >= diskEnd then
  begin
    Done := diskEnd;
    ShowWhat;
    Timer.Enabled := False;
    if MsgBox('Please insert disk ' + IntToStr(Disk + 1) + ' of ' + IntToStr(Disks) + ' into drive A:' + LineEnding + LineEnding +
      'Label it "' + Nm + ' - Disk ' + IntToStr(Disk + 1) + '" so you can find it later.',
      MB_OKCANCEL or MB_INFO, 'Insert Disk') <> IDOK then
    begin
      ModalResult := mrCancel;
      Exit;
    end;
    Inc(Disk);
    Timer.Enabled := True;
  end;
  ShowWhat;
end;

function RunFloppy(const AName: string; ABytes: Double): Boolean;
var
  f: TFloppyForm;
  b: TButton;
begin
  f := TFloppyForm.CreateNew(Application);
  try
    f.Caption := 'Copying...';
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.ClientWidth := 400; f.ClientHeight := 150;
    f.Nm := AName; f.Total := ABytes; f.Done := 0;
    f.Disks := -Trunc(-ABytes / FLOPPY_BYTES);
    if f.Disks * FLOPPY_BYTES < ABytes then Inc(f.Disks);
    f.Disk := 1;
    f.Box := TPaintBox.Create(f); f.Box.Parent := f; f.Box.SetBounds(16, 14, 48, 48); f.Box.OnPaint := @f.PaintDisk;
    f.Info := TLabel.Create(f); f.Info.Parent := f; f.Info.SetBounds(80, 16, 310, 50);
    f.Bar := TPaintBox.Create(f); f.Bar.Parent := f; f.Bar.SetBounds(16, 76, 368, 20); f.Bar.OnPaint := @f.PaintBar;
    b := TButton.Create(f); b.Parent := f; b.Caption := 'Cancel'; b.Cancel := True; b.ModalResult := mrCancel;
    b.SetBounds(308, 110, 76, 26);
    f.Timer := TTimer.Create(f); f.Timer.Interval := 50; f.Timer.OnTimer := @f.DoTick;
    f.ShowWhat;
    f.ShowModal;
    Result := f.Finished;
  finally
    f.Free;
  end;
end;

{ ---- DLL Hell: Turbo on, Help > About, Shift-click the logo ---- }

type
  TSetupForm = class(TForm)
  public
    Pct: Double;
    Timer: TTimer;
    procedure DoPaint(Sender: TObject);
    procedure DoTick(Sender: TObject);
  end;

procedure TSetupForm.DoPaint(Sender: TObject);
var
  c: TCanvas;
  w, x: Integer;
  s: string;
begin
  c := Canvas;
  GradientV(c, 0, 0, ClientWidth, ClientHeight, $A00000, $200000);
  c.Brush.Style := bsClear;
  c.Font.Style := [fsBold]; c.Font.Size := 11; c.Font.Color := clWhite;
  c.TextOut(16, 12, 'SolidCraft 98 Setup');
  c.Font.Style := []; c.Font.Size := 9;
  if Pct > 100 then s := 'Copying more than all of it...'
  else if Pct > 30 then s := 'A newer version exists. Copying the older one over it anyway...'
  else s := 'Checking for a newer version of MSCOMCTL.OCX...';
  c.Font.Color := $C0FFFF; c.TextOut(16, 44, s);
  c.Font.Color := clWhite;
  c.TextOut(16, 66, 'Source:       C:\WINDOWS\SYSTEM\MSCOMCTL.OCX');
  c.TextOut(16, 82, 'Destination:  C:\WINDOWS\SYSTEM\MSCOMCTL.OCX');
  c.Brush.Style := bsSolid;
  c.Brush.Color := $C0C0C0; c.FillRect(16, 112, 385, 133);
  if Pct > 100 then w := 364 else w := Round(364 * Pct / 100);
  if Pct > 100 then c.Brush.Color := clRed else c.Brush.Color := $800000;
  x := 19;
  while x <= 16 + w do
  begin
    c.FillRect(x, 115, x + 8, 130);
    Inc(x, 10);
  end;
  c.Brush.Style := bsClear;
  c.Font.Color := clWhite; c.TextOut(190, 140, IntToStr(Trunc(Pct)) + '%');
  c.Font.Color := $C0C0C0; c.TextOut(16, 172, 'Please do not turn off your computer.');
  c.Brush.Style := bsSolid;
end;

procedure TSetupForm.DoTick(Sender: TObject);
begin
  Pct := Pct + 1 + Random * 2;
  Invalidate;
  if Pct >= 112 then
  begin
    Pct := 112;
    Timer.Enabled := False;
    Repaint;
    MsgBox('Setup has updated your system files.' + LineEnding + LineEnding +
      'Please restart Windows to complete setup.' + LineEnding +
      '(Excel may not start afterwards. That''s normal.)', MB_EXCLAMATION, 'SolidCraft 98 Setup');
    MsgBox('Just kidding. Nothing was copied and nothing needs restarting.' + LineEnding +
      'Your Excel is fine.', MB_INFO, 'SolidCraft 98 Setup');
    ModalResult := mrOk;
  end;
end;

procedure ShowSetup;
var
  f: TSetupForm;
begin
  f := TSetupForm.CreateNew(Application);
  try
    f.Caption := 'SolidCraft 98 Setup';
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.ClientWidth := 400; f.ClientHeight := 200;
    f.DoubleBuffered := True;
    f.OnPaint := @f.DoPaint;
    f.Timer := TTimer.Create(f); f.Timer.Interval := 80; f.Timer.OnTimer := @f.DoTick;
    f.ShowModal;
  finally
    f.Free;
  end;
end;

{ ---- the WIN98 credits: starfield, copper bars, a sine scroller ---- }

const
  STARS = 90;

type
  TCreditsForm = class(TForm)
  public
    Box: TPaintBox;
    Timer: TTimer;
    SX, SY, SZ: array[1..STARS] of Double;
    T: Integer;
    Scroll: Double;
    procedure DoPaint(Sender: TObject);
    procedure DoTick(Sender: TObject);
    procedure DoKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DoClick(Sender: TObject);
  end;

const
  CreditLines: array[0..32] of string = (
    'SOLIDCRAFT 98', 'THE DELPHI EDITION', '',
    'A FORTY-THOUSAND-LINE PRODUCTION', '', '',
    'GEOMETRY KERNEL', 'UKERNEL.PAS (ALL OF IT)', '',
    'CONSTRAINT SOLVER', 'THE VARIANT SQUAD', '',
    'CHIEF REGENERATE CLICKER', 'PRESS F5 THREE TIMES', '',
    'ICONS', '16 COLOURS, NO UNDO', '',
    'FILE FORMAT', 'A PACKED RECORD, BYTE FOR BYTE', '',
    'QUALITY ASSURANCE', 'THE MACHINE SHOP', '',
    'SPECIAL THANKS', 'THE ONE PC NOBODY IS ALLOWED TO UPDATE', '',
    'NO PARTS WERE HARMED IN THE MAKING OF THIS SOFTWARE', '', '', '', '', 'PRESS ANY KEY');
  Msg = '   GREETINGS TO EVERYONE STILL RUNNING WINDOWS 98 SE ...  TURBO OFF IS FASTER THAN TURBO ON ...  BEGIN END. ...  BEST VIEWED AT 800 X 600 ...  ';

procedure TCreditsForm.DoPaint(Sender: TObject);
var
  c: TCanvas;
  w, h, i, k, yy, x, y, v: Integer;
  cx, cy: Double;
  col: TColor;
  ch: string;
begin
  c := Box.Canvas;
  w := Box.Width; h := Box.Height;
  cx := w / 2; cy := h / 2;
  c.Brush.Color := clBlack;
  c.FillRect(0, 0, w, h);
  // copper bars
  for k := 0 to 2 do
  begin
    yy := Round(cy + Sin((T + k * 25) / 15) * (h / 4));
    for i := 0 to 7 do
    begin
      case k of
        0: col := RGBToColor(40 + i * 25, 0, 120 - i * 10);
        1: col := RGBToColor(0, 40 + i * 25, 100);
      else
        col := RGBToColor(40 + i * 25, 40 + i * 25, 0);
      end;
      c.Pen.Color := col;
      c.Line(0, yy - 8 + i, w, yy - 8 + i);
      c.Line(0, yy + 8 - i, w, yy + 8 - i);
    end;
  end;
  // the starfield
  for i := 1 to STARS do
  begin
    x := Round(cx + SX[i] / SZ[i] * cx * 0.5);
    y := Round(cy + SY[i] / SZ[i] * cy * 0.5);
    v := Round(255 * (1 - SZ[i]));
    c.Pixels[x, y] := RGBToColor(v, v, v);
    if SZ[i] < 0.3 then c.Pixels[x + 1, y] := RGBToColor(v, v, v);
  end;
  // the credits, rolling up
  c.Brush.Style := bsClear;
  c.Font.Name := 'Courier New';
  c.Font.Style := [fsBold];
  c.Font.Size := 12;
  for i := 0 to High(CreditLines) do
  begin
    y := Round(Scroll + i * 22);
    if (y > -20) and (y < h) then
    begin
      if i mod 3 = 0 then c.Font.Color := clYellow else c.Font.Color := clAqua;
      c.TextOut((w - c.TextWidth(CreditLines[i])) div 2, y, CreditLines[i]);
    end;
  end;
  // the sine scroller along the bottom
  c.Font.Size := 14;
  x := w - ((T * 4) mod (c.TextWidth(Msg) + w));
  for k := 1 to Length(Msg) do
  begin
    ch := Msg[k];
    if (x > -20) and (x < w) then
    begin
      c.Font.Color := RGBToColor(255, Round(128 + 127 * Sin((k + T) / 6)), 64);
      c.TextOut(x, Round(h - 40 + Sin((x + T * 6) / 30) * 10), ch);
    end;
    Inc(x, c.TextWidth(ch));
  end;
  c.Brush.Style := bsSolid;
end;

procedure TCreditsForm.DoTick(Sender: TObject);
var
  i: Integer;
begin
  Inc(T);
  for i := 1 to STARS do
  begin
    SZ[i] := SZ[i] - 0.01;
    if SZ[i] <= 0.02 then
    begin
      SX[i] := Random * 2 - 1; SY[i] := Random * 2 - 1; SZ[i] := 1;
    end;
  end;
  Scroll := Scroll - 1.2;
  if Scroll < -(High(CreditLines) + 1) * 22 then Scroll := Box.Height;
  Box.Invalidate;
end;

procedure TCreditsForm.DoKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ModalResult := mrOk;
end;

procedure TCreditsForm.DoClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure ShowCredits;
var
  f: TCreditsForm;
  i: Integer;
begin
  Randomize;
  f := TCreditsForm.CreateNew(Application);
  try
    f.BorderStyle := bsNone;
    f.Position := poMainFormCenter;
    f.ClientWidth := 560; f.ClientHeight := 420;
    f.KeyPreview := True;
    f.OnKeyDown := @f.DoKey;
    f.Box := TPaintBox.Create(f); f.Box.Parent := f; f.Box.Align := alClient;
    f.Box.OnPaint := @f.DoPaint; f.Box.OnClick := @f.DoClick;
    for i := 1 to STARS do
    begin
      f.SX[i] := Random * 2 - 1; f.SY[i] := Random * 2 - 1; f.SZ[i] := Random;
    end;
    f.Scroll := 420;
    f.Timer := TTimer.Create(f); f.Timer.Interval := 30; f.Timer.OnTimer := @f.DoTick;
    f.ShowModal;
  finally
    f.Free;
  end;
end;

{ ---- the Component Palette: type DELPHI in the About box ---- }

type
  TPaletteForm = class(TForm)
  public
    DragComp: TControl;
    DX, DY: Integer;
    procedure CompDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CompMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure CompUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  end;

procedure TPaletteForm.CompDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  DragComp := TControl(Sender);
  DX := X; DY := Y;
end;

procedure TPaletteForm.CompMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if DragComp = Sender then
    DragComp.SetBounds(DragComp.Left + X - DX, DragComp.Top + Y - DY, DragComp.Width, DragComp.Height);
end;

procedure TPaletteForm.CompUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  DragComp := nil;
end;

procedure ShowPalette;
const
  Names: array[0..2] of string = ('TCaliper', 'TStackLight', 'TTurboButton');
  Icons: array[0..2] of string = ('Cal', 'Regen', 'Turbo');
var
  f: TPaletteForm;
  tabs, form: TPanel;
  i: Integer;
  p: TPanel;
  img: TImage;
  l: TLabel;
  b: TBitmap;
  b2: TButton;
begin
  f := TPaletteForm.CreateNew(Application);
  try
    f.Caption := 'Component Palette';
    f.BorderStyle := bsSizeToolWin;
    f.Position := poMainFormCenter;
    f.ClientWidth := 420; f.ClientHeight := 260;
    tabs := TPanel.Create(f); tabs.Parent := f; tabs.Align := alTop; tabs.Height := 24;
    tabs.Caption := '  Standard | Additional | SolidCraft | Samples'; tabs.Alignment := taLeftJustify;
    form := TPanel.Create(f); form.Parent := f; form.Align := alClient; form.BevelOuter := bvLowered;
    form.Color := clWhite;
    l := TLabel.Create(f); l.Parent := form; l.SetBounds(10, 190, 400, 40); l.WordWrap := True;
    l.Caption := 'Drag the components anywhere you like. They do nothing. ' +
      'Neither did half the components you could buy in 1998.';
    for i := 0 to 2 do
    begin
      p := TPanel.Create(f); p.Parent := form;
      p.SetBounds(20 + i * 130, 30, 110, 70);
      p.BevelOuter := bvRaised;
      p.Caption := '';
      img := TImage.Create(f); img.Parent := p; img.SetBounds(39, 6, 32, 32);
      b := IconBitmap(Icons[i], 2);
      img.Transparent := True;
      img.Picture.Assign(b); b.Free;
      img.Enabled := False;
      l := TLabel.Create(f); l.Parent := p; l.SetBounds(4, 44, 102, 20);
      l.Alignment := taCenter; l.Caption := Names[i];
      l.Enabled := False;
      p.OnMouseDown := @f.CompDown; p.OnMouseMove := @f.CompMove; p.OnMouseUp := @f.CompUp;
      p.Cursor := crSize;
    end;
    b2 := TButton.Create(f); b2.Parent := form; b2.Caption := 'Close';
    b2.Cancel := True; b2.Default := True; b2.ModalResult := mrOk;
    b2.SetBounds(330, 226, 80, 26);
    f.ClientHeight := 290;
    f.ShowModal;
  finally
    f.Free;
  end;
end;

{ ---- About ---- }

type
  TAboutForm = class(TForm)
  public
    Logo: TPaintBox;
    Typed: string;
    procedure LogoPaint(Sender: TObject);
    procedure LogoDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyPressed(Sender: TObject; var Key: Char);
  end;

procedure TAboutForm.LogoPaint(Sender: TObject);
begin
  GradientV(Logo.Canvas, 0, 0, 96, 96, $A00000, $000000);
  DrawLogo(Logo.Canvas, 46, 40, 11, clYellow);
end;

{ Turbo on, Shift-click the logo: a setup program "updates" MSCOMCTL.OCX. }
procedure TAboutForm.LogoDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (ssShift in Shift) and Turbo then ShowSetup;
end;

procedure TAboutForm.KeyPressed(Sender: TObject; var Key: Char);
begin
  Typed := Copy(Typed + UpCase(Key), Length(Typed) - 4, 6);
  if Copy(Typed, Length(Typed) - 4, 5) = 'WIN98' then
  begin
    Typed := '';
    ShowCredits;
  end
  else if Copy(Typed, Length(Typed) - 5, 6) = 'DELPHI' then
  begin
    Typed := '';
    ShowPalette;
  end;
end;

{$IFDEF WINDOWS}
type
  TMemStatusEx = record
    dwLength, dwMemoryLoad: LongWord;
    ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile,
    ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual: QWord;
  end;

function GlobalMemoryStatusEx(var m: TMemStatusEx): LongBool; stdcall; external 'kernel32.dll';
{$ENDIF}

{ The real figure, formatted like it's still impressive. }
function MemoryKB: string;
var
{$IFDEF WINDOWS}
  m: TMemStatusEx;
{$ELSE}
  sl: TStringList;
  i: Integer;
  s: string;
{$ENDIF}
begin
  Result := '65,536';
  {$IFDEF WINDOWS}
  FillChar(m, SizeOf(m), 0);
  m.dwLength := SizeOf(m);
  if GlobalMemoryStatusEx(m) then Result := FormatFloat('#,##0', m.ullTotalPhys / 1024);
  {$ELSE}
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile('/proc/meminfo');
      for i := 0 to sl.Count - 1 do
        if Copy(sl[i], 1, 9) = 'MemTotal:' then
        begin
          s := Trim(StringReplace(Copy(sl[i], 10, MaxInt), 'kB', '', []));
          Result := FormatFloat('#,##0', StrToInt64Def(s, 65536));
        end;
    except
    end;
  finally
    sl.Free;
  end;
  {$ENDIF}
end;

procedure ShowAbout;
var
  f: TAboutForm;
  l: TLabel;
  b: TButton;
  bev: TBevel;
begin
  f := TAboutForm.CreateNew(Application);
  try
    f.Caption := 'About ' + APP_NAME;
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.ClientWidth := 520; f.ClientHeight := 330;
    f.KeyPreview := True;
    f.OnKeyPress := @f.KeyPressed;
    f.Logo := TPaintBox.Create(f); f.Logo.Parent := f; f.Logo.SetBounds(16, 16, 96, 96);
    f.Logo.OnPaint := @f.LogoPaint; f.Logo.OnMouseDown := @f.LogoDown;
    l := TLabel.Create(f); l.Parent := f; l.SetBounds(128, 14, 380, 30);
    l.Font.Size := 16; l.Font.Style := [fsBold]; l.Caption := APP_NAME;
    l := TLabel.Create(f); l.Parent := f; l.SetBounds(128, 48, 380, 20);
    l.Caption := APP_VERSION + '  (' + APP_BUILD + ')';
    l := TLabel.Create(f); l.Parent := f; l.AutoSize := False; l.SetBounds(128, 72, 380, 196);
    l.Caption := APP_EDITION + LineEnding +
      'Built with Object Pascal. Compiles in 0.4 seconds.' + LineEnding + '(It really does.)' + LineEnding + LineEnding +
      'This product is licensed to:' + LineEnding + '    Machine Shop, Back Office PC' + LineEnding + LineEnding +
      {$IFDEF WINDOWS}'Physical memory available to Windows:'{$ELSE}'Physical memory available to Linux:'{$ENDIF} +
      LineEnding + '    ' + MemoryKB + ' KB';
    bev := TBevel.Create(f); bev.Parent := f; bev.Shape := bsTopLine; bev.SetBounds(16, 274, 488, 2);
    l := TLabel.Create(f); l.Parent := f; l.AutoSize := False; l.SetBounds(16, 284, 390, 40); l.WordWrap := True;
    l.Caption := 'Warning: this computer program is protected by a sense of humour.';
    b := TButton.Create(f); b.Parent := f; b.Caption := 'OK'; b.Default := True; b.Cancel := True;
    b.ModalResult := mrOk; b.SetBounds(420, 288, 84, 28);
    f.ShowModal;
  finally
    f.Free;
  end;
end;

{ ---- the splash ---- }

type
  TSplashForm = class(TForm)
  public
    Msg: string;
    procedure DoPaint(Sender: TObject);
  end;

procedure TSplashForm.DoPaint(Sender: TObject);
var
  c: TCanvas;
begin
  c := Canvas;
  GradientV(c, 0, 0, ClientWidth, ClientHeight, $800000, $000000);
  DrawLogo(c, 90, 70, 26, clYellow);
  c.Brush.Style := bsClear;
  c.Font.Name := 'Times New Roman';
  c.Font.Style := [fsBold, fsItalic];
  c.Font.Size := 30; c.Font.Color := clWhite;
  c.TextOut(190, 40, 'SolidCraft');
  c.Font.Size := 40; c.Font.Color := clYellow;
  c.TextOut(330, 84, '98');
  c.Font.Name := 'Arial'; c.Font.Style := []; c.Font.Size := 10; c.Font.Color := $C0C0C0;
  c.TextOut(192, 120, APP_EDITION);
  c.Font.Size := 9;
  c.Font.Color := clWhite; c.TextOut(16, 200, Msg);
  c.Font.Color := $C0C0C0;
  c.TextOut(16, 230, APP_VERSION + '  ' + APP_BUILD);
  c.TextOut(16, 246, 'Copyright (C) 1998-1999 SolidCraft Software. Made with Line and Ellipse.');
  c.Brush.Style := bsSolid;
  c.Pen.Color := clGray;
  c.Brush.Style := bsClear;
  c.Rectangle(0, 0, ClientWidth, ClientHeight);
  c.Brush.Style := bsSolid;
end;

function ShowSplash: TForm;
var
  f: TSplashForm;
begin
  f := TSplashForm.CreateNew(Application);
  f.BorderStyle := bsNone;
  f.Position := poScreenCenter;
  f.ClientWidth := 440; f.ClientHeight := 280;
  f.OnPaint := @f.DoPaint;
  f.Show;
  Application.ProcessMessages;
  Result := f;
end;

{ Shows a loading message, and pauses just long enough to read it. }
procedure SplashProgress(f: TForm; const s: string);
var
  t: QWord;
begin
  TSplashForm(f).Msg := s;
  f.Repaint;
  t := GetTickCount64;
  while GetTickCount64 - t < 350 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

end.
