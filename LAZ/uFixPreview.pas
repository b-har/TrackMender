unit uFixPreview;

{ Preview for Fix Timestamps and Fix Elevation. The form holds the layout,
  and the paint handler draws the before / after chart and per-point changes. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Types, Classes, Math, StrUtils,
  Forms, Controls, Graphics, StdCtrls, ExtCtrls, Buttons, BGRABitmap, BGRABitmapTypes, uFmx;

type
  TPreviewPoint = record
    Number: Integer;         // 1-based point number in its segment
    Before, After: Double;   // charted value (speed or elevation) in display units, NaN when there is none
    Shift: Double;           // how far the point's timestamp or elevation moves
    Changed: Boolean;
    Selected: Boolean;
  end;

  { What is being fixed, for the wording on the form. }
  TPreviewInfo = record
    Caption: string;         // window title
    What: string;            // 'timestamp' or 'elevation'
    ValueUnit: string;       // unit of the chart, e.g. mph or ft
    ShiftUnit: string;       // unit of the change row, e.g. s or ft
    ShiftDecimals: Integer;
  end;

  { Builds a preview for the requested fix level. }
  TPreviewSource = function(ALevel: Integer): TArray<TPreviewPoint> of object;

  TfrmFixPreview = class(TForm)
    lblSummary: TLabel;
    lblNote: TLabel;
    rectChart: TPanel;
    pbChart: TPaintBox;
    layButtons: TPanel;
    layLegend: TPanel;
    lineNow: TShape;
    lblNow: TLabel;
    lineAfter: TShape;
    lblAfter: TLabel;
    rectBand: TShape;
    lblBand: TLabel;
    lblLevel: TLabel;
    btnLevelMin: TSpeedButton;
    btnLevelMid: TSpeedButton;
    btnLevelFull: TSpeedButton;
    btnOK: TButton;
    btnCancel: TButton;
    procedure btnLevelClick(Sender: TObject);
    procedure pbChartPaint(Sender: TObject);
  private
    FPoints: TArray<TPreviewPoint>;
    FInfo: TPreviewInfo;
    FSource: TPreviewSource;
    FLevel: Integer;
    procedure SetLevel(ALevel: Integer; const APoints: TArray<TPreviewPoint>);
    procedure SetupLevels;
    procedure PaintChart(Canvas: TCanvas; AWidth, AHeight: Single);
  public
    { Returns True on Accept and reports the chosen fix level in ALevel. }
    class function Confirm(ASource: TPreviewSource; const AInfo: TPreviewInfo;
      out ALevel: Integer): Boolean;
    procedure SetPoints(const APoints: TArray<TPreviewPoint>);
  end;

var
  frmFixPreview: TfrmFixPreview;

implementation

{$R *.lfm}

const
  ColNow = $FF8A8F98;
  ColAfter = $FFEB6834;
  ColBand = $FFFDF0D5;
  ColGrid = $FFE6E8EC;
  ColText = $FF30343A;
  ColDim = $FF8A8F98;
  ColSel = $FF2A78D6;

class function TfrmFixPreview.Confirm(ASource: TPreviewSource; const AInfo: TPreviewInfo;
  out ALevel: Integer): Boolean;
var
  F: TfrmFixPreview;
begin
  ALevel := 2;
  F := TfrmFixPreview.Create(Application);
  try
    F.FSource := ASource;
    F.FInfo := AInfo;
    F.Caption := AInfo.Caption;
    F.lblBand.Caption := UpperCase(Copy(AInfo.What, 1, 1)) + Copy(AInfo.What, 2, MaxInt) + ' changes';
    F.SetupLevels;
    Result := F.ShowModal = mrOk;
    ALevel := F.FLevel;
  finally
    F.Free;
  end;
end;

{ Label the level buttons with the number of points they would change.
  A level that changes the same points as a bigger one is not offered. }
procedure TfrmFixPreview.SetupLevels;
var
  Count: array[0..2] of Integer;
  Pts: TArray<TPreviewPoint>;
  L, I: Integer;

begin
  for L := 0 to 2 do
  begin
    Count[L] := 0;
    Pts := FSource(L);
    for I := 0 to High(Pts) do
      if Pts[I].Changed then
        Inc(Count[L]);
  end;
  btnLevelMin.Caption := Format('Minimum (%d)', [Count[0]]);
  btnLevelMid.Caption := Format('Less (%d)', [Count[1]]);
  btnLevelFull.Caption := Format('Default (%d)', [Count[2]]);
  btnLevelMin.Visible := (Count[0] > 0) and (Count[0] < Count[2]);
  btnLevelMid.Visible := (Count[1] > Count[0]) and (Count[1] < Count[2]);
  btnLevelFull.Visible := btnLevelMin.Visible or btnLevelMid.Visible;
  lblLevel.Visible := btnLevelFull.Visible;
  // The last pass already built the full preview.
  SetLevel(High(Count), Pts);
end;

procedure TfrmFixPreview.btnLevelClick(Sender: TObject);
var
  Level: Integer;
begin
  Level := (Sender as TComponent).Tag;
  SetLevel(Level, FSource(Level));
end;

procedure TfrmFixPreview.SetLevel(ALevel: Integer; const APoints: TArray<TPreviewPoint>);
begin
  FLevel := ALevel;
  btnLevelMin.Down := ALevel = 0;
  btnLevelMid.Down := ALevel = 1;
  btnLevelFull.Down := ALevel = 2;
  SetPoints(APoints);
end;

procedure TfrmFixPreview.SetPoints(const APoints: TArray<TPreviewPoint>);
var
  I, N, First, Last: Integer;
  MaxShift: Double;
begin
  FPoints := APoints;
  N := 0;
  First := 0;
  Last := 0;
  MaxShift := 0;
  for I := 0 to High(FPoints) do
    if FPoints[I].Changed then
    begin
      if N = 0 then
        First := FPoints[I].Number;
      Last := FPoints[I].Number;
      Inc(N);
      MaxShift := Max(MaxShift, Abs(FPoints[I].Shift));
    end;
  if N = 1 then
    lblSummary.Caption := Format('Proposed %s change at point %d', [FInfo.What, First])
  else
    lblSummary.Caption := Format('%d proposed %s changes (points %d to %d)', [N, FInfo.What, First, Last]);
  lblNote.Caption := Format('Largest change: %s %s. Only %ss change. Undo restores them in one step.',
    [FormatFloat(IfThen(FInfo.ShiftDecimals > 0, '#,##0.0', '#,##0'), MaxShift), FInfo.ShiftUnit, FInfo.What]);
  pbChart.Repaint;
end;

procedure TfrmFixPreview.pbChartPaint(Sender: TObject);
var
  Bmp: TBGRABitmap;
  C: TCanvas;
  Scale: Single;
begin
  if (pbChart.Width < 1) or (pbChart.Height < 1) then
    Exit;
  Scale := Font.PixelsPerInch / 96;
  Bmp := TBGRABitmap.Create(pbChart.Width, pbChart.Height, BGRAWhite);
  C := TCanvas.Create;
  try
    C.Bitmap := Bmp;
    C.Scale := Scale;
    PaintChart(C, pbChart.Width / Scale, pbChart.Height / Scale);
    Bmp.Draw(pbChart.Canvas, 0, 0, True);
  finally
    C.Free;
    Bmp.Free;
  end;
end;

procedure TfrmFixPreview.PaintChart(Canvas: TCanvas; AWidth, AHeight: Single);
const
  LeftW = 62;       // row titles and axis labels
  RowH = 18;
  Rows = 4;         // point, now, after, change
  TopPad = 26;   // room for the unit above the top grid line
var
  N, I, Step: Integer;
  W, H, ColW, PlotB, Lo, Hi, Range, Tick, V: Double;
  R: TRectF;

  function XOf(K: Integer): Single;
  begin
    Result := LeftW + (K + 0.5) * ColW;
  end;

  function YOf(AValue: Double): Single;
  begin
    Result := PlotB - (AValue - Lo) / (Hi - Lo) * (PlotB - TopPad);
  end;

  procedure Text(const S: string; const ARect: TRectF; AColor: TAlphaColor; AAlign: TTextAlign;
    ABold: Boolean = False);
  begin
    Canvas.Fill.Color := AColor;
    if ABold then
      Canvas.Font.Style := [TFontStyle.fsBold]
    else
      Canvas.Font.Style := [];
    Canvas.FillText(ARect, S, False, 1, [], AAlign, TTextAlign.Center);
  end;

  procedure Series(AAfter: Boolean);
  var
    K: Integer;
    Prev: TPointF;
    HavePrev: Boolean;
    P: TPointF;
    Val: Double;
  begin
    HavePrev := False;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Dash := TStrokeDash.Solid;
    if AAfter then
    begin
      Canvas.Stroke.Color := ColAfter;
      Canvas.Stroke.Thickness := 2;
    end
    else
    begin
      Canvas.Stroke.Color := ColNow;
      Canvas.Stroke.Thickness := 1.5;
    end;
    for K := 0 to N - 1 do
    begin
      if AAfter then Val := FPoints[K].After else Val := FPoints[K].Before;
      if IsNan(Val) then
      begin
        HavePrev := False;
        Continue;
      end;
      P := PointF(XOf(K), YOf(Val));
      if HavePrev then
        Canvas.DrawLine(Prev, P, 1);
      Prev := P;
      HavePrev := True;
    end;
    for K := 0 to N - 1 do
    begin
      if AAfter then Val := FPoints[K].After else Val := FPoints[K].Before;
      if IsNan(Val) then
        Continue;
      // after-dots only where the value is really different
      if AAfter and (IsNan(FPoints[K].Before) or (Abs(Val - FPoints[K].Before) >= 0.05)) then
      begin
        Canvas.Fill.Color := ColAfter;
        Canvas.FillEllipse(RectF(XOf(K) - 3.5, YOf(Val) - 3.5, XOf(K) + 3.5, YOf(Val) + 3.5), 1);
      end
      else if not AAfter then
      begin
        Canvas.Fill.Color := ColNow;
        Canvas.FillEllipse(RectF(XOf(K) - 2.5, YOf(Val) - 2.5, XOf(K) + 2.5, YOf(Val) + 2.5), 1);
      end;
    end;
  end;

  function Val(AValue: Double): string;
  begin
    if IsNan(AValue) then
      Result := '–'
    else
      Result := Format('%.0f', [AValue]);
  end;

begin
  N := Length(FPoints);
  W := AWidth;
  H := AHeight;
  if (N = 0) or (W < LeftW + 40) or (H < Rows * RowH + 60) then
    Exit;
  ColW := (W - LeftW) / N;
  PlotB := H - Rows * RowH - 12;

  // value range over both series
  Lo := MaxDouble;
  Hi := -MaxDouble;
  for I := 0 to N - 1 do
  begin
    if not IsNan(FPoints[I].Before) then
    begin
      Lo := Min(Lo, FPoints[I].Before);
      Hi := Max(Hi, FPoints[I].Before);
    end;
    if not IsNan(FPoints[I].After) then
    begin
      Lo := Min(Lo, FPoints[I].After);
      Hi := Max(Hi, FPoints[I].After);
    end;
  end;
  if Lo > Hi then
  begin
    Lo := 0;
    Hi := 1;
  end;
  Range := Max(Hi - Lo, 1);
  Tick := Power(10, Floor(Log10(Range / 4)));
  if Range / 4 / Tick >= 5 then Tick := Tick * 5
  else if Range / 4 / Tick >= 2 then Tick := Tick * 2;
  // speeds and ordinary elevations start no lower than zero
  if Lo >= 0 then
    Lo := Max(0, Floor((Lo - Range * 0.08) / Tick) * Tick)
  else
    Lo := Floor((Lo - Range * 0.08) / Tick) * Tick;
  Hi := Ceil((Hi + Range * 0.08) / Tick) * Tick;

  Canvas.Font.Size := 11;

  // band behind the points that change
  Canvas.Fill.Kind := TBrushKind.Solid;
  for I := 0 to N - 1 do
    if FPoints[I].Changed then
    begin
      Canvas.Fill.Color := ColBand;
      Canvas.FillRect(RectF(LeftW + I * ColW, 0, LeftW + (I + 1) * ColW + 0.5, H), 0, 0, [], 1);
    end;

  // grid and axis labels
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 1;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  V := Lo;
  while V <= Hi + Tick * 0.01 do
  begin
    Canvas.Stroke.Color := ColGrid;
    Canvas.DrawLine(PointF(LeftW, Round(YOf(V)) + 0.5), PointF(W, Round(YOf(V)) + 0.5), 1);
    Text(Format('%.0f', [V]), RectF(0, YOf(V) - 9, LeftW - 8, YOf(V) + 9), ColDim, TTextAlign.Trailing);
    V := V + Tick;
  end;
  Text(FInfo.ValueUnit, RectF(0, 0, LeftW - 8, 14), ColDim, TTextAlign.Trailing);

  // the selected point
  for I := 0 to N - 1 do
    if FPoints[I].Selected then
    begin
      Canvas.Stroke.Color := ColSel;
      Canvas.Stroke.Dash := TStrokeDash.Dash;
      Canvas.DrawLine(PointF(Round(XOf(I)) + 0.5, TopPad), PointF(Round(XOf(I)) + 0.5, PlotB), 0.8);
      Canvas.Stroke.Dash := TStrokeDash.Solid;
    end;

  Series(False);
  Series(True);

  // table: one column per point
  R := RectF(0, PlotB + 12, LeftW - 8, PlotB + 12 + RowH);
  Text('Point', R, ColDim, TTextAlign.Trailing);
  R.Offset(0, RowH);
  Text('Now', R, ColDim, TTextAlign.Trailing);
  R.Offset(0, RowH);
  Text('After', R, ColAfter, TTextAlign.Trailing);
  R.Offset(0, RowH);
  Text('±' + ' ' + FInfo.ShiftUnit, R, ColDim, TTextAlign.Trailing);

  Canvas.Font.Size := 10.5;
  Step := Max(1, Ceil(34 / ColW));   // thin the point numbers out when columns are narrow
  for I := 0 to N - 1 do
  begin
    R := RectF(LeftW + I * ColW - 20, PlotB + 12, LeftW + (I + 1) * ColW + 20, PlotB + 12 + RowH);
    if FPoints[I].Selected then
      Text(IntToStr(FPoints[I].Number), R, ColSel, TTextAlign.Center, True)
    else if (I mod Step = 0) and ((Step = 1) or not ((I + 1 < N) and FPoints[I + 1].Selected) and
      not ((I > 0) and FPoints[I - 1].Selected)) then
      Text(IntToStr(FPoints[I].Number), R, ColDim, TTextAlign.Center);
    if ColW < 20 then
      Continue;   // too tight for values: the chart has to do
    R.Offset(0, RowH);
    Text(Val(FPoints[I].Before), R, ColText, TTextAlign.Center);
    R.Offset(0, RowH);
    if IsNan(FPoints[I].After) or IsNan(FPoints[I].Before) or
      (Abs(FPoints[I].After - FPoints[I].Before) >= 0.5) then
      Text(Val(FPoints[I].After), R, ColAfter, TTextAlign.Center, True)
    else
      Text(Val(FPoints[I].After), R, ColDim, TTextAlign.Center);
    R.Offset(0, RowH);
    if FPoints[I].Changed and (ColW >= 30) then
      Text(IfThen(FPoints[I].Shift >= 0, '+', '−') +
        Format('%.*f', [FInfo.ShiftDecimals, Abs(FPoints[I].Shift)]), R, ColText, TTextAlign.Center);
  end;
end;

end.
