{ uDocs - the open parts, message boxes, and Turbo (the LED, the clock, Y2K
  and the solver). Every fake here is only drawn on screen: nothing touches
  system files, the clock or a disk drive. }
unit uDocs;

{$mode objfpc}{$H+}

interface

uses uModel;

const
  MAX_DOCS = 16;
  PART_EXT = 'sc98';
  FLOPPY_BYTES = 1457664;      // a formatted 3 1/2" HD floppy

  MB_OK = 0; MB_OKCANCEL = 1; MB_YESNOCANCEL = 3; MB_YESNO = 4;
  MB_CRITICAL = $10; MB_QUESTION = $20; MB_EXCLAMATION = $30; MB_INFO = $40;
  MB_DEFBUTTON2 = $100;
  IDOK = 1; IDCANCEL = 2; IDYES = 6; IDNO = 7;

var
  Docs: array[1..MAX_DOCS] of TDesign;
  DocPath: array[1..MAX_DOCS] of string;
  DocDirty: array[1..MAX_DOCS] of Boolean;
  DocInUse: array[1..MAX_DOCS] of Boolean;
  Turbo: Boolean;
  ViewShaded: Boolean;
  StatusProc: procedure(const s: string) = nil;     // the main window's status bar
  FpsProc: procedure(const s: string) = nil;

procedure SetStatus(const s: string);
procedure SetFps(const s: string);

function NewDocSlot: Integer;
procedure FreeDocSlot(i: Integer);
function DocTitle(i: Integer): string;
function FileTitle(const APath: string): string;

{ VB's MsgBox, with the same flags and answers. }
function MsgBox(const APrompt: string; AFlags: Integer = MB_OK; const ATitle: string = 'SolidCraft 98'): Integer;

function LedDigits: string;
function OrbitFrameInterval: Double;
procedure InitClock;
function ClockNow: TDateTime;
{ Called every second: on 31 Dec 1999 at midnight, with Turbo on, the year
  rolls over the way a two-digit year does. True if it just happened. }
function ClockTick: Boolean;
function SolverConverges(var ATries: Integer): Boolean;

implementation

uses SysUtils, DateUtils, Forms, LCLType;

var
  Untitled: Integer;
  ClockOffset: Double;
  SawNewYearsEve: Boolean;

procedure SetStatus(const s: string);
begin
  if Assigned(StatusProc) then StatusProc(s);
end;

procedure SetFps(const s: string);
begin
  if Assigned(FpsProc) then FpsProc(s);
end;

function NewDocSlot: Integer;
var
  i: Integer;
begin
  for i := 1 to MAX_DOCS do
    if not DocInUse[i] then
    begin
      Inc(Untitled);
      NewDesign(Docs[i], 'Part' + IntToStr(Untitled));
      DocPath[i] := '';
      DocDirty[i] := False;
      DocInUse[i] := True;
      Exit(i);
    end;
  Result := 0;
end;

procedure FreeDocSlot(i: Integer);
begin
  if (i >= 1) and (i <= MAX_DOCS) then DocInUse[i] := False;
end;

function DocTitle(i: Integer): string;
begin
  Result := Docs[i].Title;
  if DocDirty[i] then Result := Result + ' *';
end;

function FileTitle(const APath: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(APath), '');
end;

function MsgBox(const APrompt: string; AFlags: Integer; const ATitle: string): Integer;
var
  f: LongInt;
begin
  f := 0;
  case AFlags and 7 of
    MB_OKCANCEL: f := LCLType.MB_OKCANCEL;
    MB_YESNOCANCEL: f := LCLType.MB_YESNOCANCEL;
    MB_YESNO: f := LCLType.MB_YESNO;
  else
    f := LCLType.MB_OK;
  end;
  case AFlags and $70 of
    MB_CRITICAL: f := f or LCLType.MB_ICONERROR;
    MB_QUESTION: f := f or LCLType.MB_ICONQUESTION;
    MB_EXCLAMATION: f := f or LCLType.MB_ICONWARNING;
    MB_INFO: f := f or LCLType.MB_ICONINFORMATION;
  end;
  if AFlags and MB_DEFBUTTON2 <> 0 then f := f or LCLType.MB_DEFBUTTON2;
  Result := Application.MessageBox(PChar(APrompt), PChar(ATitle), f);
end;

function LedDigits: string;
begin
  if Turbo then Result := '33' else Result := '66';
end;

function OrbitFrameInterval: Double;
begin
  if Turbo then Result := 0.25 else Result := 0;
end;

{ Starting with /Y2KTEST (or --y2ktest) pretends it's a minute to midnight on
  31 Dec 1999, so the Y2K bug can be seen without touching the PC's clock. }
procedure InitClock;
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    if (UpperCase(ParamStr(i)) = '/Y2KTEST') or (LowerCase(ParamStr(i)) = '--y2ktest') then
      ClockOffset := EncodeDateTime(1999, 12, 31, 23, 59, 0, 0) - Now;
end;

function ClockNow: TDateTime;
begin
  Result := Now + ClockOffset;
end;

function Y2KText: string;
begin
  Result := '19' + IntToStr(YearOf(ClockNow) - 1900);
end;

function ClockTick: Boolean;
var
  t: TDateTime;
begin
  Result := False;
  if not Turbo or Y2KHappened then Exit;
  t := ClockNow;
  if (YearOf(t) = 1999) and (MonthOf(t) = 12) and (DayOf(t) = 31) then SawNewYearsEve := True;
  if SawNewYearsEve and (YearOf(t) = 2000) then
  begin
    Y2KHappened := True;
    Result := True;
  end;
end;

{ The solver: Variant everything; converges on the third try. }
function SolverConverges(var ATries: Integer): Boolean;
var
  residual: Variant;
begin
  if not Turbo then Exit(True);
  Inc(ATries);
  residual := '0.' + StringOfChar('9', 3 - ATries) + '1';     // a String, a Double, who's counting
  if ATries < 3 then
  begin
    MsgBox('Did not converge. Try again.' + LineEnding + LineEnding + 'Residual: ' + string(residual),
      MB_EXCLAMATION, 'Constraint Solver');
    Exit(False);
  end;
  ATries := 0;
  MsgBox('Converged. See? Variant works.', MB_INFO, 'Constraint Solver');
  Result := True;
end;

initialization
  Y2KDimension := @Y2KText;
end.
