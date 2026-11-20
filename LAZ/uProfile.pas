unit uProfile;

{ Elevation / speed profile of the track: elevation on the left axis, speed on
  the right, against distance or time since the start.  Pure FMX canvas
  drawing, like the map. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Types, Math, Controls, uFmx, uGpx;

type
  TUnitSystem = (usImperial, usMetric, usAviation, usMarine);
  TProfileX = (pxDistance, pxTime);

  TUnitInfo = record
    Key: string;          // name in the settings file
    EleName, SpeedName, DistName: string;
    EleFactor: Double;    // metres -> unit
    SpeedFactor: Double;  // m/s -> unit
    DistFactor: Double;   // metres -> unit
  end;

const
  UnitInfo: array[TUnitSystem] of TUnitInfo = (
    (Key: 'imperial'; EleName: 'ft'; SpeedName: 'mph'; DistName: 'mi';
     EleFactor: 3.280839895; SpeedFactor: 2.2369362921; DistFactor: 1 / 1609.344),
    (Key: 'metric'; EleName: 'm'; SpeedName: 'km/h'; DistName: 'km';
     EleFactor: 1; SpeedFactor: 3.6; DistFactor: 0.001),
    (Key: 'aviation'; EleName: 'ft'; SpeedName: 'kt'; DistName: 'NM';
     EleFactor: 3.280839895; SpeedFactor: 1.9438444924; DistFactor: 1 / 1852),
    (Key: 'marine'; EleName: 'm'; SpeedName: 'kt'; DistName: 'NM';
     EleFactor: 1; SpeedFactor: 1.9438444924; DistFactor: 1 / 1852));

type
  TProfileSelectEvent = procedure(Sender: TObject; ASeg, AIdx: Integer) of object;

  { A point that stands out from the points around it. }
  TOutlier = record
    K: Integer;        // index into the visible points
    Speed: Boolean;    // False: elevation
    Hard: Boolean;     // outside any reasonable limit
    Score: Double;     // how far out of line, in units of the track's usual scatter
    Delta: Double;     // difference to the neighbours (m or m/s, signed)
  end;

  TProfileView = class(TFmxControl)
  private
    FDoc: TGpxDoc;
    FVisSeg: Integer;
    FSelSeg, FSelIdx, FSelK: Integer;
    FXMode: TProfileX;
    FUnits: TUnitSystem;
    FStale: Boolean;
    // the visible points, one after the other
    FCount: Integer;
    FSeg, FIdx: TArray<Integer>;
    FDist: TArray<Double>;   // metres from the start
    FTime: TArray<Double>;   // seconds from the start; NaN = no timestamp
    FEle: TArray<Double>;    // metres, limited to -500 ft .. 60,000 ft; NaN = none
    FSpd: TArray<Double>;    // m/s; NaN = unknown
    FHasEle, FHasSpd, FHasTime: Boolean;
    FDistMax, FTimeMax: Double;
    FStartLocal: TDateTime;  // local clock time of the earliest timestamp
    FEleMin, FEleMax, FSpdMax, FSpdTop: Double;
    FGain, FLoss: Double;
    // axes, in display units
    FEleLo, FEleStep, FSpdStep: Double;
    FPlot: TRectF;
    FHover: Integer;
    FMouseX: Single;
    FLine, FFill: TPathData;
    FRun: TArray<TPointF>;
    FRunN: Integer;
    FOut: TArray<TOutlier>;  // in track order
    FOnSelectPoint: TProfileSelectEvent;
    procedure Recalc;
    procedure FindOutliers;
    procedure CalcAxes;
    function EffectiveX: TProfileX;
    function XOf(K: Integer): Double;
    function XMax: Double;
    function XToScreen(AValue: Double): Single;
    function EleToScreen(AMetres: Double): Single;
    function SpdToScreen(AMps: Double): Single;
    function PointAt(X: Single): Integer;
    function FindK(ASeg, AIdx: Integer): Integer;
    procedure BuildSeries(const AValues: TArray<Double>; AEle, AFill: Boolean);
    procedure SetFont(ASize: Single; ABold: Boolean = False);
    procedure Text(const R: TRectF; const S: string; AColor: TAlphaColor;
      AHorz: TTextAlign; AVert: TTextAlign = TTextAlign.Center);
    procedure PaintFrame;
    procedure PaintAxes;
    procedure PaintSeries;
    procedure PaintOutliers;
    procedure PaintMarker(K: Integer; AColor: TAlphaColor; AThickness: Single);
    procedure PaintTooltip(K: Integer);
    procedure PaintMessage(const S: string);
    procedure SetDoc(const Value: TGpxDoc);
    procedure SetVisSeg(const Value: Integer);
    procedure SetXMode(const Value: TProfileX);
    procedure SetUnits(const Value: TUnitSystem);
    function GetHasTime: Boolean;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The track (or what is shown of it) has changed. }
    procedure DataChanged;
    procedure SetSelection(ASeg, AIdx: Integer);
    { One line of totals: distance, duration, climb, top speed. }
    function Summary: string;
    function FormatEle(AMetres: Double): string;
    function FormatSpeed(AMps: Double): string;
    function FormatDist(AMetres: Double): string;
    { Points that are out of line with their neighbours, in track order. }
    function OutlierCount: Integer;
    { The outlier after (ADir > 0) or before the given point, wrapping round at
      the ends; with no point given, the first / last one.  -1: there are none. }
    function OutlierStep(ASeg, AIdx, ADir: Integer): Integer;
    function OutlierPos(ASeg, AIdx: Integer): Integer;
    function OutlierPoint(APos: Integer; out ASeg, AIdx: Integer): Boolean;
    function OutlierText(APos: Integer): string;
    property Doc: TGpxDoc read FDoc write SetDoc;
    property VisibleSeg: Integer read FVisSeg write SetVisSeg;
    property XMode: TProfileX read FXMode write SetXMode;
    property Units: TUnitSystem read FUnits write SetUnits;
    property HasTime: Boolean read GetHasTime;
    property OnSelectPoint: TProfileSelectEvent read FOnSelectPoint write FOnSelectPoint;
  end;

