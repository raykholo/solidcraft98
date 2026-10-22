{ fPart - one part window: the feature tree (TTreeView) on the left, the
  viewport (a TPaintBox, wireframe or shaded) on the right, the timeline
  (TListView, report style) along the bottom.

  Lazarus has MDI only on Windows, so the part windows are our own: panels
  with a caption bar inside the main window's grey area, which work on every
  widget set and look like MDI children did. }
unit fPart;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics, Forms,
  uModel, uKernel, uMesh, uView, uShade, uDocs;

const
  CAPTION_H = 20;

type
  TPartWindow = class;
  TPartEvent = procedure(p: TPartWindow) of object;

  TPartWindow = class(TCustomPanel)
  private
    FCaption: TPaintBox;
    FTree: TTreeView;
    FView: TPaintBox;
    FList: TListView;
    FGrip: TPaintBox;
    FTimer: TTimer;
    FBack, FShaded: TBitmap;
    FEdges: TEdgeArray;
    FEdgeN: Integer;
    FTris: TTriArray;
    FTriN: Integer;
    FFaces: TIntArray;
    FMeshOk: Boolean;
    FRevealing: Boolean;
    FRevealStart: QWord;
    FRevealMs: Integer;
    FRevealRows: Integer;
    FDrag: Integer;               // 0 none, 1 orbit, 2 pan, 3 move window, 4 resize
    FDragX, FDragY: Integer;
    FMoved: Boolean;
    FLastDraw: QWord;
    FFrames: Integer;
    FFrameStart: QWord;
    FActive: Boolean;
    FMinimized: Boolean;
    FSaved: TRect;
    FFilling: Boolean;
    procedure CaptionPaint(Sender: TObject);
    procedure CaptionDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CaptionMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure CaptionUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CaptionDblClick(Sender: TObject);
    procedure GripPaint(Sender: TObject);
    procedure GripDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GripMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GripUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewPaint(Sender: TObject);
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure AnyDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TreeClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected_: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure FillTree;
    procedure FillTimeline;
    procedure EnsureBitmaps;
    function ButtonAt(x: Integer): Integer;
  protected
    procedure Resize; override;
  public
    Slot: Integer;
    View: TView;
    Selected: Integer;            // feature picked in the tree or timeline
    RegenTries: Integer;
    Spinning: Boolean;
    OnActivatePart: TPartEvent;
    OnClosePart: TPartEvent;      // asks, and frees it if allowed
    OnEditFeature: TPartEvent;    // Selected is the feature
    constructor CreatePart(AOwner: TComponent; AParent: TWinControl; ASlot: Integer);
    destructor Destroy; override;
    procedure SetActive(AValue: Boolean);
    procedure RefreshAll(AFit: Boolean);
    procedure RefreshNames;
    procedure Redraw;
    procedure ViewIso;
    procedure ZoomFit;
    procedure Regen;
    procedure ZoomBy(k: Double);
    procedure ToggleMinimize;
    procedure SelectFeature(i: Integer);
    function ViewBitmap: TBitmap;
    property IsActive: Boolean read FActive;
    property Minimized: Boolean read FMinimized;
    property TriCount: Integer read FTriN;
  end;

implementation

uses uArt;

const
  TREE_W = 170;
  TL_H = 140;
  BAND = 6;

