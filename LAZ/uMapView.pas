unit uMapView;

{ Tiled map and GPX point editing. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Types, Math, Controls, uFmx, uGpx, uTiles;

type
  TMouseMode = (mmNone, mmPan, mmPointPending, mmPointDrag);

  TMapView = class(TFmxControl)
  private
    FDoc: TGpxDoc;
    FTiles: TTileStore;
    FAttribution: string;
    FCX, FCY: Double;          // view centre, normalised mercator
    FZoom: Double;             // in steps of ZoomInc
    FSelSeg, FSelIdx: Integer;
    FVisSeg: Integer;          // -1 = all segments
    FHoverSeg, FHoverIdx: Integer;
    FMode: TMouseMode;
    FDown: TPointF;
    FDownCX, FDownCY: Double;
    FGrab: TPointF;
    FMoved: Boolean;
    FDragBefore: TGpxPoint;
    FMouse: TPointF;
    FMouseInside: Boolean;
    FWheelAcc: Integer;
    FPath: TPathData;
    FScr: TArray<TPointF>;
    FOnChange: TNotifyEvent;
    FOnCursorMove: TNotifyEvent;
    function WorldSize: Double;
    function ToScreen(AMX, AMY: Double): TPointF;
    procedure ToMerc(X, Y: Single; out AMX, AMY: Double);
    function SegVisible(ASeg: Integer): Boolean;
    function HitPoint(X, Y: Single; out ASeg, AIdx: Integer): Boolean;
    procedure ClampView;
    procedure DoChange;
    procedure TileReady(Sender: TObject);
    procedure SetDoc(const Value: TGpxDoc);
    procedure SetVisSeg(const Value: Integer);
    procedure SetSelection(ASeg, AIdx: Integer);
    procedure EnsureVisible(ASeg, AIdx: Integer);
    procedure AfterHistory(AOk: Boolean; ASeg, AIdx: Integer);
    procedure ZoomAt(ADelta: Double; AX, AY: Single);
    procedure StepZoom(ADir: Integer);
    function GetMaxZoom: Integer;
    // painting
    procedure SetStroke(AColor: TAlphaColor; AThickness: Single);
    procedure SetFill(AColor: TAlphaColor);
    procedure ProjectSegment(ASeg: TGpxSegment);
    procedure BuildPath(ACount: Integer);
    procedure PaintTiles;
    procedure PaintTrack;
    procedure PaintFocus;
    procedure PaintOverlay;
    procedure DrawHandle(const P: TPointF; ARadius, AStroke, AOpacity: Single);
    procedure DrawEnd(const P: TPointF; AStart: Boolean; AOpacity: Single);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Configure(const AUrlTemplate, AApiKey, AAttribution: string; AMaxZoom: Integer);

    function HasSelection: Boolean;
    procedure ClearSelection;
    { Selects a point and brings it into view (used by the graph). }
    procedure SelectPoint(ASeg, AIdx: Integer);
    { Esc: cancels a drag in progress, otherwise clears the selection. }
    procedure Escape;
    procedure DeleteSelected;
    procedure InsertAfterSelected;
    procedure SelectStep(ADelta: Integer);
    procedure SelectEnd(ALast: Boolean);
    { Moves the selected point by whole screen pixels. }
    procedure Nudge(ADX, ADY: Integer);
    procedure Undo;
    procedure Redo;

    procedure ZoomIn;
    procedure ZoomOut;
    procedure ZoomToTrack;
    procedure PanBy(ADX, ADY: Single);
    function CursorPos(out ALat, ALon: Double): Boolean;
    function TileError: string;

    property Doc: TGpxDoc read FDoc write SetDoc;
    property SelSeg: Integer read FSelSeg;
    property SelIdx: Integer read FSelIdx;
    property VisibleSeg: Integer read FVisSeg write SetVisSeg;
    property Zoom: Double read FZoom;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCursorMove: TNotifyEvent read FOnCursorMove write FOnCursorMove;
  end;

implementation

const
  MinZoom = 2;
  ZoomInc = 0.5;             // one zoom step, in tile levels
  OverZoom = 3;              // levels beyond the tile server's maximum (tiles get stretched)
  FocusSpan = 3;             // neighbours highlighted on each side of the selection
  HitRadius = 10.0;
  DragThreshold = 3.0;
  HandleSpacing = 9.0;       // minimum screen distance between two drawn handles

  ColTrack = $FF14308A;      // dark blue
  ColCasing = $FFFFFFFF;
  ColStart = $FF1E9E54;
  ColEnd = $FFD93025;
  ColInk = $FF2B2F36;
  ColBackground = $FFE6E8EC;
  MutedOpacity = 0.42;

  FocusOpacity: array[0..FocusSpan] of Single = (1, 1, 0.82, 0.62);
  FocusRadius: array[0..FocusSpan] of Single = (6.5, 5, 4.5, 4);

function Around(const P: TPointF; R: Single): TRectF; inline;
begin
  Result := TRectF.Create(P.X - R, P.Y - R, P.X + R, P.Y + R);
end;

{ TMapView }

constructor TMapView.Create(AOwner: TComponent);
begin
  inherited;
  TabStop := True;
  FPath := TPathData.Create;
  FCX := 0.5;
  FCY := 0.38;
  FZoom := MinZoom;
  FSelSeg := -1;
  FSelIdx := -1;
  FVisSeg := -1;
  FHoverSeg := -1;
  FHoverIdx := -1;
end;

destructor TMapView.Destroy;
begin
  FTiles.Free;
  FPath.Free;
  inherited;
end;

procedure TMapView.Configure(const AUrlTemplate, AApiKey, AAttribution: string; AMaxZoom: Integer);
begin
  FreeAndNil(FTiles);
  FAttribution := AAttribution;
  FTiles := TTileStore.Create(AUrlTemplate, AApiKey, EnsureRange(AMaxZoom, 1, 22));
  FTiles.OnTileReady := TileReady;
  Repaint;
end;

procedure TMapView.TileReady(Sender: TObject);
begin
  Repaint;
end;

function TMapView.TileError: string;
begin
  if FTiles <> nil then
    Result := FTiles.LastError
  else
    Result := '';
end;

function TMapView.GetMaxZoom: Integer;
begin
  if FTiles <> nil then
    Result := Min(22, FTiles.MaxZoom + OverZoom)
  else
    Result := 19;
end;

function TMapView.WorldSize: Double;
begin
  Result := 256.0 * Power(2, FZoom);
end;

function TMapView.ToScreen(AMX, AMY: Double): TPointF;
var
  WS: Double;
begin
  WS := WorldSize;
  Result.X := (AMX - FCX) * WS + Width / 2;
  Result.Y := (AMY - FCY) * WS + Height / 2;
end;

procedure TMapView.ToMerc(X, Y: Single; out AMX, AMY: Double);
var
  WS: Double;
begin
  WS := WorldSize;
  AMX := FCX + (X - Width / 2) / WS;
  AMY := FCY + (Y - Height / 2) / WS;
end;

function TMapView.SegVisible(ASeg: Integer): Boolean;
begin
  Result := (FVisSeg < 0) or (FVisSeg = ASeg);
end;

procedure TMapView.ClampView;
begin
  FCX := EnsureRange(FCX, 0, 1);
  FCY := EnsureRange(FCY, 0, 1);
end;

procedure TMapView.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TMapView.HasSelection: Boolean;
begin
  Result := (FDoc <> nil) and (FSelSeg >= 0) and (FSelSeg < FDoc.SegCount) and
    (FSelIdx >= 0) and (FSelIdx < FDoc[FSelSeg].Count);
end;

procedure TMapView.SetDoc(const Value: TGpxDoc);
begin
  FDoc := Value;
  FMode := mmNone;
  FSelSeg := -1;
  FSelIdx := -1;
  FHoverSeg := -1;
  FHoverIdx := -1;
  FVisSeg := -1;
  if FDoc <> nil then
    ZoomToTrack
  else
    Repaint;
end;

procedure TMapView.SetVisSeg(const Value: Integer);
begin
  if FVisSeg = Value then
    Exit;
  FVisSeg := Value;
  FHoverSeg := -1;
  FHoverIdx := -1;
  if HasSelection and not SegVisible(FSelSeg) then
  begin
    FSelSeg := -1;
    FSelIdx := -1;
  end;
  Repaint;
  DoChange;
end;

procedure TMapView.SetSelection(ASeg, AIdx: Integer);
begin
  if (ASeg = FSelSeg) and (AIdx = FSelIdx) then
    Exit;
  FSelSeg := ASeg;
  FSelIdx := AIdx;
  Repaint;
  DoChange;
end;

procedure TMapView.ClearSelection;
begin
  SetSelection(-1, -1);
end;

procedure TMapView.SelectPoint(ASeg, AIdx: Integer);
begin
  if (FDoc = nil) or (FMode <> mmNone) or (ASeg < 0) or (ASeg >= FDoc.SegCount) or
    (AIdx < 0) or (AIdx >= FDoc[ASeg].Count) or not SegVisible(ASeg) then
    Exit;
  if (ASeg = FSelSeg) and (AIdx = FSelIdx) then
    Exit;
  SetSelection(ASeg, AIdx);
  EnsureVisible(ASeg, AIdx);
end;

procedure TMapView.EnsureVisible(ASeg, AIdx: Integer);
var
  P: PGpxPoint;
  S: TPointF;
  M: Single;
begin
  P := FDoc[ASeg][AIdx];
  S := ToScreen(P.MX, P.MY);
  M := Min(48, Min(Width, Height) / 4);
  if (S.X < M) or (S.Y < M) or (S.X > Width - M) or (S.Y > Height - M) then
  begin
    FCX := P.MX;
    FCY := P.MY;
    ClampView;
  end;
  Repaint;
end;

function TMapView.HitPoint(X, Y: Single; out ASeg, AIdx: Integer): Boolean;
var
  WS, OX, OY, DX, DY, D, Best: Double;
  S, I: Integer;
  Seg: TGpxSegment;
  P: PGpxPoint;
begin
  ASeg := -1;
  AIdx := -1;
  if FDoc = nil then
    Exit(False);
  WS := WorldSize;
  OX := Width / 2 - FCX * WS;
  OY := Height / 2 - FCY * WS;
  Best := HitRadius * HitRadius;

  // the highlighted points are drawn on top, so they also win the click
  if HasSelection then
  begin
    Seg := FDoc[FSelSeg];
    for I := Max(0, FSelIdx - FocusSpan) to Min(Seg.Count - 1, FSelIdx + FocusSpan) do
    begin
      P := Seg[I];
      DX := P.MX * WS + OX - X;
      DY := P.MY * WS + OY - Y;
      D := DX * DX + DY * DY;
      if (D < Best) or ((D = Best) and (I = FSelIdx)) then
      begin
        Best := D;
        ASeg := FSelSeg;
        AIdx := I;
      end;
    end;
    if AIdx >= 0 then
      Exit(True);
  end;

  for S := 0 to FDoc.SegCount - 1 do
    if SegVisible(S) then
    begin
      Seg := FDoc[S];
      for I := 0 to Seg.Count - 1 do
      begin
        P := Seg[I];
        DX := P.MX * WS + OX - X;
        if Abs(DX) > HitRadius then
          Continue;
        DY := P.MY * WS + OY - Y;
        D := DX * DX + DY * DY;
        if D < Best then
        begin
          Best := D;
          ASeg := S;
          AIdx := I;
        end;
      end;
    end;
  Result := AIdx >= 0;
end;

{ ---- editing --------------------------------------------------------------- }

procedure TMapView.Escape;
begin
  if FMode = mmPointDrag then
  begin
    FDoc.RestorePoint(FSelSeg, FSelIdx, FDragBefore);
    FMode := mmNone;
    Repaint;
    DoChange;
  end
  else
  begin
    FMode := mmNone;
    ClearSelection;
  end;
end;

procedure TMapView.DeleteSelected;
var
  N: Integer;
begin
  if not HasSelection or (FMode <> mmNone) then
    Exit;
  FDoc.DeletePoint(FSelSeg, FSelIdx);
  N := FDoc[FSelSeg].Count;
  if N = 0 then
  begin
    FSelSeg := -1;
    FSelIdx := -1;
  end
  else
    FSelIdx := Min(FSelIdx, N - 1);
  FHoverSeg := -1;
  FHoverIdx := -1;
  Repaint;
  DoChange;
end;

procedure TMapView.InsertAfterSelected;
const
  Offset = 26.0;   // screen pixels between the selected and the new point
var
  Seg: TGpxSegment;
  A, B: PGpxPoint;
  WS, DX, DY, D, T, NX, NY: Double;
begin
  if not HasSelection or (FMode <> mmNone) then
    Exit;
  Seg := FDoc[FSelSeg];
  A := Seg[FSelIdx];
  WS := WorldSize;
  T := 0;
  NX := A.MX + Offset / WS;
  NY := A.MY;

  if FSelIdx < Seg.Count - 1 then
  begin
    // towards the next point, but never past the half-way mark
    B := Seg[FSelIdx + 1];
    DX := (B.MX - A.MX) * WS;
    DY := (B.MY - A.MY) * WS;
    D := Sqrt(DX * DX + DY * DY);
    if D > 0.01 then
    begin
      T := Min(0.5, Offset / D);
      NX := A.MX + (B.MX - A.MX) * T;
      NY := A.MY + (B.MY - A.MY) * T;
    end;
  end
  else if FSelIdx > 0 then
  begin
    // last point: continue in the direction of travel
    B := Seg[FSelIdx - 1];
    DX := (A.MX - B.MX) * WS;
    DY := (A.MY - B.MY) * WS;
    D := Sqrt(DX * DX + DY * DY);
    if D > 0.01 then
    begin
      NX := A.MX + DX / D * Offset / WS;
      NY := A.MY + DY / D * Offset / WS;
    end;
  end;

  FDoc.InsertPointAfter(FSelSeg, FSelIdx, NX, NY, T);
  Inc(FSelIdx);
  FHoverSeg := -1;
  FHoverIdx := -1;
  EnsureVisible(FSelSeg, FSelIdx);
  DoChange;
end;

procedure TMapView.SelectStep(ADelta: Integer);
var
  S, I: Integer;
begin
  if not HasSelection or (FMode <> mmNone) then
    Exit;
  S := FSelSeg;
  I := FSelIdx + ADelta;
  if (I < 0) or (I >= FDoc[S].Count) then
  begin
    if FVisSeg >= 0 then
      Exit;
    // step across to the neighbouring segment
    repeat
      Inc(S, Sign(ADelta));
    until (S < 0) or (S >= FDoc.SegCount) or (FDoc[S].Count > 0);
    if (S < 0) or (S >= FDoc.SegCount) then
      Exit;
    if ADelta > 0 then
      I := 0
    else
      I := FDoc[S].Count - 1;
  end;
  SetSelection(S, I);
  EnsureVisible(S, I);
end;

{ First / last point of what is shown. }
procedure TMapView.SelectEnd(ALast: Boolean);
var
  S, I: Integer;
begin
  if (FDoc = nil) or (FMode <> mmNone) then
    Exit;
  if ALast then
  begin
    S := FDoc.SegCount - 1;
    while (S >= 0) and not (SegVisible(S) and (FDoc[S].Count > 0)) do
      Dec(S);
  end
  else
  begin
    S := 0;
    while (S < FDoc.SegCount) and not (SegVisible(S) and (FDoc[S].Count > 0)) do
      Inc(S);
  end;
  if (S < 0) or (S >= FDoc.SegCount) then
    Exit;
  if ALast then
    I := FDoc[S].Count - 1
  else
    I := 0;
  SetSelection(S, I);
  EnsureVisible(S, I);
end;

procedure TMapView.Nudge(ADX, ADY: Integer);
var
  Before: TGpxPoint;
  WS: Double;
begin
  if not HasSelection or (FMode <> mmNone) then
    Exit;
  WS := WorldSize;
  Before := FDoc[FSelSeg][FSelIdx]^;
  FDoc.SetPos(FSelSeg, FSelIdx, Before.MX + ADX / WS, Before.MY + ADY / WS);
  FDoc.CommitMove(FSelSeg, FSelIdx, Before, True);
  EnsureVisible(FSelSeg, FSelIdx);
  DoChange;
end;

procedure TMapView.AfterHistory(AOk: Boolean; ASeg, AIdx: Integer);
begin
  if not AOk then
    Exit;
  FHoverSeg := -1;
  FHoverIdx := -1;
  if (ASeg >= 0) and not SegVisible(ASeg) then
    FVisSeg := -1;
  if ASeg < 0 then
  begin
    // a step that moved no points (normalize): the selection stays as it is
    if not HasSelection then
    begin
      FSelSeg := -1;
      FSelIdx := -1;
    end;
  end
  else if (AIdx >= 0) and (AIdx < FDoc[ASeg].Count) then
  begin
    FSelSeg := ASeg;
    FSelIdx := AIdx;
    EnsureVisible(ASeg, AIdx);
  end
  else
  begin
    FSelSeg := -1;
    FSelIdx := -1;
  end;
  Repaint;
  DoChange;
end;

procedure TMapView.Undo;
var
  S, I: Integer;
begin
  if (FDoc = nil) or (FMode <> mmNone) then
    Exit;
  AfterHistory(FDoc.Undo(S, I), S, I);
end;

procedure TMapView.Redo;
var
  S, I: Integer;
begin
  if (FDoc = nil) or (FMode <> mmNone) then
    Exit;
  AfterHistory(FDoc.Redo(S, I), S, I);
end;

{ ---- view ------------------------------------------------------------------ }

procedure TMapView.ZoomAt(ADelta: Double; AX, AY: Single);
var
  MX, MY, WS: Double;
  NewZoom: Double;
begin
  NewZoom := Round(EnsureRange(FZoom + ADelta, MinZoom, GetMaxZoom) / ZoomInc) * ZoomInc;
  if SameValue(NewZoom, FZoom, 1e-6) then
    Exit;
  // keep the map position under (AX, AY) where it is
  ToMerc(AX, AY, MX, MY);
  FZoom := NewZoom;
  WS := WorldSize;
  FCX := MX - (AX - Width / 2) / WS;
  FCY := MY - (AY - Height / 2) / WS;
  ClampView;
  Repaint;
  DoChange;
end;

{ Anchor zoom at the selected point or the view centre. Centre an
  off-screen selection first. }
procedure TMapView.StepZoom(ADir: Integer);
var
  P: TPointF;
  Pt: PGpxPoint;
begin
  P := PointF(Width / 2, Height / 2);
  if HasSelection then
  begin
    Pt := FDoc[FSelSeg][FSelIdx];
    if LocalRect.Contains(ToScreen(Pt.MX, Pt.MY)) then
      P := ToScreen(Pt.MX, Pt.MY)
    else
    begin
      FCX := Pt.MX;
      FCY := Pt.MY;
      ClampView;
      Repaint;
    end;
  end;
  ZoomAt(ADir * ZoomInc, P.X, P.Y);
end;

procedure TMapView.ZoomIn;
begin
  StepZoom(1);
end;

procedure TMapView.ZoomOut;
begin
  StepZoom(-1);
end;

procedure TMapView.PanBy(ADX, ADY: Single);
var
  WS: Double;
begin
  WS := WorldSize;
  FCX := FCX + ADX / WS;
  FCY := FCY + ADY / WS;
  ClampView;
  Repaint;
end;

procedure TMapView.ZoomToTrack;
var
  S, I: Integer;
  Seg: TGpxSegment;
  P: PGpxPoint;
  X0, Y0, X1, Y1, AW, AH, ZX, ZY, Z: Double;
  Any: Boolean;
begin
  if FDoc = nil then
    Exit;
  Any := False;
  X0 := 1; Y0 := 1; X1 := 0; Y1 := 0;
  for S := 0 to FDoc.SegCount - 1 do
    if SegVisible(S) then
    begin
      Seg := FDoc[S];
      for I := 0 to Seg.Count - 1 do
      begin
        P := Seg[I];
        X0 := Min(X0, P.MX); X1 := Max(X1, P.MX);
        Y0 := Min(Y0, P.MY); Y1 := Max(Y1, P.MY);
        Any := True;
      end;
    end;
  if not Any then
  begin
    Repaint;
    Exit;
  end;

  AW := Max(64, Width - 120);
  AH := Max(64, Height - 120);
  ZX := 99;
  ZY := 99;
  if X1 > X0 then ZX := Log2(AW / ((X1 - X0) * 256));
  if Y1 > Y0 then ZY := Log2(AH / ((Y1 - Y0) * 256));
  Z := Floor(Min(ZX, ZY) / ZoomInc) * ZoomInc;
  if FTiles <> nil then
    Z := Min(Z, Min(FTiles.MaxZoom, 18))
  else
    Z := Min(Z, 18);
  FZoom := Max(MinZoom, Z);
  FCX := (X0 + X1) / 2;
  FCY := (Y0 + Y1) / 2;
  ClampView;
  Repaint;
  DoChange;
end;

function TMapView.CursorPos(out ALat, ALon: Double): Boolean;
var
  MX, MY: Double;
begin
  Result := FMouseInside;
  if not Result then
    Exit;
  ToMerc(FMouse.X, FMouse.Y, MX, MY);
  ALon := MXToLon(MX);
  ALat := MYToLat(EnsureRange(MY, 0, 1));
  Result := (MX >= 0) and (MX <= 1);
end;

{ ---- mouse ----------------------------------------------------------------- }

procedure TMapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  S, I: Integer;
  P: PGpxPoint;
  Scr: TPointF;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  if ssDouble in Shift then
  begin
    // double click: one full level in, about the spot that was clicked
    FMode := mmNone;
    ZoomAt(1, X, Y);
    Exit;
  end;
  FDown := PointF(X, Y);
  FMoved := False;
  if HitPoint(X, Y, S, I) then
  begin
    SetSelection(S, I);
    P := FDoc[S][I];
    Scr := ToScreen(P.MX, P.MY);
    FGrab := PointF(Scr.X - X, Scr.Y - Y);
    FMode := mmPointPending;
  end
  else
  begin
    FMode := mmPan;
    FDownCX := FCX;
    FDownCY := FCY;
  end;
end;

procedure TMapView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  WS, MX, MY: Double;
  S, I: Integer;
  Far: Boolean;
begin
  inherited;
  FMouse := PointF(X, Y);
  FMouseInside := True;
  Far := (Abs(X - FDown.X) > DragThreshold) or (Abs(Y - FDown.Y) > DragThreshold);

  if (FMode = mmPointPending) and Far and HasSelection then
  begin
    FDragBefore := FDoc[FSelSeg][FSelIdx]^;
    FMode := mmPointDrag;
  end;

  case FMode of
    mmPan:
      if FMoved or Far then
      begin
        FMoved := True;
        WS := WorldSize;
        FCX := FDownCX - (X - FDown.X) / WS;
        FCY := FDownCY - (Y - FDown.Y) / WS;
        ClampView;
        Repaint;
      end;
    mmPointDrag:
      begin
        ToMerc(X + FGrab.X, Y + FGrab.Y, MX, MY);
        FDoc.SetPos(FSelSeg, FSelIdx, MX, MY);
        Repaint;
        DoChange;
      end;
    mmNone:
      begin
        HitPoint(X, Y, S, I);
        if (S <> FHoverSeg) or (I <> FHoverIdx) then
        begin
          FHoverSeg := S;
          FHoverIdx := I;
          if I >= 0 then
            Cursor := crHandPoint
          else
            Cursor := crDefault;
          Repaint;
        end;
      end;
  end;

  if Assigned(FOnCursorMove) then
    FOnCursorMove(Self);
end;

procedure TMapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Mode: TMouseMode;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  Mode := FMode;
  FMode := mmNone;
  case Mode of
    mmPointDrag:
      if HasSelection then
      begin
        FDoc.CommitMove(FSelSeg, FSelIdx, FDragBefore, False);
        Repaint;
        DoChange;
      end;
    mmPan:
      if not FMoved then
        ClearSelection;   // plain click on the map
  end;
end;

procedure TMapView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
var
  Steps: Integer;
begin
  inherited;
  Handled := True;
  if FMode <> mmNone then
    Exit;
  // precision touchpads send many small deltas; act on whole notches only
  if (FWheelAcc > 0) <> (WheelDelta > 0) then
    FWheelAcc := 0;
  Inc(FWheelAcc, WheelDelta);
  Steps := FWheelAcc div 120;
  if Steps = 0 then
    Exit;
  Dec(FWheelAcc, Steps * 120);
  if FMouseInside then
    ZoomAt(EnsureRange(Steps, -4, 4) * ZoomInc, FMouse.X, FMouse.Y)
  else
    ZoomAt(EnsureRange(Steps, -4, 4) * ZoomInc, Width / 2, Height / 2);
end;

procedure TMapView.DoMouseLeave;
begin
  inherited;
  FMouseInside := False;
  if FHoverIdx >= 0 then
  begin
    FHoverSeg := -1;
    FHoverIdx := -1;
    Repaint;
  end;
  if Assigned(FOnCursorMove) then
    FOnCursorMove(Self);
end;

{ ---- painting -------------------------------------------------------------- }

procedure TMapView.SetStroke(AColor: TAlphaColor; AThickness: Single);
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := AColor;
  Canvas.Stroke.Thickness := AThickness;
  Canvas.Stroke.Cap := TStrokeCap.Round;
  Canvas.Stroke.Join := TStrokeJoin.Round;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
end;

procedure TMapView.SetFill(AColor: TAlphaColor);
begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := AColor;
end;

procedure TMapView.Paint;
var
  State: TCanvasSaveState;
begin
  State := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(LocalRect);
    SetFill(ColBackground);
    Canvas.FillRect(LocalRect, 0, 0, AllCorners, 1);
    PaintTiles;
    if FDoc <> nil then
    begin
      PaintTrack;
      if HasSelection then
        PaintFocus;
    end;
    PaintOverlay;
  finally
    Canvas.RestoreState(State);
  end;
end;

procedure TMapView.PaintTiles;
var
  L, N, TX, TY, X0, X1, Y0, Y1, D, Mask: Integer;
  TS, WS, OX, OY, Scale, Sub: Double;
  Bmp: TBitmap;
  Dst, Src: TRectF;

  function Snap(V: Double): Single;
  begin
    Result := Round(V * Scale) / Scale;
  end;

begin
  if FTiles = nil then
    Exit;
  Scale := SceneScale;
  // in-between zooms use the next finer level, scaled down: stays sharp
  L := Min(Floor(FZoom + 0.5), FTiles.MaxZoom);
  TS := 256.0 * Power(2, FZoom - L);
  WS := WorldSize;
  OX := Width / 2 - FCX * WS;
  OY := Height / 2 - FCY * WS;
  N := 1 shl L;
  X0 := Max(0, Floor(-OX / TS));
  Y0 := Max(0, Floor(-OY / TS));
  X1 := Min(N - 1, Floor((Width - OX) / TS));
  Y1 := Min(N - 1, Floor((Height - OY) / TS));

  FTiles.BeginFrame(L);
  for TY := Y0 to Y1 do
    for TX := X0 to X1 do
    begin
      // edges snapped to device pixels so neighbouring tiles join without seams
      Dst := TRectF.Create(Snap(OX + TX * TS), Snap(OY + TY * TS),
        Snap(OX + (TX + 1) * TS), Snap(OY + (TY + 1) * TS));
      Bmp := FTiles.GetTile(L, TX, TY);
      if Bmp <> nil then
        Canvas.DrawBitmap(Bmp, TRectF.Create(0, 0, Bmp.Width, Bmp.Height), Dst, 1, False)
      else
        // not there yet: show the matching part of a coarser tile meanwhile
        for D := 1 to Min(L, 6) do
        begin
          Bmp := FTiles.PeekTile(L - D, TX shr D, TY shr D);
          if Bmp <> nil then
          begin
            Mask := (1 shl D) - 1;
            Sub := Bmp.Width / (1 shl D);
            Src := TRectF.Create((TX and Mask) * Sub, (TY and Mask) * Sub,
              ((TX and Mask) + 1) * Sub, ((TY and Mask) + 1) * Sub);
            Canvas.DrawBitmap(Bmp, Src, Dst, 1, False);
            Break;
          end;
        end;
    end;
end;

procedure TMapView.ProjectSegment(ASeg: TGpxSegment);
var
  I, N: Integer;
  WS, OX, OY: Double;
  P: PGpxPoint;
begin
  N := ASeg.Count;
  if Length(FScr) < N then
    SetLength(FScr, N + N div 4 + 16);
  WS := WorldSize;
  OX := Width / 2 - FCX * WS;
  OY := Height / 2 - FCY * WS;
  for I := 0 to N - 1 do
  begin
    P := ASeg[I];
    FScr[I].X := P.MX * WS + OX;
    FScr[I].Y := P.MY * WS + OY;
  end;
end;

{ Polyline of FScr[0..ACount-1], without the parts that are off screen and
  without vertices that fall onto the same pixel. }
procedure TMapView.BuildPath(ACount: Integer);
const
  Pad = 24;
var
  I: Integer;
  Last, P: TPointF;
  PenDown: Boolean;
  W, H: Single;
begin
  FPath.Clear;
  if ACount < 2 then
    Exit;
  W := Width + Pad;
  H := Height + Pad;
  Last := FScr[0];
  PenDown := False;
  for I := 1 to ACount - 1 do
  begin
    P := FScr[I];
    if (I < ACount - 1) and (Abs(P.X - Last.X) < 0.75) and (Abs(P.Y - Last.Y) < 0.75) then
      Continue;
    if ((P.X < -Pad) and (Last.X < -Pad)) or ((P.X > W) and (Last.X > W)) or
      ((P.Y < -Pad) and (Last.Y < -Pad)) or ((P.Y > H) and (Last.Y > H)) then
      PenDown := False
    else
    begin
      if not PenDown then
        FPath.MoveTo(Last);
      FPath.LineTo(P);
      PenDown := True;
    end;
    Last := P;
  end;
end;

procedure TMapView.DrawHandle(const P: TPointF; ARadius, AStroke, AOpacity: Single);
var
  R: TRectF;
begin
  R := Around(P, ARadius);
  SetFill(ColCasing);
  Canvas.FillEllipse(R, AOpacity);
  SetStroke(ColTrack, AStroke);
  Canvas.DrawEllipse(R, AOpacity);
end;

{ First point of a segment = green dot, last = red dot.  The red one is the
  smaller of the two, so a track that ends where it began shows both. }
procedure TMapView.DrawEnd(const P: TPointF; AStart: Boolean; AOpacity: Single);
var
  R: Single;
begin
  if AStart then
    R := 6
  else
    R := 4.5;
  SetFill(ColCasing);
  Canvas.FillEllipse(Around(P, R + 1.75), AOpacity);
  if AStart then
    SetFill(ColStart)
  else
    SetFill(ColEnd);
  Canvas.FillEllipse(Around(P, R), AOpacity);
end;

procedure TMapView.PaintTrack;
var
  S, I, N: Integer;
  Seg: TGpxSegment;
  Op, PinOp: Single;
  P, LastH, PStart, PEnd: TPointF;
  DX, DY: Single;
  View: TRectF;
begin
  if HasSelection then
    Op := MutedOpacity
  else
    Op := 1;
  PinOp := Min(1, Op + 0.4);
  View := LocalRect;
  View.Inflate(8, 8);

  for S := 0 to FDoc.SegCount - 1 do
  begin
    if not SegVisible(S) then
      Continue;
    Seg := FDoc[S];
    N := Seg.Count;
    if N = 0 then
      Continue;
    ProjectSegment(Seg);
    PStart := FScr[0];
    PEnd := FScr[N - 1];

    BuildPath(N);
    if not FPath.IsEmpty then
    begin
      SetStroke(ColCasing, 5.5);
      Canvas.DrawPath(FPath, Op * 0.85);
      SetStroke(ColTrack, 2.75);
      Canvas.DrawPath(FPath, Op);
    end;

    // handles; thinned out while they would overlap anyway
    LastH := PointF(-1e6, -1e6);
    for I := 0 to N - 1 do
    begin
      P := FScr[I];
      if not View.Contains(P) then
        Continue;
      DX := P.X - LastH.X;
      DY := P.Y - LastH.Y;
      if (DX * DX + DY * DY < HandleSpacing * HandleSpacing) and (I > 0) and (I < N - 1) then
        Continue;
      DrawHandle(P, 3.25, 1.5, Op);
      LastH := P;
    end;

    if View.Contains(PStart) then
      DrawEnd(PStart, True, PinOp);
    if (N > 1) and View.Contains(PEnd) then
      DrawEnd(PEnd, False, PinOp);
  end;

  if (FHoverIdx >= 0) and (FHoverSeg >= 0) and (FHoverSeg < FDoc.SegCount) and
    (FHoverIdx < FDoc[FHoverSeg].Count) and
    not ((FHoverSeg = FSelSeg) and (FHoverIdx = FSelIdx)) then
  begin
    P := ToScreen(FDoc[FHoverSeg][FHoverIdx].MX, FDoc[FHoverSeg][FHoverIdx].MY);
    DrawHandle(P, 5, 2, 1);
  end;
end;

{ The selected point and its neighbours, drawn last so nothing covers them. }
procedure TMapView.PaintFocus;
var
  Seg: TGpxSegment;
  D, Side, A, B, N: Integer;
  PA, PB, P: TPointF;

  function Pt(AIndex: Integer): TPointF;
  begin
    Result := ToScreen(Seg[AIndex].MX, Seg[AIndex].MY);
  end;

  procedure Handle(AIndex, ADist: Integer);
  begin
    if AIndex = 0 then
      DrawEnd(Pt(AIndex), True, FocusOpacity[ADist])
    else if AIndex = N - 1 then
      DrawEnd(Pt(AIndex), False, FocusOpacity[ADist])
    else
      DrawHandle(Pt(AIndex), FocusRadius[ADist], 2, FocusOpacity[ADist]);
  end;

begin
  Seg := FDoc[FSelSeg];
  N := Seg.Count;

  for D := FocusSpan downto 1 do
    for Side := 0 to 1 do
    begin
      if Side = 0 then
      begin
        A := FSelIdx - D + 1;
        B := FSelIdx - D;
      end
      else
      begin
        A := FSelIdx + D - 1;
        B := FSelIdx + D;
      end;
      if (B < 0) or (B >= N) then
        Continue;
      PA := Pt(A);
      PB := Pt(B);
      SetStroke(ColCasing, 7);
      Canvas.DrawLine(PA, PB, FocusOpacity[D]);
      SetStroke(ColTrack, 3.5);
      Canvas.DrawLine(PA, PB, FocusOpacity[D]);
    end;

  for D := FocusSpan downto 1 do
  begin
    if FSelIdx - D >= 0 then
      Handle(FSelIdx - D, D);
    if FSelIdx + D < N then
      Handle(FSelIdx + D, D);
  end;

  // the selected point keeps its start / end colour inside the selection ring
  P := Pt(FSelIdx);
  SetFill(ColTrack);
  Canvas.FillEllipse(Around(P, 13), 0.16);
  Canvas.FillEllipse(Around(P, 9.5), 1);
  SetFill(ColCasing);
  Canvas.FillEllipse(Around(P, 7.5), 1);
  if FSelIdx = 0 then
    SetFill(ColStart)
  else if FSelIdx = N - 1 then
    SetFill(ColEnd)
  else
    SetFill(ColTrack);
  Canvas.FillEllipse(Around(P, 5.5), 1);
end;

procedure TMapView.PaintOverlay;
var
  R: TRectF;
  W: Single;
  Msg: string;
begin
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Style := [];

  if FDoc = nil then
  begin
    Msg := 'Open a GPX file, or drop one here';
    Canvas.Font.Size := 15;
    W := Canvas.TextWidth(Msg) + 56;
    R := TRectF.Create(0, 0, W, 54);
    R.Offset((Width - W) / 2, (Height - 54) / 2);
    SetFill($FF000000);
    Canvas.FillRect(TRectF.Create(R.Left, R.Top + 2, R.Right, R.Bottom + 3), 12, 12, AllCorners, 0.10);
    SetFill(ColCasing);
    Canvas.FillRect(R, 12, 12, AllCorners, 0.96);
    SetFill(ColInk);
    Canvas.FillText(R, Msg, False, 1, [], TTextAlign.Center, TTextAlign.Center);
  end;

  if FAttribution <> '' then
  begin
    Canvas.Font.Size := 11;
    W := Canvas.TextWidth(FAttribution) + 12;
    R := TRectF.Create(Width - W - 4, Height - 22, Width - 4, Height - 4);
    SetFill(ColCasing);
    Canvas.FillRect(R, 4, 4, AllCorners, 0.8);
    SetFill(ColInk);
    Canvas.FillText(R, FAttribution, False, 0.9, [], TTextAlign.Center, TTextAlign.Center);
  end;
end;

end.