function FormatDuration(ASeconds: Double; AWithSeconds: Boolean = True): string;
{ A GPX timestamp (UTC) as local date and time. }
function LocalTimeText(AUtc: TDateTime): string;

implementation

uses
  Generics.Collections, Generics.Defaults, DateUtils, StrUtils, uCompat;

{ hh:nn:ss.x, x being tenths of a second. }
function ClockText(ALocal: TDateTime; AWithDate: Boolean): string;
var
  Tenths: Int64;
  V: TDateTime;
begin
  Tenths := Round(ALocal * SecsPerDay * 10);
  V := (Tenths div 10) / SecsPerDay + 0.0001 / SecsPerDay;
  Result := FormatDateTime('hh":"nn":"ss', V) + '.' + IntToStr(Tenths mod 10);
  if AWithDate then
    Result := FormatDateTime('ddddd', V) + ' ' + Result;
end;

function LocalTimeText(AUtc: TDateTime): string;
begin
  Result := ClockText(TTimeZone.Local.ToLocalTime(AUtc), True);
end;

const
  ColEle = $FF2A78D6;        // blue
  ColSpeed = $FFEB6834;      // orange
  ColSelect = $FF14308A;     // the map's track colour
  ColInk = $FF2B2F36;
  ColInk2 = $FF5B6068;
  ColGrid = $FFE3E6EA;
  ColAxis = $FFC3C7CE;
  ColSurface = $FFFFFFFF;
  YIntervals = 4;
  AxisW = 58.0;              // room for the tick labels on either side
  TopH = 26.0;               // legend row
  BottomH = 24.0;            // x tick labels

function FormatDuration(ASeconds: Double; AWithSeconds: Boolean): string;
var
  T: Int64;