constructor TPartWindow.CreatePart(AOwner: TComponent; AParent: TWinControl; ASlot: Integer);
begin
  inherited Create(AOwner);
  Slot := ASlot;
  Parent := AParent;
  BevelOuter := bvRaised;
  BevelInner := bvRaised;
  BorderWidth := 1;
  Color := clBtnFace;
  ResetView(View);
  FBack := TBitmap.Create;
  FShaded := TBitmap.Create;

  FCaption := TPaintBox.Create(Self);
  FCaption.Parent := Self;
  FCaption.OnPaint := @CaptionPaint;
  FCaption.OnMouseDown := @CaptionDown;
  FCaption.OnMouseMove := @CaptionMove;
  FCaption.OnMouseUp := @CaptionUp;
  FCaption.OnDblClick := @CaptionDblClick;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.ShowRoot := True;
  FTree.ScrollBars := ssAutoBoth;
  FTree.OnClick := @TreeClick;
  FTree.OnSelectionChanged := @TreeClick;     // the arrow keys too
  FTree.OnDblClick := @TreeDblClick;
  FTree.OnMouseDown := @AnyDown;

  FView := TPaintBox.Create(Self);
  FView.Parent := Self;
  FView.Cursor := crSizeAll;
  FView.OnPaint := @ViewPaint;
  FView.OnMouseDown := @ViewDown;
  FView.OnMouseMove := @ViewMove;
  FView.OnMouseUp := @ViewUp;
  FView.OnMouseWheel := @ViewWheel;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.GridLines := True;
  with FList.Columns.Add do begin Caption := '#'; Width := 34; end;
  with FList.Columns.Add do begin Caption := 'Feature'; Width := 110; end;
  with FList.Columns.Add do begin Caption := 'Type'; Width := 125; end;
  with FList.Columns.Add do begin Caption := 'Parameters'; Width := 280; end;
  with FList.Columns.Add do begin Caption := 'Status'; Width := 170; end;
  FList.OnClick := @ListClick;
  FList.OnSelectItem := @ListSelect;
  FList.OnDblClick := @ListDblClick;
  FList.OnMouseDown := @AnyDown;

  FGrip := TPaintBox.Create(Self);
  FGrip.Parent := Self;
  FGrip.Cursor := crSizeNWSE;
  FGrip.OnPaint := @GripPaint;
  FGrip.OnMouseDown := @GripDown;
  FGrip.OnMouseMove := @GripMove;
  FGrip.OnMouseUp := @GripUp;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 30;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
end;

destructor TPartWindow.Destroy;
begin
  FGrip := nil;              // no more layout while the children go
  if FTimer <> nil then FTimer.Enabled := False;
  inherited Destroy;
  FBack.Free;
  FShaded.Free;
end;

procedure TPartWindow.Resize;
var
  w, h, ch, tl: Integer;
begin
  inherited Resize;
  if (FGrip = nil) or (FTimer = nil) then Exit;     // still being built
  w := ClientWidth; h := ClientHeight;
  FCaption.SetBounds(0, 0, w, CAPTION_H);
  if FMinimized then Exit;
  ch := h - CAPTION_H;
  tl := TL_H;
  if tl > ch div 3 then tl := ch div 3;      // tiled small: the view keeps two thirds
  FTree.SetBounds(0, CAPTION_H + 1, TREE_W, ch - tl - 4);
  FView.SetBounds(TREE_W + 3, CAPTION_H + 1, w - TREE_W - 3, ch - tl - 4);
  FList.SetBounds(0, h - tl, w, tl - 12);
  FGrip.SetBounds(w - 12, h - 12, 12, 12);
  if Slot <> 0 then
  begin
    EnsureBitmaps;
    Redraw;
  end;
end;

