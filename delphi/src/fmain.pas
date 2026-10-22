{ fMain - the battleship-grey main window: menus, toolbar, status bar, and
  the grey area the part windows live in. Every menu item and toolbar button
  carries a command key and hands it to RunCommand. }
unit fMain;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, Menus, ComCtrls, ExtCtrls, StdCtrls,
  Graphics, Dialogs, ImgList, LCLType, fPart;

type
  TMainForm = class(TForm)
  private
    FMenu: TMainMenu;
    FWindowMenu: TMenuItem;
    FWindowFixed: Integer;
    FShadedItem, FTurboItem: TMenuItem;
    FImages: TImageList;
    FBar: TToolBar;
    FTurboBtn, FShadedBtn: TToolButton;
    FLed: TPaintBox;
    FStatus: TStatusBar;
    FArea: TPanel;
    FClock: TTimer;
    FCmds: TStringList;
    FLastMsg: string;
    FActive: TPartWindow;
    FNewCount: Integer;
    FKonami: Integer;
    // Cal
    FCal: TPanel;
    FCalSay: TLabel;
    FCalHelp, FCalNoHelp: TButton;
    FCalShown, FCalSilenced: Boolean;
    function AddItem(AParent: TMenuItem; const ACaption, ACmd: string; AKey: TShortCut = 0; const AHint: string = ''): TMenuItem;
    procedure BuildMenus;
    procedure BuildToolbar;
    procedure BuildCal;
    procedure ItemClick(Sender: TObject);
    procedure WindowItemClick(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
    procedure LedPaint(Sender: TObject);
    procedure ClockTimer(Sender: TObject);
    procedure ShowHintText(Sender: TObject);
    procedure StatusResize(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure PartActivate(p: TPartWindow);
    procedure PartClose(p: TPartWindow);
    procedure PartEdit(p: TPartWindow);
    procedure CalPaint(Sender: TObject);
    procedure CalClick(Sender: TObject);
    procedure CalHelpClick(Sender: TObject);
    procedure CalNoHelpClick(Sender: TObject);
    procedure CalNeverClick(Sender: TObject);
    function KonamiKey(Key: Word): Boolean;
    procedure KonamiSpin(p: TPartWindow);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ActivePart: TPartWindow;
    function PartCount: Integer;
    function Part(i: Integer): TPartWindow;
    function AddPart(ASlot: Integer): TPartWindow;
    { Asks to save if needed; False if the user cancelled. }
    function ClosePart(p: TPartWindow): Boolean;
    procedure FrontPart(p: TPartWindow);
    procedure Arrange(AKind: Integer);      // 0 cascade, 1 tile horizontally, 2 tile vertically
    procedure PartsChanged;
    procedure RefreshAllParts;
    procedure TurboChanged;
    procedure ShadedChanged;
    procedure SetStatusText(const s: string);
    procedure SetFpsText(const s: string);
    { Open and Save As dialogs. '' on Cancel. }
    function AskFileName(ASave: Boolean; const ADefault, AFilter, AExt: string): string;
    procedure CalPop(const ASay: string);
  end;

var
  MainForm: TMainForm;

implementation

uses Math, uModel, uDocs, uArt, uCommands;

procedure StatusHook(const s: string);
begin
  if MainForm <> nil then MainForm.SetStatusText(s);
end;

procedure FpsHook(const s: string);
begin
  if MainForm <> nil then MainForm.SetFpsText(s);
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  p: TStatusPanel;
begin
  // built in code, so there's no form file to load
  inherited CreateNew(AOwner, 1);
  FCmds := TStringList.Create;
  Caption := APP_NAME;
  Color := clBtnFace;
  Position := poScreenCenter;
  SetBounds(0, 0, 800, 600);
  // On an 800 x 600 screen the window doesn't fit, so take the whole screen.
  if (Width > Screen.Width * 0.95) or (Height > Screen.Height * 0.9) then WindowState := wsMaximized;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  ShowHint := True;

  BuildMenus;
  BuildToolbar;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := False;
  p := FStatus.Panels.Add; p.Width := 500; p.Text := 'Ready';
  p := FStatus.Panels.Add; p.Width := 40; p.Text := 'mm'; p.Alignment := taCenter;
  p := FStatus.Panels.Add; p.Width := 110;
  p := FStatus.Panels.Add; p.Width := 100; p.Alignment := taCenter;
  FStatus.OnResize := @StatusResize;

  FArea := TPanel.Create(Self);
  FArea.Parent := Self;
  FArea.Align := alClient;
  FArea.BevelOuter := bvLowered;
  FArea.Color := $808080;
  FArea.Caption := '';

  BuildCal;

  FClock := TTimer.Create(Self);
  FClock.Interval := 1000;
  FClock.OnTimer := @ClockTimer;

  Application.OnHint := @ShowHintText;
  StatusProc := @StatusHook;
  FpsProc := @FpsHook;
  ClockTimer(nil);
  SetStatusText('Ready');
end;

destructor TMainForm.Destroy;
begin
  StatusProc := nil;
  FpsProc := nil;
  FCmds.Free;
  inherited Destroy;
end;

{ ---- menus ---- }

function TMainForm.AddItem(AParent: TMenuItem; const ACaption, ACmd: string; AKey: TShortCut; const AHint: string): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  if ACmd <> '' then
  begin
    Result.Tag := FCmds.Add(ACmd);
    Result.OnClick := @ItemClick;
  end;
  Result.ShortCut := AKey;
  Result.Hint := AHint;
  AParent.Add(Result);
end;

procedure TMainForm.BuildMenus;
var
  m: TMenuItem;
begin
  FMenu := TMainMenu.Create(Self);
  Menu := FMenu;

  m := AddItem(FMenu.Items, '&File', '');
  AddItem(m, '&New Part', 'New', ShortCut(VK_N, [ssCtrl]), 'Start a new part.');
  AddItem(m, '&Open...', 'Open', ShortCut(VK_O, [ssCtrl]), 'Open a part, or a SolidCraft design.');
  AddItem(m, '&Save', 'Save', ShortCut(VK_S, [ssCtrl]), 'Save the part.');
  AddItem(m, 'Save &As...', 'SaveAs', 0, 'Save the part under a new name.');
  AddItem(m, 'Sen&d To 3 1/2 Floppy (A:)...', 'SaveFloppy', 0, 'Save the part to drive A:.');
  AddItem(m, 'Publish to &Web...', 'Publish', 0, 'Make a home page for the part.');
  AddItem(m, 'Export for &Rapid Prototyping (*.stl)...', 'ExportStl', 0, 'Write the part as an STL file.');
  AddItem(m, '&Close', 'Close', 0, 'Close the part.');
  AddItem(m, '-', '');
  AddItem(m, 'E&xit', 'Exit', 0, 'Quit SolidCraft 98.');

  m := AddItem(FMenu.Items, '&Edit', '');
  AddItem(m, '&Undo Last Feature', 'Undo', ShortCut(VK_Z, [ssCtrl]), 'Remove the last feature.');
  AddItem(m, '-', '');
  AddItem(m, '&Edit Feature...', 'Edit', ShortCut(VK_RETURN, []), 'Change the selected feature''s numbers.');
  AddItem(m, '&Delete Feature', 'Delete', ShortCut(VK_DELETE, []), 'Delete the selected feature.');

  m := AddItem(FMenu.Items, '&Sketch', '');
  AddItem(m, '&Rectangle...', 'SketchRect', ShortCut(VK_R, []), 'Sketch a rectangle.');
  AddItem(m, '&Circle...', 'SketchCircle', ShortCut(VK_C, []), 'Sketch a circle.');

  m := AddItem(FMenu.Items, 'Fea&tures', '');
  AddItem(m, '&Extrude...', 'Extrude', ShortCut(VK_E, []), 'Pull the last sketch up into a solid.');
  AddItem(m, 'Re&volve...', 'Revolve', ShortCut(VK_V, []), 'Spin the last sketch round the Y axis.');
  AddItem(m, '&Hole...', 'Hole', ShortCut(VK_H, []), 'Drill a hole in the top face.');

  m := AddItem(FMenu.Items, '&View', '');
  AddItem(m, '&Isometric', 'ViewIso', ShortCut(VK_I, []), 'Look at the front, right and top.');
  AddItem(m, 'Zoom to &Fit', 'ZoomFit', ShortCut(VK_F, []), 'Fit the part in the window.');
  AddItem(m, '&Regenerate', 'Regen', ShortCut(VK_F5, []), 'Rebuild the part.');
  FShadedItem := AddItem(m, '&Shaded', 'Shaded', ShortCut(VK_S, []), 'Rendered in software, properly.');
  AddItem(m, '-', '');
  FTurboItem := AddItem(m, '&Turbo', 'Turbo', 0, 'Makes everything faster. (It doesn''t.)');

  FWindowMenu := AddItem(FMenu.Items, '&Window', '');
  AddItem(FWindowMenu, '&Cascade', 'Cascade');
  AddItem(FWindowMenu, 'Tile &Horizontally', 'TileH');
  AddItem(FWindowMenu, 'Tile &Vertically', 'TileV');
  FWindowFixed := FWindowMenu.Count;

  m := AddItem(FMenu.Items, '&Help', '');
  AddItem(m, '&Contents', 'Help', ShortCut(VK_F1, []), 'Help.');
  AddItem(m, '-', '');
  AddItem(m, '&About SolidCraft 98...', 'About', 0, 'Version, licence and memory.');
end;

procedure TMainForm.ItemClick(Sender: TObject);
begin
  RunCommand(FCmds[TComponent(Sender).Tag]);
end;

{ ---- the toolbar ---- }

procedure TMainForm.BuildToolbar;
const
  Keys: array[0..16] of string = ('New', 'Open', 'Save', '', 'SketchRect', 'SketchCircle', '',
    'Extrude', 'Revolve', 'Hole', '', 'Orbit', 'Shaded', 'ZoomFit', 'Regen', '', 'Turbo');
  Tips: array[0..16] of string = ('New Part (Ctrl+N)', 'Open Part (Ctrl+O)', 'Save Part (Ctrl+S)', '',
    'Sketch Rectangle (R)', 'Sketch Circle (C)', '', 'Extrude (E)', 'Revolve (V)', 'Hole (H)', '',
    'Isometric View (I). Drag in the viewport to orbit.', 'Shaded (S). Rendered in software, properly.',
    'Zoom to Fit (F)', 'Regenerate (F5)', '', 'Turbo. Makes everything faster. (It doesn''t.)');
var
  i: Integer;
  b: TToolButton;
  icons: array of string;
begin
  FImages := TImageList.Create(Self);
  FImages.Width := 16; FImages.Height := 16;
  SetLength(icons, 0);
  for i := 0 to High(Keys) do
    if Keys[i] <> '' then
    begin
      SetLength(icons, Length(icons) + 1);
      icons[High(icons)] := Keys[i];
    end;
  AddIcons(FImages, icons);

  FBar := TToolBar.Create(Self);
  FBar.Parent := Self;
  FBar.Images := FImages;
  FBar.ButtonWidth := 24; FBar.ButtonHeight := 22;
  FBar.Height := 28;
  FBar.ShowHint := True;
  FBar.Flat := True;
  for i := 0 to High(Keys) do
  begin
    b := TToolButton.Create(Self);
    if Keys[i] = '' then b.Style := tbsSeparator
    else
    begin
      b.ImageIndex := IconIndex(Keys[i]);
      b.Hint := Tips[i];
      b.Tag := FCmds.Add(Keys[i]);
      b.OnClick := @ButtonClick;
      if (Keys[i] = 'Turbo') or (Keys[i] = 'Shaded') then b.Style := tbsCheck;
    end;
    b.Left := i * 30;          // a toolbar keeps its buttons in order of Left
    b.Parent := FBar;
    if Keys[i] = 'Turbo' then FTurboBtn := b;
    if Keys[i] = 'Shaded' then FShadedBtn := b;
  end;
  b := TToolButton.Create(Self);
  b.Style := tbsDivider;
  b.Left := 1000;
  b.Parent := FBar;
  FLed := TPaintBox.Create(Self);
  FLed.Width := 40; FLed.Height := 22;
  FLed.Left := 1010;
  FLed.OnPaint := @LedPaint;
  FLed.Hint := 'MHz';
  FLed.Parent := FBar;
end;

procedure TMainForm.ButtonClick(Sender: TObject);
begin
  RunCommand(FCmds[TComponent(Sender).Tag]);
  // a check button flips itself; put it back to what's really on
  TurboChanged;
  ShadedChanged;
end;

{ The speed LED: two red seven-segment digits on black. }
procedure TMainForm.LedPaint(Sender: TObject);
const
  // segments a b c d e f g, for 0-9
  Seg: array[0..9] of string[7] = ('1111110', '0110000', '1101101', '1111001', '0110011',
    '1011011', '1011111', '1110000', '1111111', '1111011');
var
  c: TCanvas;
  s: string;
  k, x, y, w, h, d: Integer;

  procedure Bar(on: Boolean; x1, y1, x2, y2: Integer);
  begin
    if on then c.Brush.Color := $0000FF else c.Brush.Color := $000040;
    c.FillRect(x1, y1, x2, y2);
  end;

begin
  c := FLed.Canvas;
  c.Brush.Color := clBlack;
  c.FillRect(0, 0, FLed.Width, FLed.Height);
  s := LedDigits;
  w := 9; h := 14; y := (FLed.Height - h) div 2;
  for k := 1 to 2 do
  begin
    x := 6 + (k - 1) * 15;
    d := Ord(s[k]) - Ord('0');
    Bar(Seg[d][1] = '1', x + 1, y, x + w - 1, y + 2);                 // a
    Bar(Seg[d][2] = '1', x + w - 2, y + 1, x + w, y + h div 2);        // b
    Bar(Seg[d][3] = '1', x + w - 2, y + h div 2, x + w, y + h - 1);    // c
    Bar(Seg[d][4] = '1', x + 1, y + h - 2, x + w - 1, y + h);          // d
    Bar(Seg[d][5] = '1', x, y + h div 2, x + 2, y + h - 1);            // e
    Bar(Seg[d][6] = '1', x, y + 1, x + 2, y + h div 2);                // f
    Bar(Seg[d][7] = '1', x + 1, y + h div 2 - 1, x + w - 1, y + h div 2 + 1);   // g
  end;
end;

{ The Turbo button stays pushed in while Turbo is on; the LED shows the "speed". }
procedure TMainForm.TurboChanged;
begin
  FTurboBtn.Down := Turbo;
  FTurboItem.Checked := Turbo;
  FLed.Invalidate;
end;

{ The Shaded button stays pushed in while the view is shaded. }
procedure TMainForm.ShadedChanged;
begin
  FShadedBtn.Down := ViewShaded;
  FShadedItem.Checked := ViewShaded;
end;

{ ---- the status bar ---- }

procedure TMainForm.StatusResize(Sender: TObject);
var
  w: Integer;
begin
  w := FStatus.ClientWidth - 40 - 110 - 100 - 4;
  if w < 100 then w := 100;
  FStatus.Panels[0].Width := w;
end;

procedure TMainForm.SetStatusText(const s: string);
begin
  FLastMsg := s;
  FStatus.Panels[0].Text := s;
end;

procedure TMainForm.SetFpsText(const s: string);
begin
  FStatus.Panels[2].Text := s;
end;

{ Toolbar and menu hints go in the status bar, the way they always did. }
procedure TMainForm.ShowHintText(Sender: TObject);
begin
  if Application.Hint <> '' then FStatus.Panels[0].Text := GetLongHint(Application.Hint)
  else FStatus.Panels[0].Text := FLastMsg;
end;

procedure TMainForm.ClockTimer(Sender: TObject);
begin
  if ClockTick then
  begin
    RefreshAllParts;
    SetStatusText('Happy New Year 19100! All dimensions have been updated.');
  end;
  FStatus.Panels[3].Text := FormatDateTime('h:nn AM/PM', ClockNow);
end;

{ ---- the part windows ---- }

function TMainForm.PartCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FArea.ControlCount - 1 do
    if (FArea.Controls[i] is TPartWindow) and FArea.Controls[i].Visible then Inc(Result);
end;

{ The i-th part window, in the order they were opened. }
function TMainForm.Part(i: Integer): TPartWindow;
var
  k: Integer;
begin
  for k := 0 to ComponentCount - 1 do
    if (Components[k] is TPartWindow) and TPartWindow(Components[k]).Visible then
    begin
      if i = 0 then Exit(TPartWindow(Components[k]));
      Dec(i);
    end;
  Result := nil;
end;

function TMainForm.ActivePart: TPartWindow;
begin
  Result := FActive;
end;

function TMainForm.AddPart(ASlot: Integer): TPartWindow;
var
  w, h, k: Integer;
begin
  Result := TPartWindow.CreatePart(Self, FArea, ASlot);
  Result.OnActivatePart := @PartActivate;
  Result.OnClosePart := @PartClose;
  Result.OnEditFeature := @PartEdit;
  w := Max(420, FArea.ClientWidth * 17 div 20);
  h := Max(320, FArea.ClientHeight * 17 div 20);
  k := FNewCount mod 6;
  Inc(FNewCount);
  Result.SetBounds(k * 24, k * 24, Min(w, FArea.ClientWidth), Min(h, FArea.ClientHeight));
  Result.RefreshAll(False);
  FrontPart(Result);
end;

procedure TMainForm.FrontPart(p: TPartWindow);
var
  i: Integer;
begin
  for i := 0 to FArea.ControlCount - 1 do
    if FArea.Controls[i] is TPartWindow then
      TPartWindow(FArea.Controls[i]).SetActive(FArea.Controls[i] = p);
  FActive := p;
  if p <> nil then
  begin
    p.BringToFront;
    if FCal.Visible then FCal.BringToFront;
  end;
  PartsChanged;
end;

procedure TMainForm.PartActivate(p: TPartWindow);
begin
  if p <> FActive then FrontPart(p);
end;

procedure TMainForm.PartClose(p: TPartWindow);
begin
  ClosePart(p);
end;

procedure TMainForm.PartEdit(p: TPartWindow);
begin
  EditFeature(p, p.Selected);
end;

{ Asks before closing a part with unsaved changes, also when the whole
  program is closing: Cancel here stops the exit. }
function TMainForm.ClosePart(p: TPartWindow): Boolean;
var
  i: Integer;
  topPart: TPartWindow;
begin
  Result := False;
  if DocDirty[p.Slot] then
  begin
    FrontPart(p);
    case MsgBox('Save changes to ' + Docs[p.Slot].Title + '?', MB_QUESTION or MB_YESNOCANCEL) of
      IDYES:
        begin
          RunCommand('Save');
          if DocDirty[p.Slot] then Exit;
        end;
      IDCANCEL: Exit;
    end;
  end;
  FreeDocSlot(p.Slot);
  p.Visible := False;
  if FActive = p then FActive := nil;
  // freed once its own mouse handler (the close button) has finished
  Application.ReleaseComponent(p);
  topPart := nil;
  for i := 0 to FArea.ControlCount - 1 do
    if (FArea.Controls[i] is TPartWindow) and FArea.Controls[i].Visible then topPart := TPartWindow(FArea.Controls[i]);
  FrontPart(topPart);
  Result := True;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  p: TPartWindow;
begin
  // one question per unsaved part; Cancel on any of them keeps SolidCraft open
  p := ActivePart;
  while p <> nil do
  begin
    if not ClosePart(p) then
    begin
      CanClose := False;
      Exit;
    end;
    p := ActivePart;
  end;
end;

procedure TMainForm.RefreshAllParts;
var
  i: Integer;
begin
  for i := 0 to FArea.ControlCount - 1 do
    if (FArea.Controls[i] is TPartWindow) and FArea.Controls[i].Visible then
      TPartWindow(FArea.Controls[i]).RefreshAll(False);
end;

{ The Window menu lists the parts, with a tick by the one in front. }
procedure TMainForm.PartsChanged;
var
  i, n: Integer;
  m: TMenuItem;
  p: TPartWindow;
begin
  while FWindowMenu.Count > FWindowFixed do FWindowMenu.Items[FWindowFixed].Free;
  n := PartCount;
  if n = 0 then Exit;
  AddItem(FWindowMenu, '-', '');
  for i := 0 to n - 1 do
  begin
    p := Part(i);
    m := TMenuItem.Create(Self);
    m.Caption := '&' + IntToStr(i + 1) + ' ' + DocTitle(p.Slot);
    m.Tag := i;
    m.Checked := p = FActive;
    m.OnClick := @WindowItemClick;
    FWindowMenu.Add(m);
  end;
  for i := 0 to n - 1 do Part(i).RefreshNames;
end;

procedure TMainForm.WindowItemClick(Sender: TObject);
var
  p: TPartWindow;
begin
  p := Part(TComponent(Sender).Tag);
  if p = nil then Exit;
  if p.Minimized then p.ToggleMinimize;
  FrontPart(p);
end;

procedure TMainForm.Arrange(AKind: Integer);
const
  MIN_W = 240; MIN_H = 200;
var
  list: array of TPartWindow;
  i, n, aw, ah, cols, rows, w, h, k: Integer;
  p: TPartWindow;
begin
  SetLength(list, 0);
  ah := FArea.ClientHeight;
  for i := 0 to FArea.ControlCount - 1 do
    if (FArea.Controls[i] is TPartWindow) and FArea.Controls[i].Visible then
    begin
      p := TPartWindow(FArea.Controls[i]);
      if p.Minimized then ah := FArea.ClientHeight - CAPTION_H - 8
      else
      begin
        SetLength(list, Length(list) + 1);
        list[High(list)] := p;
      end;
    end;
  n := Length(list);
  if n = 0 then Exit;
  aw := FArea.ClientWidth;
  case AKind of
    0: begin
         // the one in front ends up last, on top, bottom right
         w := Max(MIN_W * 2, aw - 24 * (n - 1));
         h := Max(MIN_H * 2, ah - 24 * (n - 1));
         for i := 0 to n - 1 do
         begin
           k := i mod 8;
           list[i].SetBounds(k * 24, k * 24, Min(w, aw), Min(h, ah));
         end;
       end;
    1, 2:
       begin
         if AKind = 1 then
         begin
           // one above the other; columns too when they'd get too short
           rows := Max(1, Min(n, ah div MIN_H));
           cols := (n + rows - 1) div rows;
         end
         else
         begin
           cols := Max(1, Min(n, aw div MIN_W));
           rows := (n + cols - 1) div cols;
         end;
         for i := 0 to n - 1 do
         begin
           if AKind = 1 then
           begin
             w := aw div cols; h := ah div rows;
             list[i].SetBounds((i div rows) * w, (i mod rows) * h, w, h);
           end
           else
           begin
             w := aw div cols; h := ah div rows;
             list[i].SetBounds((i mod cols) * w, (i div cols) * h, w, h);
           end;
         end;
       end;
  end;
  for i := 0 to n - 1 do list[i].ZoomFit;
  if FActive <> nil then FActive.BringToFront;
end;

{ ---- keys ---- }

{ Up, up, down, down, left, right, left, right, B, A. True when it completes. }
function TMainForm.KonamiKey(Key: Word): Boolean;
const
  Seq: array[0..9] of Word = (VK_UP, VK_UP, VK_DOWN, VK_DOWN, VK_LEFT, VK_RIGHT, VK_LEFT, VK_RIGHT, VK_B, VK_A);
begin
  Result := False;
  if Key = Seq[FKonami] then
  begin
    Inc(FKonami);
    if FKonami > High(Seq) then
    begin
      FKonami := 0;
      Result := True;
    end;
  end
  else if Key = Seq[0] then FKonami := 1
  else if not (Key in [VK_SHIFT, VK_CONTROL, VK_MENU]) then FKonami := 0;
end;

{ Three seconds of full-speed spin. The frame counter is decorative. }
procedure TMainForm.KonamiSpin(p: TPartWindow);
var
  t: QWord;
  y0: Double;
begin
  t := GetTickCount64;
  y0 := p.View.Yaw;
  p.Spinning := True;
  SetFpsText('60 fps (lying)');
  SetStatusText('Cheat activated. Full speed for three seconds.');
  while GetTickCount64 - t < 3000 do
  begin
    p.View.Yaw := y0 + (GetTickCount64 - t) / 1000 * 240;
    p.Redraw;
    p.Update;
    Application.ProcessMessages;
    if not p.Visible then Exit;
  end;
  p.View.Yaw := y0;
  p.Spinning := False;
  p.Redraw;
  SetFpsText('60 fps (lying)');
end;

procedure TMainForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  p: TPartWindow;
begin
  p := ActivePart;
  if p = nil then Exit;
  if KonamiKey(Key) then
  begin
    Key := 0;
    KonamiSpin(p);
    Exit;
  end;
  if Shift <> [] then Exit;
  case Key of
    VK_ADD, VK_OEM_PLUS: begin p.ZoomBy(1.25); Key := 0; end;
    VK_SUBTRACT, VK_OEM_MINUS: begin p.ZoomBy(0.8); Key := 0; end;
  end;
end;

{ ---- file dialogs ---- }

function TMainForm.AskFileName(ASave: Boolean; const ADefault, AFilter, AExt: string): string;
var
  d: TOpenDialog;
  filter, ext, dir: string;
begin
  Result := '';
  filter := AFilter;
  ext := AExt;
  if filter = '' then filter := 'SolidCraft 98 Parts (*.sc98)|*.sc98';
  if ext = '' then ext := PART_EXT;
  if ASave then d := TSaveDialog.Create(Self) else d := TOpenDialog.Create(Self);
  try
    d.Filter := filter;
    d.DefaultExt := ext;
    dir := IncludeTrailingPathDelimiter(GetUserDir) + 'Documents';
    if DirectoryExists(dir) then d.InitialDir := dir else d.InitialDir := GetUserDir;
    if ASave then
    begin
      d.FileName := ADefault;
      d.Options := d.Options + [ofOverwritePrompt, ofPathMustExist];
      d.Title := 'Save As';
    end
    else
    begin
      d.Options := d.Options + [ofFileMustExist];
      d.Title := 'Open';
    end;
    if d.Execute then
    begin
      Result := d.FileName;
      if ASave and (ExtractFileExt(Result) = '') then Result := Result + '.' + ext;
    end;
  finally
    d.Free;
  end;
end;

{ ---- Cal, the office-assistant caliper. Our own pixel art. Pops up the
  first time you sketch a rectangle in a run. Turbo on or off. ---- }

procedure TMainForm.BuildCal;
var
  pb: TPaintBox;
  b: TButton;
begin
  FCal := TPanel.Create(Self);
  FCal.Parent := FArea;
  FCal.Visible := False;
  FCal.Width := 300; FCal.Height := 170;
  FCal.Color := $E1FFFF;
  FCal.BevelOuter := bvRaised;
  FCal.Caption := '';
  FCal.Anchors := [akRight, akBottom];
  pb := TPaintBox.Create(Self);
  pb.Parent := FCal;
  pb.SetBounds(8, 8, 48, 48);
  pb.OnPaint := @CalPaint;
  pb.OnClick := @CalClick;
  FCalSay := TLabel.Create(Self);
  FCalSay.Parent := FCal;
  FCalSay.SetBounds(64, 8, 228, 80);
  FCalSay.AutoSize := False;
  FCalSay.WordWrap := True;
  FCalHelp := TButton.Create(Self);
  FCalHelp.Parent := FCal;
  FCalHelp.SetBounds(8, 92, 284, 22);
  FCalHelp.Caption := '&Get help with drawing the box';
  FCalHelp.OnClick := @CalHelpClick;
  FCalNoHelp := TButton.Create(Self);
  FCalNoHelp.Parent := FCal;
  FCalNoHelp.SetBounds(8, 116, 284, 22);
  FCalNoHelp.OnClick := @CalNoHelpClick;
  b := TButton.Create(Self);
  b.Parent := FCal;
  b.SetBounds(8, 140, 284, 22);
  b.Caption := '&Don''t show me this tip again';
  b.OnClick := @CalNeverClick;
end;

procedure TMainForm.CalPaint(Sender: TObject);
begin
  TPaintBox(Sender).Canvas.Brush.Color := FCal.Color;
  TPaintBox(Sender).Canvas.FillRect(0, 0, 48, 48);
  PaintIcon(TPaintBox(Sender).Canvas, 'Cal', 0, 0, 3);
end;

procedure TMainForm.CalPop(const ASay: string);
begin
  if FCalSilenced or FCalShown then Exit;
  FCalShown := True;     // once per run is plenty
  FCalSay.Caption := ASay + LineEnding + LineEnding + 'Would you like help?';
  FCalHelp.Visible := True;
  FCalNoHelp.Caption := '&Just draw the box without help';
  FCal.SetBounds(FArea.ClientWidth - FCal.Width - 12, FArea.ClientHeight - FCal.Height - 12, FCal.Width, FCal.Height);
  // shown without taking the focus: you can keep typing while Cal watches
  FCal.Visible := True;
  FCal.BringToFront;
end;

procedure TMainForm.CalClick(Sender: TObject);
begin
  FCalSay.Caption := 'Did you know? Every SolidCraft 98 file is also a perfectly good door stop, if you print it out.';
end;

procedure TMainForm.CalHelpClick(Sender: TObject);
begin
  FCalSay.Caption := 'Here''s a tip: boxes usually want to be extruded.' + LineEnding +
    'Press E. If that doesn''t work, press E harder.';
  FCalHelp.Visible := False;
  FCalNoHelp.Caption := '&Thanks, Cal';
end;

procedure TMainForm.CalNoHelpClick(Sender: TObject);
begin
  FCal.Visible := False;
end;

procedure TMainForm.CalNeverClick(Sender: TObject);
begin
  FCalSilenced := True;
  MsgBox('OK. Cal won''t show this tip again.' + LineEnding + '(Until you restart SolidCraft 98.)', MB_INFO, 'Cal');
  FCal.Visible := False;
end;

end.