begin
  if AWithSeconds then
  begin
    T := Round(ASeconds);
    Result := Format('%d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60]);
  end
  else
  begin
    T := Round(ASeconds / 60);
    Result := Format('%d:%.2d', [T div 60, T mod 60]);
  end;
end;

function Num(AValue: Double; ADecimals: Integer = 0): string;
begin
  case ADecimals of
    0: Result := FormatFloat('#,##0', AValue);
    1: Result := FormatFloat('#,##0.0', AValue);
  else
    Result := FormatFloat('#,##0.00', AValue);
  end;
end;

function DecimalsFor(AStep: Double): Integer;
begin
  if AStep >= 1 then
    Result := 0
  else if AStep >= 0.1 then
    Result := 1
  else
    Result := 2;
end;

{ A step from the 1 / 2 / 2.5 / 5 series that is at least ARaw. }
function NiceStep(ARaw: Double): Double;
const
  M: array[0..4] of Double = (1, 2, 2.5, 5, 10);
var
  Mag: Double;
  I: Integer;
begin
  if not (ARaw > 1e-12) then
    Exit(1);
  Mag := Power(10, Floor(Log10(ARaw)));
  for I := 0 to High(M) do
    if M[I] * Mag >= ARaw * 0.9999 then
      Exit(M[I] * Mag);
  Result := 10 * Mag;
end;

{ Axis of AIntervals equal steps that covers AMin..AMax. }
procedure NiceAxis(AMin, AMax: Double; AIntervals: Integer; out ALo, AStep: Double);
var
  Guard: Integer;
begin
  if AMax - AMin < 1e-9 then
  begin
    AMin := AMin - 1;
    AMax := AMax + 1;
  end;
  AStep := NiceStep((AMax - AMin) / AIntervals);
  for Guard := 1 to 8 do
  begin
    ALo := Floor(AMin / AStep + 1e-9) * AStep;
    if ALo + AStep * AIntervals >= AMax - 1e-9 then
      Exit;
    AStep := NiceStep(AStep * 1.01);
  end;
end;

{ TProfileView }

constructor TProfileView.Create(AOwner: TComponent);
begin
  inherited;
  FLine := TPathData.Create;
  FFill := TPathData.Create;
  FVisSeg := -1;
  FSelSeg := -1;
  FSelIdx := -1;
  FSelK := -1;
  FHover := -1;
  FStale := True;
  Cursor := crDefault;
end;

destructor TProfileView.Destroy;
begin
  FLine.Free;
  FFill.Free;
  inherited;
end;

procedure TProfileView.DataChanged;
begin
  FStale := True;
  FHover := -1;
  Repaint;
end;

procedure TProfileView.SetDoc(const Value: TGpxDoc);
begin
  FDoc := Value;
  FSelSeg := -1;
  FSelIdx := -1;
  DataChanged;
end;

procedure TProfileView.SetVisSeg(const Value: Integer);
begin
  if FVisSeg <> Value then
  begin
    FVisSeg := Value;
    DataChanged;
  end;
end;

procedure TProfileView.SetXMode(const Value: TProfileX);
begin
  if FXMode <> Value then
  begin
    FXMode := Value;
    FHover := -1;
    Repaint;
  end;
end;

procedure TProfileView.SetUnits(const Value: TUnitSystem);
begin
  if FUnits <> Value then
  begin
    FUnits := Value;
    Repaint;
  end;
end;

procedure TProfileView.SetSelection(ASeg, AIdx: Integer);
begin
  if (ASeg = FSelSeg) and (AIdx = FSelIdx) and not FStale then
    Exit;
  FSelSeg := ASeg;
  FSelIdx := AIdx;
  if not FStale then
    FSelK := FindK(ASeg, AIdx);
  Repaint;
end;

function TProfileView.GetHasTime: Boolean;
begin
  if FStale then
    Recalc;
  Result := FHasTime;
end;

function TProfileView.FindK(ASeg, AIdx: Integer): Integer;
var
  K: Integer;
begin
  if (ASeg >= 0) and (AIdx >= 0) then
    for K := 0 to FCount - 1 do
      if (FSeg[K] = ASeg) and (FIdx[K] = AIdx) then
        Exit(K);
  Result := -1;
end;

{ ---- data ------------------------------------------------------------------ }

function ByScore(constref L, R: TOutlier): Integer;
begin
  Result := CompareValue(R.Score, L.Score);
  if Result = 0 then
    Result := L.K - R.K;
end;

function ByPosition(constref L, R: TOutlier): Integer;
begin
  Result := L.K - R.K;
  if Result = 0 then
    Result := CompareValue(R.Score, L.Score);
end;

procedure TProfileView.Recalc;
var
  S, I, K, N: Integer;
  Seg: TGpxSegment;
  P: PGpxPoint;
  Cum, T0, T1, V, Ref, P99: Double;
  Sorted: TArray<Double>;
begin
  FStale := False;
  FCount := 0;
  FHasEle := False;
  FHasSpd := False;
  FHasTime := False;
  FDistMax := 0;
  FTimeMax := 0;
  FGain := 0;
  FLoss := 0;
  FSpdMax := 0;
  FSpdTop := 0;
  FEleMin := 0;
  FEleMax := 0;
  FSelK := -1;
  if FDoc = nil then
    Exit;

  N := 0;
  T0 := 0;
  T1 := 0;
  for S := 0 to FDoc.SegCount - 1 do
    if (FVisSeg < 0) or (FVisSeg = S) then
    begin
      Seg := FDoc[S];
      Inc(N, Seg.Count);
      for I := 0 to Seg.Count - 1 do
      begin
        P := Seg[I];
        if P.HasTime then
        begin
          if (T0 = 0) or (P.Time < T0) then T0 := P.Time;
          if (T1 = 0) or (P.Time > T1) then T1 := P.Time;
        end;
      end;
    end;
  if Length(FSeg) < N then
  begin
    SetLength(FSeg, N);
    SetLength(FIdx, N);
    SetLength(FDist, N);
    SetLength(FTime, N);
    SetLength(FEle, N);
    SetLength(FSpd, N);
  end;
  FHasTime := T1 > T0;
  FTimeMax := (T1 - T0) * SecsPerDay;
  FStartLocal := 0;
  if T0 <> 0 then
    FStartLocal := TTimeZone.Local.ToLocalTime(T0);

  K := 0;
  Cum := 0;
  Ref := NaN;
  for S := 0 to FDoc.SegCount - 1 do
    if (FVisSeg < 0) or (FVisSeg = S) then
    begin
      Seg := FDoc[S];
      for I := 0 to Seg.Count - 1 do
      begin
        P := Seg[I];
        if I > 0 then
          Cum := Cum + GeoDist(Seg[I - 1]^, P^);
        FSeg[K] := S;
        FIdx[K] := I;
        FDist[K] := Cum;
        if P.HasTime then
          FTime[K] := (P.Time - T0) * SecsPerDay
        else
          FTime[K] := NaN;

        FEle[K] := NaN;
        if P.HasEle then
        begin
          V := EnsureRange(P.Ele, MinEleM, MaxEleM);
          FEle[K] := V;
          if not FHasEle then
          begin
            FEleMin := V;
            FEleMax := V;
            Ref := V;
            FHasEle := True;
          end;
          FEleMin := Min(FEleMin, V);
          FEleMax := Max(FEleMax, V);
          // climb / descent, ignoring jitter of less than 3 m
          if V - Ref >= 3 then
          begin
            FGain := FGain + V - Ref;
            Ref := V;
          end
          else if Ref - V >= 3 then
          begin
            FLoss := FLoss + Ref - V;
            Ref := V;
          end;
        end;

        V := FDoc.SpeedAt(S, I);
        FSpd[K] := V;
        if not IsNan(V) then
        begin
          FHasSpd := True;
          FSpdMax := Max(FSpdMax, V);
        end;
        Inc(K);
      end;
    end;
  FCount := K;
  FDistMax := Cum;

  // One glitch must not flatten the whole speed curve: when the maximum is far
  // beyond the 99th percentile the axis follows the percentile and the glitch
  // runs off the top.
  FSpdTop := FSpdMax;
  if FHasSpd then
  begin
    SetLength(Sorted, FCount);
    N := 0;
    for K := 0 to FCount - 1 do
      if not IsNan(FSpd[K]) then
      begin
        Sorted[N] := FSpd[K];
        Inc(N);
      end;
    SetLength(Sorted, N);
    TArrayHelper<Double>.Sort(Sorted);
    P99 := Sorted[Floor(0.99 * (N - 1))];
    if (P99 > 0) and (FSpdMax > 3 * P99) then
      FSpdTop := P99 * 1.5;
  end;

  FSelK := FindK(FSelSeg, FSelIdx);
  FindOutliers;
end;

{ Compare each reading with the median of nearby points in its segment.
  Scale the difference by the track's usual scatter. Minimum differences
  suppress jitter, and Abrupt helps distinguish spikes from gradual changes.
  Readings beyond the hard limits bypass those filters. }
procedure TProfileView.FindOutliers;
const
  Span = 5;
  MinScore = 8.0;         // times the track's usual scatter
  MinSpeedPart = 0.25;    // and, for speed, this share of the speed around it
  MaxOut = 50;
  HardMaxEle = 12192.0;   // 40,000 ft
  HardMaxSpeed = 400.0;   // m/s, about 900 mph
var
  Cand: TList<TOutlier>;
  Dev, Sorted: TArray<Double>;
  I: Integer;

  function Value(K: Integer; ASpeed: Boolean): Double;
  begin
    if ASpeed then
      Result := FSpd[K]
    else
      Result := FDoc[FSeg[K]][FIdx[K]].Ele;   // not the clamped copy used for drawing
  end;

  function IsHard(V: Double; ASpeed: Boolean): Boolean;
  begin
    if ASpeed then
      Result := V > HardMaxSpeed
    else
      Result := (V < MinEleM) or (V > HardMaxEle);
  end;

  { Compare the point's deviation from its immediate neighbours with the
    typical change between adjacent points nearby. }
  function Abrupt(K: Integer; ASpeed: Boolean): Boolean;
  const
    StepFactor = 1.5;
  var
    J, N, A: Integer;
    V0, V1, V2, T: Double;
    St: array[0..2 * Span] of Double;
  begin
    Result := True;
    if (K = 0) or (K = FCount - 1) or (FSeg[K - 1] <> FSeg[K]) or (FSeg[K + 1] <> FSeg[K]) then
      Exit;
    V0 := Value(K - 1, ASpeed);
    V1 := Value(K, ASpeed);
    V2 := Value(K + 1, ASpeed);
    if IsNan(V0) or IsNan(V2) then
      Exit;
    N := 0;
    for J := Max(0, K - Span) to Min(FCount - 2, K + Span - 1) do
      if (FSeg[J] = FSeg[K]) and (FSeg[J + 1] = FSeg[K]) then
      begin
        T := Abs(Value(J + 1, ASpeed) - Value(J, ASpeed));
        if IsNan(T) then
          Continue;
        A := N;
        while (A > 0) and (St[A - 1] > T) do
        begin
          St[A] := St[A - 1];
          Dec(A);
        end;
        St[A] := T;
        Inc(N);
      end;
    if N < 3 then
      Exit;
    if Odd(N) then
      T := St[N div 2]
    else
      T := (St[N div 2 - 1] + St[N div 2]) / 2;
    Result := Abs(V1 - (V0 + V2) / 2) > StepFactor * T;
  end;

  procedure Scan(ASpeed: Boolean);
  var
    K, J, N, A, B: Integer;
    V, Med, Scale, Floor_, MinAbs, T: Double;
    Nb: array[0..2 * Span] of Double;
    O: TOutlier;
  begin
    if ASpeed then
    begin
      Floor_ := 0.5;
      MinAbs := 4.5;      // m/s, about 10 mph
    end
    else
    begin
      Floor_ := 3.0;
      MinAbs := 20.0;     // m, about 65 ft
    end;

    for K := 0 to FCount - 1 do
    begin
      Dev[K] := NaN;
      V := Value(K, ASpeed);
      if IsNan(V) then
        Continue;
      N := 0;
      for J := Max(0, K - Span) to Min(FCount - 1, K + Span) do
        if (J <> K) and (FSeg[J] = FSeg[K]) then
        begin
          T := Value(J, ASpeed);
          if IsNan(T) or IsHard(T, ASpeed) then
            Continue;
          // insertion sort; at most ten values
          A := N;
          while (A > 0) and (Nb[A - 1] > T) do
          begin
            Nb[A] := Nb[A - 1];
            Dec(A);
          end;
          Nb[A] := T;
          Inc(N);
        end;
      if N < 2 then
        Continue;
      if Odd(N) then
        Med := Nb[N div 2]
      else
        Med := (Nb[N div 2 - 1] + Nb[N div 2]) / 2;
      Dev[K] := V - Med;
    end;

    // the track's usual scatter around the local median
    N := 0;
    for K := 0 to FCount - 1 do
      if not IsNan(Dev[K]) and not IsHard(Value(K, ASpeed), ASpeed) then
      begin
        Sorted[N] := Abs(Dev[K]);
        Inc(N);
      end;
    Scale := Floor_;
    if N > 0 then
    begin
      TArrayHelper<Double>.Sort(Sorted, TComparer<Double>.Default, 0, N);
      Scale := Max(Floor_, 1.4826 * Sorted[N div 2]);
    end;

    B := Cand.Count;
    for K := 0 to FCount - 1 do
    begin
      V := Value(K, ASpeed);
      if IsNan(V) then
        Continue;
      O.K := K;
      O.Speed := ASpeed;
      O.Hard := IsHard(V, ASpeed);
      O.Delta := Dev[K];
      if O.Hard then
        O.Score := 1e9 + Abs(V)
      else if not IsNan(Dev[K]) and (Abs(Dev[K]) >= MinAbs) and (Abs(Dev[K]) / Scale >= MinScore) and
        (not ASpeed or (Abs(Dev[K]) >= MinSpeedPart * Abs(V - Dev[K]))) and Abrupt(K, ASpeed) then
        O.Score := Abs(Dev[K]) / Scale
      else
        Continue;
      // one bad point also disturbs its neighbours: keep the worst of a run
      if (Cand.Count > B) and (Cand.Last.K >= K - 3) and (FSeg[Cand.Last.K] = FSeg[K]) then
      begin
        if O.Score > Cand.Last.Score then
          Cand[Cand.Count - 1] := O;
      end
      else
        Cand.Add(O);
    end;
  end;

begin
  FOut := nil;
  if (FDoc = nil) or (FCount < 3) then
    Exit;
  SetLength(Dev, FCount);
  SetLength(Sorted, FCount);
  Cand := TList<TOutlier>.Create;
  try
    if FHasEle then
      Scan(False);
    if FHasSpd then
      Scan(True);
    Cand.Sort(TComparer<TOutlier>.Construct(ByScore));
    if Cand.Count > MaxOut then
      Cand.Count := MaxOut;     // the worst ones ...
    // ... listed in track order, left to right on the graph; a point that is
    // out of line in both elevation and speed is listed once
    Cand.Sort(TComparer<TOutlier>.Construct(ByPosition));
    for I := Cand.Count - 1 downto 1 do
      if Cand[I].K = Cand[I - 1].K then
        Cand.Delete(I);
    FOut := Cand.ToArray;
  finally
    Cand.Free;
  end;
end;

function TProfileView.OutlierCount: Integer;
begin
  if FStale then
    Recalc;
  Result := Length(FOut);
end;

function TProfileView.OutlierStep(ASeg, AIdx, ADir: Integer): Integer;
var
  I, K, N: Integer;
begin
  if FStale then
    Recalc;
  N := Length(FOut);
  if N = 0 then
    Exit(-1);
  K := FindK(ASeg, AIdx);
  if ADir > 0 then
  begin
    Result := 0;
    if K >= 0 then
      for I := 0 to N - 1 do
        if FOut[I].K > K then
          Exit(I);
  end
  else
  begin
    Result := N - 1;
    if K >= 0 then
      for I := N - 1 downto 0 do
        if FOut[I].K < K then
          Exit(I);
  end;
end;

function TProfileView.OutlierPos(ASeg, AIdx: Integer): Integer;
var
  I: Integer;
begin
  if FStale then
    Recalc;
  for I := 0 to High(FOut) do
    if (FSeg[FOut[I].K] = ASeg) and (FIdx[FOut[I].K] = AIdx) then
      Exit(I);
  Result := -1;
end;

function TProfileView.OutlierPoint(APos: Integer; out ASeg, AIdx: Integer): Boolean;
begin
  if FStale then
    Recalc;
  Result := (APos >= 0) and (APos < Length(FOut));
  if Result then
  begin
    ASeg := FSeg[FOut[APos].K];
    AIdx := FIdx[FOut[APos].K];
  end;
end;

function TProfileView.OutlierText(APos: Integer): string;
var
  O: TOutlier;
begin
  Result := '';
  if FStale then
    Recalc;
  if (APos < 0) or (APos >= Length(FOut)) then
    Exit;
  O := FOut[APos];
  if O.Speed then
  begin
    if O.Hard then
      Result := 'speed ' + FormatSpeed(FSpd[O.K]) + ' is out of range'
    else
      Result := 'speed ' + FormatSpeed(Abs(O.Delta)) + IfThen(O.Delta > 0, ' above', ' below') + ' its neighbours';
  end
  else if O.Hard then
    Result := 'elevation ' + FormatEle(FDoc[FSeg[O.K]][FIdx[O.K]].Ele) + ' is out of range'
  else
    Result := 'elevation ' + FormatEle(Abs(O.Delta)) + IfThen(O.Delta > 0, ' above', ' below') + ' its neighbours';
end;

procedure TProfileView.CalcAxes;
var
  U: TUnitInfo;
  LimLo, LimHi, Lo: Double;
begin
  U := UnitInfo[FUnits];
  // elevation: automatic, but never below -500 ft and never above 60,000 ft
  LimLo := MinEleM * U.EleFactor;
  LimHi := MaxEleM * U.EleFactor;
  NiceAxis(FEleMin * U.EleFactor, FEleMax * U.EleFactor, YIntervals, FEleLo, FEleStep);
  if FEleLo < LimLo then
    FEleLo := LimLo;
  if FEleLo + FEleStep * YIntervals > LimHi then
    FEleStep := (LimHi - FEleLo) / YIntervals;
  // speed: always from 0
  NiceAxis(0, Max(FSpdTop * U.SpeedFactor, 1e-6), YIntervals, Lo, FSpdStep);
end;

function TProfileView.EffectiveX: TProfileX;
begin
  if (FXMode = pxTime) and FHasTime then
    Result := pxTime
  else
    Result := pxDistance;
end;

function TProfileView.XOf(K: Integer): Double;
begin
  if EffectiveX = pxTime then
    Result := FTime[K]
  else
    Result := FDist[K];
end;

function TProfileView.XMax: Double;
begin
  if EffectiveX = pxTime then
    Result := FTimeMax
  else
    Result := FDistMax;
  if Result <= 0 then
    Result := 1;
end;

function TProfileView.XToScreen(AValue: Double): Single;
begin
  Result := FPlot.Left + AValue / XMax * FPlot.Width;
end;

function TProfileView.EleToScreen(AMetres: Double): Single;
var
  F: Double;
begin
  F := (AMetres * UnitInfo[FUnits].EleFactor - FEleLo) / (FEleStep * YIntervals);
  Result := FPlot.Bottom - EnsureRange(F, -0.05, 1.05) * FPlot.Height;
end;

function TProfileView.SpdToScreen(AMps: Double): Single;
var
  F: Double;
begin
  F := AMps * UnitInfo[FUnits].SpeedFactor / (FSpdStep * YIntervals);
  Result := FPlot.Bottom - EnsureRange(F, 0, 1.05) * FPlot.Height;
end;

function TProfileView.PointAt(X: Single): Integer;
var
  K: Integer;
  Target, D, Best, V: Double;
begin
  Result := -1;
  if (FCount = 0) or (FPlot.Width <= 0) then
    Exit;
  Target := (X - FPlot.Left) / FPlot.Width * XMax;
  Best := MaxDouble;
  for K := 0 to FCount - 1 do
  begin
    V := XOf(K);
    if IsNan(V) then
      Continue;
    D := Abs(V - Target);
    if D < Best then
    begin
      Best := D;
      Result := K;
    end;
  end;

  // an outlier marker within a few pixels wins, so the flagged points can be picked
  Best := 7 / FPlot.Width * XMax;
  for K := 0 to High(FOut) do
  begin
    V := XOf(FOut[K].K);
    if not IsNan(V) and (Abs(V - Target) < Best) then
    begin
      Best := Abs(V - Target);
      Result := FOut[K].K;
    end;
  end;
end;

function TProfileView.FormatEle(AMetres: Double): string;
begin
  Result := Num(AMetres * UnitInfo[FUnits].EleFactor) + ' ' + UnitInfo[FUnits].EleName;
end;

function TProfileView.FormatSpeed(AMps: Double): string;
begin
  Result := Num(AMps * UnitInfo[FUnits].SpeedFactor, 1) + ' ' + UnitInfo[FUnits].SpeedName;
end;

function TProfileView.FormatDist(AMetres: Double): string;
begin
  Result := Num(AMetres * UnitInfo[FUnits].DistFactor, 2) + ' ' + UnitInfo[FUnits].DistName;
end;

function TProfileView.Summary: string;
const
  Dot = '   ·   ';
var
  U: TUnitInfo;
  D: Double;
begin
  Result := '';
  if FStale then
    Recalc;
  if (FDoc = nil) or (FCount = 0) then
    Exit;
  U := UnitInfo[FUnits];
  D := FDistMax * U.DistFactor;
  Result := Num(D, IfThen(D < 100, 2, 1)) + ' ' + U.DistName;
  if FHasTime then
    Result := Result + Dot + FormatDuration(FTimeMax);
  if FHasEle then
    Result := Result + Dot + '↑ ' + FormatEle(FGain) + '   ↓ ' + FormatEle(FLoss);
  if FHasSpd then
    Result := Result + Dot + 'max ' + FormatSpeed(FSpdMax);
end;

{ ---- mouse ----------------------------------------------------------------- }

procedure TProfileView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  K: Integer;
begin
  inherited;
  if FStale then
    Exit;
  FMouseX := X;
  if (X < FPlot.Left - 6) or (X > FPlot.Right + 6) then
    K := -1
  else
    K := PointAt(X);
  if K <> FHover then
  begin
    FHover := K;
    Repaint;
  end;
  // dragging along the graph scrubs the selection along the track
  if (ssLeft in Shift) and (K >= 0) and Assigned(FOnSelectPoint) then
    FOnSelectPoint(Self, FSeg[K], FIdx[K]);
end;

procedure TProfileView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if (Button = TMouseButton.mbLeft) and not FStale and (FHover >= 0) and (FHover < FCount) and
    Assigned(FOnSelectPoint) then
    FOnSelectPoint(Self, FSeg[FHover], FIdx[FHover]);
end;

procedure TProfileView.DoMouseLeave;
begin
  inherited;
  if FHover >= 0 then
  begin
    FHover := -1;
    Repaint;
  end;
end;

{ ---- painting -------------------------------------------------------------- }

procedure TProfileView.SetFont(ASize: Single; ABold: Boolean);
begin
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := ASize;
  if ABold then
    Canvas.Font.Style := [TFontStyle.fsBold]
  else
    Canvas.Font.Style := [];
end;

procedure TProfileView.Text(const R: TRectF; const S: string; AColor: TAlphaColor;
  AHorz, AVert: TTextAlign);
begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := AColor;
  Canvas.FillText(R, S, False, 1, [], AHorz, AVert);
end;

procedure TProfileView.PaintFrame;
begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := ColSurface;
  Canvas.FillRect(LocalRect, 0, 0, AllCorners, 1);
end;

procedure TProfileView.PaintMessage(const S: string);
begin
  SetFont(13);
  Text(LocalRect, S, ColInk2, TTextAlign.Center);
end;

procedure TProfileView.Paint;
var
  State: TCanvasSaveState;
begin
  if FStale then
    Recalc;
  State := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(LocalRect);
    PaintFrame;
    FPlot := TRectF.Create(AxisW, TopH, Width - AxisW, Height - BottomH);
    if FDoc = nil then
      PaintMessage('Open a track to see its elevation and speed')
    else if (FCount < 2) or not (FHasEle or FHasSpd) then
      PaintMessage('This track has no elevation or time data')
    else if (FPlot.Width < 40) or (FPlot.Height < 24) then
      // too small to draw anything meaningful
    else
    begin
      CalcAxes;
      PaintAxes;
      PaintSeries;
      PaintOutliers;
      if FSelK >= 0 then
        PaintMarker(FSelK, ColSelect, 1.5);
      if (FHover >= 0) and (FHover < FCount) then
      begin
        if FHover <> FSelK then
          PaintMarker(FHover, ColInk2, 1);
        PaintTooltip(FHover);
      end;
    end;
  finally
    Canvas.RestoreState(State);
  end;
end;

procedure TProfileView.PaintAxes;
var
  U: TUnitInfo;
  I, Dec_, N: Integer;
  Y, X, W, HalfW: Single;
  Step, V, V0, Range, StartSec: Double;
  S, TimeFmt: string;
  R: TRectF;
  MultiDay: Boolean;
const
  TimeSteps: array[0..17] of Integer = (1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800,
    3600, 7200, 10800, 21600, 43200, 86400);
begin
  U := UnitInfo[FUnits];
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  Canvas.Stroke.Cap := TStrokeCap.Flat;
  Canvas.Stroke.Thickness := 1;

  // legend row: each series is named right above its own axis
  SetFont(12);
  Canvas.Fill.Kind := TBrushKind.Solid;
  if FHasEle then
  begin
    Canvas.Fill.Color := ColEle;
    Canvas.FillRect(TRectF.Create(10, 8, 20, 18), 2, 2, AllCorners, 1);
    Text(TRectF.Create(26, 0, 300, TopH), 'Elevation (' + U.EleName + ')', ColInk, TTextAlign.Leading);
  end
  else
    Text(TRectF.Create(10, 0, 300, TopH), 'No elevation data', ColInk2, TTextAlign.Leading);
  if FHasSpd then
  begin
    S := 'Speed (' + U.SpeedName + ')';
    W := Canvas.TextWidth(S);
    Text(TRectF.Create(Width - 300, 0, Width - 10, TopH), S, ColInk, TTextAlign.Trailing);
    Canvas.Fill.Color := ColSpeed;
    Canvas.FillRect(TRectF.Create(Width - 10 - W - 22, 12, Width - 10 - W - 6, 14.5), 1, 1, AllCorners, 1);
  end
  else
    Text(TRectF.Create(Width - 300, 0, Width - 10, TopH), 'No speed (needs timestamps)', ColInk2,
      TTextAlign.Trailing);
  MultiDay := Trunc(FStartLocal + FTimeMax / SecsPerDay) > Trunc(FStartLocal);
  if EffectiveX = pxTime then
  begin
    // the real clock, in this computer's time zone
    S := 'Local time  ·  ' + FormatDateTime('ddddd', FStartLocal);
    if MultiDay then
      S := S + ' – ' + FormatDateTime('ddddd', FStartLocal + FTimeMax / SecsPerDay);
  end
  else
    S := 'Distance (' + U.DistName + ')';
  SetFont(11);
  if Width > 560 then
    Text(TRectF.Create(0, 0, Width, TopH), S, ColInk2, TTextAlign.Center);

  // horizontal grid, shared by both axes
  SetFont(11);
  for I := 0 to YIntervals do
  begin
    Y := Round(FPlot.Bottom - I / YIntervals * FPlot.Height) + 0.5;
    if I = 0 then
      Canvas.Stroke.Color := ColAxis
    else
      Canvas.Stroke.Color := ColGrid;
    Canvas.DrawLine(PointF(FPlot.Left, Y), PointF(FPlot.Right, Y), 1);
    if FHasEle then
      Text(TRectF.Create(0, Y - 9, FPlot.Left - 8, Y + 9),
        Num(FEleLo + I * FEleStep, DecimalsFor(FEleStep)), ColInk2, TTextAlign.Trailing);
    if FHasSpd then
      Text(TRectF.Create(FPlot.Right + 8, Y - 9, Width, Y + 9),
        Num(I * FSpdStep, DecimalsFor(FSpdStep)), ColInk2, TTextAlign.Leading);
  end;

  // x axis
  Dec_ := 0;
  V0 := 0;
  HalfW := 45;
  TimeFmt := 't';
  if EffectiveX = pxTime then
  begin
    HalfW := IfThen(MultiDay, 75, 55);
    N := Max(2, Trunc(FPlot.Width / (HalfW * 2 + 20)));
    Range := FTimeMax;
    Step := TimeSteps[High(TimeSteps)];
    for I := 0 to High(TimeSteps) do
      if TimeSteps[I] >= Range / N then
      begin
        Step := TimeSteps[I];
        Break;
      end;
    while Range / Step > N do
      Step := Step * 2;
    // ticks sit on round clock times (:00, :15 ...), not on round offsets from the start
    StartSec := FStartLocal * SecsPerDay;
    V0 := Ceil(StartSec / Step - 1e-9) * Step - StartSec;
    if Step < 60 then
      TimeFmt := 'tt';
    if Step >= SecsPerDay then
      TimeFmt := 'mmm d'
    else if MultiDay then
      TimeFmt := 'mmm d  ' + TimeFmt;
  end
  else
  begin
    N := Max(2, Trunc(FPlot.Width / 90));
    Range := FDistMax * U.DistFactor;
    Step := NiceStep(Range / N);
    Dec_ := DecimalsFor(Step);
  end;
  if (Range <= 0) or (Step <= 0) then
    Exit;
  Canvas.Stroke.Color := ColAxis;
  I := 0;
  while V0 + I * Step <= Range * 1.0001 do
  begin
    V := V0 + I * Step;
    X := Round(FPlot.Left + V / Range * FPlot.Width) + 0.5;
    Canvas.DrawLine(PointF(X, FPlot.Bottom), PointF(X, FPlot.Bottom + 4), 1);
    if EffectiveX = pxTime then
      S := FormatDateTime(TimeFmt, FStartLocal + (V + 0.01) / SecsPerDay)
    else
      S := Num(V, Dec_);
    R := TRectF.Create(X - HalfW, FPlot.Bottom + 4, X + HalfW, Height - 2);
    if X - HalfW < 2 then
      Text(TRectF.Create(Max(2, X - 3), R.Top, X + 2 * HalfW, R.Bottom), S, ColInk2, TTextAlign.Leading)
    else if X + HalfW > Width - 2 then
      Text(TRectF.Create(X - 2 * HalfW, R.Top, Width - 4, R.Bottom), S, ColInk2, TTextAlign.Trailing)
    else
      Text(R, S, ColInk2, TTextAlign.Center);
    Inc(I);
  end;
end;

{ Scan the series and build the drawing paths. For each run of points in
  a pixel column, keep the first, lowest, highest and last values. }
procedure TProfileView.BuildSeries(const AValues: TArray<Double>; AEle, AFill: Boolean);
var
  K, Col, BCol, LastSeg: Integer;
  PX, PY, BX, BFirst, BMin, BMax, BLast: Single;
  BHas: Boolean;
  XV: Double;

  procedure Add(X, Y: Single);
  begin
    if FRunN >= Length(FRun) then
      SetLength(FRun, FRunN * 2 + 256);
    FRun[FRunN] := PointF(X, Y);
    Inc(FRunN);
  end;

  procedure EmitBucket;
  begin
    if not BHas then
      Exit;
    BHas := False;
    Add(BX, BFirst);
    if BMin < Min(BFirst, BLast) then
      Add(BX, BMin);
    if BMax > Max(BFirst, BLast) then
      Add(BX, BMax);
    if (BLast <> BFirst) or (FRun[FRunN - 1].Y <> BLast) then
      Add(BX, BLast);
  end;

  procedure Flush;
  var
    J: Integer;
  begin
    EmitBucket;
    if FRunN >= 2 then
    begin
      FLine.MoveTo(FRun[0]);
      for J := 1 to FRunN - 1 do
        FLine.LineTo(FRun[J]);
      if AFill then
      begin
        FFill.MoveTo(PointF(FRun[0].X, FPlot.Bottom));
        for J := 0 to FRunN - 1 do
          FFill.LineTo(FRun[J]);
        FFill.LineTo(PointF(FRun[FRunN - 1].X, FPlot.Bottom));
        FFill.ClosePath;
      end;
    end;
    FRunN := 0;
  end;

begin
  FLine.Clear;
  FFill.Clear;
  FRunN := 0;
  BHas := False;
  BCol := 0;
  BX := 0;
  BFirst := 0;
  BMin := 0;
  BMax := 0;
  BLast := 0;
  LastSeg := -1;
  for K := 0 to FCount - 1 do
  begin
    if FSeg[K] <> LastSeg then
    begin
      Flush;               // segments are not joined
      LastSeg := FSeg[K];
    end;
    XV := XOf(K);
    if IsNan(XV) or IsNan(AValues[K]) then
      Continue;
    PX := XToScreen(XV);
    if AEle then
      PY := EleToScreen(AValues[K])
    else
      PY := SpdToScreen(AValues[K]);
    Col := Floor(PX);
    if BHas and (Col = BCol) then
    begin
      BMin := Min(BMin, PY);
      BMax := Max(BMax, PY);
      BLast := PY;
    end
    else
    begin
      EmitBucket;
      BHas := True;
      BCol := Col;
      BX := PX;
      BFirst := PY;
      BMin := PY;
      BMax := PY;
      BLast := PY;
    end;
  end;
  Flush;
end;

procedure TProfileView.PaintSeries;
var
  State: TCanvasSaveState;
  Clip: TRectF;
begin
  State := Canvas.SaveState;
  try
    Clip := FPlot;
    Clip.Inflate(1, 1);
    Clip.Top := FPlot.Top - 4;
    Canvas.IntersectClipRect(Clip);
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Dash := TStrokeDash.Solid;
    Canvas.Stroke.Cap := TStrokeCap.Round;
    Canvas.Stroke.Join := TStrokeJoin.Round;
    Canvas.Fill.Kind := TBrushKind.Solid;

    if FHasEle then
    begin
      BuildSeries(FEle, True, True);
      Canvas.Fill.Color := ColEle;
      Canvas.FillPath(FFill, 0.16);
      Canvas.Stroke.Color := ColEle;
      Canvas.Stroke.Thickness := 2;
      Canvas.DrawPath(FLine, 1);
    end;
    if FHasSpd then
    begin
      BuildSeries(FSpd, False, False);
      Canvas.Stroke.Color := ColSpeed;
      Canvas.Stroke.Thickness := 1.75;
      Canvas.DrawPath(FLine, 1);
    end;
  finally
    Canvas.RestoreState(State);
  end;
end;

{ A small marker along the top edge for every outlier, in its curve's colour.
  They sit at the top so that a value running off the chart is still marked. }
procedure TProfileView.PaintOutliers;
var
  I: Integer;
  V: Double;
  X, Y: Single;
  Poly: TPolygon;
begin
  SetLength(Poly, 3);
  Canvas.Fill.Kind := TBrushKind.Solid;
  for I := High(FOut) downto 0 do
  begin
    V := XOf(FOut[I].K);
    if IsNan(V) then
      Continue;
    X := XToScreen(V);
    Y := FPlot.Top - 3;
    Poly[0] := PointF(X - 5, Y - 5);
    Poly[1] := PointF(X + 5, Y - 5);
    Poly[2] := PointF(X, Y + 3);
    Canvas.Fill.Color := ColSurface;
    Canvas.FillPolygon(Poly, 1);
    Poly[0] := PointF(X - 3.5, Y - 4);
    Poly[1] := PointF(X + 3.5, Y - 4);
    Poly[2] := PointF(X, Y + 1.5);
    if FOut[I].Speed then
      Canvas.Fill.Color := ColSpeed
    else
      Canvas.Fill.Color := ColEle;
    Canvas.FillPolygon(Poly, 1);
  end;
end;

{ Vertical line through point K with a dot on each curve. }
procedure TProfileView.PaintMarker(K: Integer; AColor: TAlphaColor; AThickness: Single);
var
  XV: Double;
  X: Single;

  procedure Dot(Y: Single; AFill: TAlphaColor);
  var
    R: TRectF;
  begin
    R := TRectF.Create(X - 4.5, Y - 4.5, X + 4.5, Y + 4.5);
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := ColSurface;
    Canvas.FillEllipse(R, 1);
    R.Inflate(-1.75, -1.75);
    R.Inflate(0.25, 0.25);
    Canvas.Fill.Color := AFill;
    Canvas.FillEllipse(R, 1);
  end;

begin
  XV := XOf(K);
  if IsNan(XV) then
    Exit;
  X := Round(XToScreen(XV)) + 0.5;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  Canvas.Stroke.Color := AColor;
  Canvas.Stroke.Thickness := AThickness;
  Canvas.DrawLine(PointF(X, FPlot.Top - 2), PointF(X, FPlot.Bottom), 1);
  if FHasEle and not IsNan(FEle[K]) then
    Dot(EleToScreen(FEle[K]), ColEle);
  if FHasSpd and not IsNan(FSpd[K]) then
    Dot(Max(FPlot.Top, SpdToScreen(FSpd[K])), ColSpeed);
end;

procedure TProfileView.PaintTooltip(K: Integer);
const
  RowH = 18.0;
  Pad = 9.0;
var
  U: TUnitInfo;
  Head, SEle, SSpd: string;
  Rows: Integer;
  W, X, Y: Single;
  V: TDateTime;
  R: TRectF;
begin
  U := UnitInfo[FUnits];
  Head := Num(FDist[K] * U.DistFactor, 2) + ' ' + U.DistName;
  if not IsNan(FTime[K]) then
  begin
    // clock time; the date as well when the track runs past midnight
    V := FStartLocal + FTime[K] / SecsPerDay;
    if Trunc(FStartLocal + FTimeMax / SecsPerDay) > Trunc(FStartLocal) then
      Head := Head + '   ·   ' + ClockText(V, True)
    else
      Head := Head + '   ·   ' + ClockText(V, False);
  end;
  if IsNan(FEle[K]) then SEle := 'no elevation' else SEle := FormatEle(FEle[K]);
  if IsNan(FSpd[K]) then SSpd := 'no speed' else SSpd := FormatSpeed(FSpd[K]);

  Rows := 3;
  SetFont(12, True);
  W := Canvas.TextWidth(Head);
  SetFont(12);
  W := Max(W, 18 + Max(Canvas.TextWidth(SEle), Canvas.TextWidth(SSpd)));
  W := W + 2 * Pad;

  X := XToScreen(XOf(K));
  if IsNan(XOf(K)) then
    X := FMouseX;
  R := TRectF.Create(0, 0, W, Rows * RowH + 2 * Pad - 4);
  if X + 12 + W < Width - 4 then
    R.Offset(X + 12, 0)
  else
    R.Offset(X - 12 - W, 0);
  R.Offset(0, Max(2, FPlot.Top + (FPlot.Height - R.Height) / 2));
  if R.Bottom > Height - 2 then
    R.Offset(0, Height - 2 - R.Bottom);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FF000000;
  Canvas.FillRect(TRectF.Create(R.Left, R.Top + 1, R.Right, R.Bottom + 2), 6, 6, AllCorners, 0.10);
  Canvas.Fill.Color := ColSurface;
  Canvas.FillRect(R, 6, 6, AllCorners, 0.97);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  Canvas.Stroke.Color := ColAxis;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(R, 6, 6, AllCorners, 1);

  X := R.Left + Pad;
  Y := R.Top + Pad - 2;
  SetFont(12, True);
  Text(TRectF.Create(X, Y, R.Right, Y + RowH), Head, ColInk, TTextAlign.Leading);
  SetFont(12);
  Y := Y + RowH;
  Canvas.Fill.Color := ColEle;
  Canvas.FillRect(TRectF.Create(X, Y + 5, X + 9, Y + 14), 2, 2, AllCorners, 1);
  Text(TRectF.Create(X + 18, Y, R.Right, Y + RowH), SEle, ColInk, TTextAlign.Leading);
  Y := Y + RowH;
  Canvas.Fill.Color := ColSpeed;
  Canvas.FillRect(TRectF.Create(X - 2, Y + 8, X + 11, Y + 10.5), 1, 1, AllCorners, 1);
  Text(TRectF.Create(X + 18, Y, R.Right, Y + RowH), SSpd, ColInk, TTextAlign.Leading);
end;

end.