procedure TPartWindow.SetActive(AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  FCaption.Invalidate;
end;

procedure TPartWindow.AnyDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Assigned(OnActivatePart) then OnActivatePart(Self);
end;

{ ---- the caption bar: title, and minimise, maximise and close ---- }

function TPartWindow.ButtonAt(x: Integer): Integer;
var
  bx: Integer;
begin
  bx := FCaption.Width - 2 - 16;
  if (x >= bx) and (x < bx + 16) then Exit(2);              // close
  if (x >= bx - 18) and (x < bx - 2) then Exit(1);           // maximise / restore
  if (x >= bx - 34) and (x < bx - 18) then Exit(0);          // minimise
  Result := -1;
end;

procedure DrawCaptionButton(c: TCanvas; x, y, kind: Integer; disabled: Boolean);
var
  i: Integer;
  col: TColor;
begin
  c.Brush.Color := clBtnFace;
  c.FillRect(x, y, x + 16, y + 14);
  c.Pen.Color := clWhite; c.Line(x, y + 13, x, y); c.Line(x, y, x + 15, y);
  c.Pen.Color := clBlack; c.Line(x + 15, y, x + 15, y + 14); c.Line(x, y + 13, x + 16, y + 13);
  c.Pen.Color := clGray; c.Line(x + 14, y + 1, x + 14, y + 13); c.Line(x + 1, y + 12, x + 14, y + 12);
  if disabled then col := clGray else col := clBlack;
  c.Pen.Color := col; c.Brush.Color := col;
  case kind of
    0: c.FillRect(x + 4, y + 9, x + 10, y + 11);
    1: begin
         c.Brush.Style := bsClear;
         c.Rectangle(x + 3, y + 2, x + 12, y + 11);
         c.Line(x + 3, y + 3, x + 12, y + 3);
         c.Brush.Style := bsSolid;
       end;
    2: for i := 0 to 5 do
       begin
         c.FillRect(x + 4 + i, y + 3 + i, x + 6 + i, y + 4 + i);
         c.FillRect(x + 9 - i, y + 3 + i, x + 11 - i, y + 4 + i);
       end;
    3: begin
         c.Brush.Style := bsClear;
         c.Rectangle(x + 5, y + 2, x + 11, y + 7);
         c.Rectangle(x + 3, y + 5, x + 9, y + 10);
         c.Brush.Style := bsSolid;
       end;
  end;
end;

procedure TPartWindow.CaptionPaint(Sender: TObject);
var
  c: TCanvas;
  w, bx: Integer;
begin
  c := FCaption.Canvas;
  w := FCaption.Width;
  if FActive then GradientH(c, 0, 0, w, CAPTION_H, $800000, $D08410)
  else GradientH(c, 0, 0, w, CAPTION_H, $808080, $B5B5B5);
  PaintIcon(c, 'App', 2, 2);
  c.Brush.Style := bsClear;
  c.Font.Style := [fsBold];
  if FActive then c.Font.Color := clWhite else c.Font.Color := $C8D0D4;
  c.TextOut(22, (CAPTION_H - c.TextHeight('Xy')) div 2, DocTitle(Slot));
  c.Brush.Style := bsSolid;
  bx := w - 2 - 16;
  DrawCaptionButton(c, bx, 3, 2, False);
  if FMinimized then DrawCaptionButton(c, bx - 18, 3, 3, False)
  else DrawCaptionButton(c, bx - 18, 3, 1, True);
  DrawCaptionButton(c, bx - 34, 3, 0, FMinimized);
end;

procedure TPartWindow.CaptionDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Assigned(OnActivatePart) then OnActivatePart(Self);
  case ButtonAt(X) of
    2: begin
         if Assigned(OnClosePart) then OnClosePart(Self);
         Exit;
       end;
    1: begin if FMinimized then ToggleMinimize; Exit; end;
    0: begin if not FMinimized then ToggleMinimize; Exit; end;
  end;
  FDrag := 3;
  FDragX := X; FDragY := Y;
end;

procedure TPartWindow.CaptionMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FDrag <> 3 then Exit;
  SetBounds(Left + X - FDragX, Top + Y - FDragY, Width, Height);
  if Top < 0 then Top := 0;
end;

procedure TPartWindow.CaptionUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDrag := 0;
end;

procedure TPartWindow.CaptionDblClick(Sender: TObject);
begin
  if FMinimized then ToggleMinimize;
end;

procedure TPartWindow.ToggleMinimize;
var
  n, i: Integer;
begin
  if FMinimized then
  begin
    FMinimized := False;
    FTree.Visible := True; FView.Visible := True; FList.Visible := True; FGrip.Visible := True;
    BoundsRect := FSaved;
  end
  else
  begin
    FSaved := BoundsRect;
    FMinimized := True;
    FTree.Visible := False; FView.Visible := False; FList.Visible := False; FGrip.Visible := False;
    n := 0;
    for i := 0 to Parent.ControlCount - 1 do
      if (Parent.Controls[i] is TPartWindow) and (Parent.Controls[i] <> Self) and TPartWindow(Parent.Controls[i]).Minimized then
        Inc(n);
    SetBounds(n * 162, Parent.ClientHeight - CAPTION_H - 6, 160, CAPTION_H + 6);
  end;
  FCaption.Invalidate;
end;

{ ---- the size grip ---- }

procedure TPartWindow.GripPaint(Sender: TObject);
var
  c: TCanvas;
  i: Integer;
begin
  c := FGrip.Canvas;
  c.Brush.Color := clBtnFace;
  c.FillRect(0, 0, 12, 12);
  for i := 0 to 2 do
  begin
    c.Pen.Color := clWhite; c.Line(9 - i * 4, 11, 11, 9 - i * 4);
    c.Pen.Color := clGray; c.Line(10 - i * 4, 11, 11, 10 - i * 4);
  end;
end;

procedure TPartWindow.GripDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Assigned(OnActivatePart) then OnActivatePart(Self);
  FDrag := 4;
  FDragX := X; FDragY := Y;
end;

procedure TPartWindow.GripMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  w, h: Integer;
begin
  if FDrag <> 4 then Exit;
  w := Width + X - FDragX; h := Height + Y - FDragY;
  if w < 260 then w := 260;
  if h < 220 then h := 220;
  SetBounds(Left, Top, w, h);
end;

procedure TPartWindow.GripUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDrag := 0;
  FitView(View, FBack.Width, FBack.Height, FEdges, FEdgeN);
  Redraw;
end;

{ ---- the view ---- }

procedure TPartWindow.EnsureBitmaps;
var
  w, h: Integer;
begin
  w := FView.Width; h := FView.Height;
  if w < 16 then w := 16;
  if h < 16 then h := 16;
  if (FBack.Width <> w) or (FBack.Height <> h) then
  begin
    FBack.SetSize(w, h);
    FShaded.SetSize(w, h);
  end;
end;

function TPartWindow.ViewBitmap: TBitmap;
begin
  Result := FBack;
end;

procedure TPartWindow.ViewPaint(Sender: TObject);
begin
  FView.Canvas.Draw(0, 0, FBack);
end;

procedure DrawLabel(c: TCanvas; const t: string);
begin
  c.Brush.Style := bsClear;
  c.Font.Style := [];
  c.Font.Color := $404040;
  c.TextOut(6, 4, t);
  c.Brush.Style := bsSolid;
end;

{ Wireframe, or (when shaded, and the view isn't moving) a shaded render
  that the timer reveals a few rows at a time. }
procedure TPartWindow.Redraw;
var
  i: Integer;
  serr: string;
  moving: Boolean;
begin
  EnsureBitmaps;
  moving := (FDrag = 1) or (FDrag = 2) or Spinning;
  if ViewShaded and not moving and (Docs[Slot].Count > 0) then
  begin
    if not FMeshOk then
    begin
      FTriN := MeshDesign(Docs[Slot], FTris, 32, serr);
      FaceGroups(FTris, FTriN, FFaces);
      FMeshOk := True;
    end;
    // the background now; the shaded picture, revealed over it
    DrawScene(FBack.Canvas, View, FBack.Width, FBack.Height, FEdges, 0);
    DrawScene(FShaded.Canvas, View, FShaded.Width, FShaded.Height, FEdges, 0);
    if FTriN > 0 then RenderShaded(FShaded, View, FTris, FTriN, FFaces, Docs[Slot]);
    // sketches nothing is built on yet, drawn over the top
    for i := 0 to FEdgeN - 1 do
      if (FEdges[i].Col = COL_SKETCH) or (FEdges[i].Col = COL_AXIS) then
        DrawEdge(FShaded.Canvas, View, FShaded.Width, FShaded.Height, FEdges[i]);
    DrawLabel(FShaded.Canvas, 'Shaded, ' + IntToStr(FTriN) + ' triangles');
    FRevealing := True;
    FRevealStart := GetTickCount64;
    if Turbo then FRevealMs := 4000 else FRevealMs := 1500;
    FRevealRows := 0;
    FTimer.Enabled := True;
  end
  else
  begin
    FRevealing := False;
    FTimer.Enabled := False;
    DrawScene(FBack.Canvas, View, FBack.Width, FBack.Height, FEdges, FEdgeN);
    if Docs[Slot].Count = 0 then DrawLabel(FBack.Canvas, 'Empty part. Sketch a rectangle (R) or a circle (C) to begin.')
    else DrawLabel(FBack.Canvas, IntToStr(FEdgeN) + ' edges');
  end;
  FView.Invalidate;
end;

procedure TPartWindow.TimerTick(Sender: TObject);
var
  t: Double;
  due: Integer;
  r: TRect;
begin
  if not FRevealing then begin FTimer.Enabled := False; Exit; end;
  t := (GetTickCount64 - FRevealStart) / FRevealMs;
  if t >= 1 then due := FBack.Height
  else due := Trunc(t * FBack.Height / BAND) * BAND;
  if due <= FRevealRows then Exit;
  r := Rect(0, FRevealRows, FBack.Width, due);
  FBack.Canvas.CopyRect(r, FShaded.Canvas, r);
  FRevealRows := due;
  FView.Invalidate;
  if due >= FBack.Height then
  begin
    FRevealing := False;
    FTimer.Enabled := False;
    if Turbo then
      SetStatus('Shaded at Turbo quality in ' + FmtN((GetTickCount64 - FRevealStart) / 1000, 1) +
        ' seconds. Every pixel was rendered twice, to be sure.')
    else
      SetStatus('Shaded in ' + FmtN((GetTickCount64 - FRevealStart) / 1000, 1) + ' seconds.');
  end
  else if Turbo then SetStatus('Rendering at Turbo quality... ' + IntToStr(100 * due div FBack.Height) + '%')
  else SetStatus('Rendering... ' + IntToStr(100 * due div FBack.Height) + '%');
end;

procedure TPartWindow.ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Assigned(OnActivatePart) then OnActivatePart(Self);
  if Button = mbRight then FDrag := 2 else FDrag := 1;      // orbit with the left button, pan with the right
  FDragX := X; FDragY := Y;
  FMoved := False;
  FFrames := 0;
  FFrameStart := GetTickCount64;
end;

procedure TPartWindow.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  el: Double;
begin
  if (FDrag <> 1) and (FDrag <> 2) then Exit;
  if (X = FDragX) and (Y = FDragY) then Exit;
  if FDrag = 1 then
  begin
    View.Yaw := View.Yaw + (X - FDragX) * 0.5;
    View.Pitch := View.Pitch + (Y - FDragY) * 0.5;
    if View.Pitch > 90 then View.Pitch := 90;
    if View.Pitch < -90 then View.Pitch := -90;
  end
  else
  begin
    View.PanX := View.PanX + X - FDragX;
    View.PanY := View.PanY + Y - FDragY;
  end;
  FDragX := X; FDragY := Y;
  FMoved := True;
  // Turbo caps orbit at 4 fps; the mouse keeps going, the picture catches up
  if GetTickCount64 - FLastDraw < Round(OrbitFrameInterval * 1000) then Exit;
  FLastDraw := GetTickCount64;
  Redraw;
  FView.Update;
  Inc(FFrames);
  el := (GetTickCount64 - FFrameStart) / 1000;
  if el > 0.5 then
  begin
    if Turbo then
    begin
      SetFps(IntToStr(Round(FFrames / el)) + ' fps (Turbo)');
      SetStatus('Orbit is limited to 4 fps while Turbo is on.');
    end
    else
      SetFps(IntToStr(Round(FFrames / el)) + ' fps');
    FFrames := 0;
    FFrameStart := GetTickCount64;
  end;
end;

procedure TPartWindow.ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  k: Integer;
begin
  k := FDrag;
  FDrag := 0;
  // the last position, in case Turbo skipped it; shaded again if it moved
  if ((k = 1) or (k = 2)) and (FMoved or not ViewShaded) then Redraw;
end;

procedure TPartWindow.ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if WheelDelta > 0 then ZoomBy(1.25) else ZoomBy(0.8);
  Handled := True;
end;

procedure TPartWindow.ZoomBy(k: Double);
begin
  View.Zoom := View.Zoom * k;
  View.PanX := View.PanX * k;
  View.PanY := View.PanY * k;
  Redraw;
end;

procedure TPartWindow.ViewIso;
begin
  ResetView(View);
  FitView(View, FBack.Width, FBack.Height, FEdges, FEdgeN);
  Redraw;
  SetStatus('Isometric view.');
end;

procedure TPartWindow.ZoomFit;
begin
  FitView(View, FBack.Width, FBack.Height, FEdges, FEdgeN);
  Redraw;
end;

procedure TPartWindow.Regen;
begin
  if not SolverConverges(RegenTries) then
  begin
    SetStatus('Regenerate: the solver did not converge (attempt ' + IntToStr(RegenTries) + ').');
    Exit;
  end;
  RefreshAll(False);
  SetStatus('Regenerated ' + IntToStr(Docs[Slot].Count) + ' features, ' + IntToStr(FEdgeN) + ' edges.');
end;

{ ---- the tree and the timeline ---- }

procedure TPartWindow.FillTree;
var
  root, origin, n: TTreeNode;
  nodes: array[1..MAX_FEATURES] of TTreeNode;
  i, j: Integer;
  used: array[0..MAX_FEATURES] of Boolean;

  function NodeText(k: Integer): string;
  begin
    Result := Docs[Slot].F[k].Name;
    if not RefOk(Docs[Slot], k) then Result := Result + ' (!)';
  end;

  function Uses_(k: Integer): Integer;
  begin
    Result := 0;
    with Docs[Slot] do
      if (F[k].Kind = FK_EXTRUDE) or (F[k].Kind = FK_REVOLVE) then
        if (F[k].Ref >= 1) and (F[k].Ref < k) and IsSketch(F[F[k].Ref].Kind) then Result := F[k].Ref;
  end;

begin
  FFilling := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    root := FTree.Items.Add(nil, Docs[Slot].Title);
    origin := FTree.Items.AddChild(root, 'Origin');
    FTree.Items.AddChild(origin, 'Front Plane (XZ)');
    FTree.Items.AddChild(origin, 'Top Plane (XY)');
    FTree.Items.AddChild(origin, 'Right Plane (YZ)');
    FillChar(used, SizeOf(used), 0);
    for i := 1 to Docs[Slot].Count do
    begin
      j := Uses_(i);
      if j > 0 then used[j] := True;
    end;
    for i := 1 to Docs[Slot].Count do
    begin
      nodes[i] := nil;
      if used[i] then Continue;
      // sketches hang under the feature that uses them, the way people expect
      n := FTree.Items.AddChild(root, NodeText(i));
      n.Data := Pointer(PtrInt(i));
      nodes[i] := n;
      j := Uses_(i);
      if j > 0 then
      begin
        nodes[j] := FTree.Items.AddChild(n, NodeText(j));
        nodes[j].Data := Pointer(PtrInt(j));
        n.Expanded := True;
      end;
    end;
    root.Expanded := True;
    if (Selected >= 1) and (Selected <= Docs[Slot].Count) and (nodes[Selected] <> nil) then
      FTree.Selected := nodes[Selected];
  finally
    FTree.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TPartWindow.FillTimeline;
var
  i: Integer;
  it: TListItem;
begin
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 1 to Docs[Slot].Count do
    begin
      it := FList.Items.Add;
      it.Caption := IntToStr(i);
      it.SubItems.Add(Docs[Slot].F[i].Name);
      if Docs[Slot].F[i].Kind = FK_FOREIGN then
      begin
        it.SubItems.Add(Docs[Slot].F[i].Info);
        it.SubItems.Add(Describe(Docs[Slot], i));
        it.SubItems.Add('Requires SolidCraft 2000');
      end
      else
      begin
        it.SubItems.Add(KindName(Docs[Slot].F[i].Kind));
        it.SubItems.Add(Describe(Docs[Slot], i));
        if RefOk(Docs[Slot], i) then it.SubItems.Add('OK') else it.SubItems.Add('Rebuild error');
      end;
    end;
    if (Selected >= 1) and (Selected <= FList.Items.Count) then
    begin
      FList.Selected := FList.Items[Selected - 1];
      FList.Items[Selected - 1].MakeVisible(False);
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TPartWindow.SelectFeature(i: Integer);
begin
  Selected := i;
  if i > 0 then SetStatus(FeatureName(Docs[Slot], i) + ': ' + Describe(Docs[Slot], i));
  FFilling := True;
  try
    if (i >= 1) and (i <= FList.Items.Count) then
    begin
      FList.Selected := FList.Items[i - 1];
      FList.Items[i - 1].MakeVisible(False);
    end;
  finally
    FFilling := False;
  end;
end;

procedure TPartWindow.TreeClick(Sender: TObject);
begin
  if FFilling then Exit;
  if (FTree.Selected <> nil) and (FTree.Selected.Data <> nil) then
    SelectFeature(PtrInt(FTree.Selected.Data))
  else
    Selected := 0;
end;

procedure TPartWindow.TreeDblClick(Sender: TObject);
begin
  TreeClick(Sender);
  if (Selected > 0) and Assigned(OnEditFeature) then OnEditFeature(Self);
end;

procedure TPartWindow.ListClick(Sender: TObject);
begin
  if FFilling then Exit;
  if FList.Selected <> nil then
  begin
    Selected := FList.Selected.Index + 1;
    SetStatus(FeatureName(Docs[Slot], Selected) + ': ' + Describe(Docs[Slot], Selected));
  end;
end;

procedure TPartWindow.ListSelect(Sender: TObject; Item: TListItem; Selected_: Boolean);
begin
  if Selected_ then ListClick(Sender);
end;

procedure TPartWindow.ListDblClick(Sender: TObject);
begin
  ListClick(Sender);
  if (Selected > 0) and Assigned(OnEditFeature) then OnEditFeature(Self);
end;

procedure TPartWindow.RefreshNames;
begin
  FCaption.Invalidate;
  FillTree;
end;

procedure TPartWindow.RefreshAll(AFit: Boolean);
begin
  if Selected > Docs[Slot].Count then Selected := 0;
  FCaption.Invalidate;
  FillTree;
  FillTimeline;
  FEdgeN := Regenerate(Docs[Slot], FEdges);
  FMeshOk := False;
  EnsureBitmaps;
  if AFit then FitView(View, FBack.Width, FBack.Height, FEdges, FEdgeN);
  Redraw;
end;

end.
