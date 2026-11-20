unit uFmx;

{ Lazarus only.  The Delphi edition draws the map and the graph on an FMX
  canvas.  This unit gives the LCL the small part of that canvas the two
  controls use - same type names, same method names, same coordinates - on top
  of BGRABitmap, so uMapView and uProfile stay line for line what they are in
  the Delphi project.

    TControl (FMX)       ->  TFmxControl   a TCustomControl that paints into an
                                           off-screen bitmap through Canvas
    TCanvas, TBitmap     ->  the classes below
    TPathData, TPolygon  ->  the classes below

  Coordinates are FMX coordinates: whole numbers lie on the edges between
  pixels, so a one pixel line from (0.5, 0.5) is crisp.  They are logical
  units (1/96 inch) as in FMX: on a high-DPI screen the canvas scales
  everything, and Width / Height / mouse positions are reported unscaled. }

{$mode delphi}{$H+}{$SCOPEDENUMS ON}

interface

uses
  Classes, SysUtils, Types, Math, LCLType, LCLIntf, LMessages, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes;

type
  TAlphaColor = type Cardinal;   // $AARRGGBB
  TPointF = Types.TPointF;

  TRectF = record
    Left, Top, Right, Bottom: Single;
    class function Create(ALeft, ATop, ARight, ABottom: Single): TRectF; static;
    function Width: Single;
    function Height: Single;
    function Contains(const P: TPointF): Boolean;
    function CenterPoint: TPointF;
    procedure Offset(DX, DY: Single);
    procedure Inflate(DX, DY: Single);
  end;

  TPolygon = array of TPointF;

  TBrushKind = (None, Solid);
  TStrokeCap = (Flat, Round);
  TStrokeJoin = (Miter, Round, Bevel);
  TStrokeDash = (Solid, Dash, Dot);
  TTextAlign = (Center, Leading, Trailing);
  TCorner = (TopLeft, TopRight, BottomLeft, BottomRight);
  TCorners = set of TCorner;
  TFillTextFlag = (RightToLeft);
  TFillTextFlags = set of TFillTextFlag;
  TFontStyle = Graphics.TFontStyle;
  TFontStyles = Graphics.TFontStyles;

  TBrush = class
  public
    Kind: TBrushKind;
    Color: TAlphaColor;
  end;

  TStrokeBrush = class(TBrush)
  public
    Thickness: Single;
    Cap: TStrokeCap;
    Join: TStrokeJoin;
    Dash: TStrokeDash;
  end;

  TFont = class
  public
    Family: string;
    Size: Single;
    Style: TFontStyles;
  end;

  { A decoded image (map tile). }
  TBitmap = class(TBGRABitmap)
  public
    class function CreateFromStream(AStream: TStream): TBitmap;
    function IsEmpty: Boolean;
  end;

  TPathData = class
  private
    FPts: array of TPointF;
    FCount: Integer;
    procedure Add(const P: TPointF);
  public
    procedure Clear;
    procedure MoveTo(const P: TPointF);
    procedure LineTo(const P: TPointF);
    procedure ClosePath;
    function IsEmpty: Boolean;
  end;

  TCanvasSaveState = record
    Clip: TRect;
  end;

  TCanvas = class
  private
    FBmp: TBGRABitmap;
    FScale: Single;
    FFill: TBrush;
    FStroke: TStrokeBrush;
    FFont: TFont;
    function Pix(AColor: TAlphaColor; AOpacity: Single): TBGRAPixel;
    procedure ApplyPen;
    procedure ApplyFont;
  public
    constructor Create;
    destructor Destroy; override;
    function SaveState: TCanvasSaveState;
    procedure RestoreState(const AState: TCanvasSaveState);
    procedure IntersectClipRect(const R: TRectF);

    procedure DrawLine(const A, B: TPointF; AOpacity: Single);
    procedure FillRect(const R: TRectF; XRadius, YRadius: Single; ACorners: TCorners; AOpacity: Single);
    procedure DrawRect(const R: TRectF; XRadius, YRadius: Single; ACorners: TCorners; AOpacity: Single);
    procedure FillEllipse(const R: TRectF; AOpacity: Single);
    procedure DrawEllipse(const R: TRectF; AOpacity: Single);
    procedure DrawPath(APath: TPathData; AOpacity: Single);
    procedure FillPath(APath: TPathData; AOpacity: Single);
    procedure FillPolygon(const APoints: TPolygon; AOpacity: Single);
    procedure DrawPolygon(const APoints: TPolygon; AOpacity: Single);
    procedure DrawBitmap(ABitmap: TBitmap; const ASrc, ADst: TRectF; AOpacity: Single;
      AHighSpeed: Boolean = False);
    procedure FillText(const R: TRectF; const AText: string; AWordWrap: Boolean; AOpacity: Single;
      AFlags: TFillTextFlags; AHorz: TTextAlign; AVert: TTextAlign = TTextAlign.Center);
    function TextWidth(const AText: string): Single;
    function TextHeight(const AText: string): Single;

    property Bitmap: TBGRABitmap read FBmp write FBmp;
    { Device pixels per logical unit. }
    property Scale: Single read FScale write FScale;
    property Fill: TBrush read FFill;
    property Stroke: TStrokeBrush read FStroke;
    property Font: TFont read FFont;
  end;

  { Base of the map and the graph.  Subclasses override Paint and the mouse
    methods exactly as they would on an FMX TControl. }
  TFmxControl = class(TCustomControl)
  private
    FFx: TCanvas;
    FBuf: TBGRABitmap;
    function GetScale: Single;
    function GetLogWidth: Single;
    function GetLogHeight: Single;
    procedure Prepare;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure PaintWindow(DC: HDC); override;
    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;
    // the LCL's integer versions hand over to the FMX style ones below
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); overload; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); overload; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); overload; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseLeave; override;

    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); overload; virtual;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); overload; virtual;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); overload; virtual;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); virtual;
    procedure DoMouseLeave; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function LocalRect: TRectF;
    { As in FMX: asks for a repaint, does not paint right away. }
    procedure Repaint; override;
    property Canvas: TCanvas read FFx;
    { Size in logical units, as FMX reports it. }
    property Width: Single read GetLogWidth;
    property Height: Single read GetLogHeight;
    property SceneScale: Single read GetScale;
  end;

const
  AllCorners = [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight];

function PointF(X, Y: Single): TPointF;
function RectF(ALeft, ATop, ARight, ABottom: Single): TRectF;

implementation

function RectF(ALeft, ATop, ARight, ABottom: Single): TRectF;
begin
  Result := TRectF.Create(ALeft, ATop, ARight, ABottom);
end;

function PointF(X, Y: Single): TPointF;
begin
  Result.X := X;
  Result.Y := Y;
end;

{ TRectF }

class function TRectF.Create(ALeft, ATop, ARight, ABottom: Single): TRectF;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function TRectF.Width: Single;
begin
  Result := Right - Left;
end;

function TRectF.Height: Single;
begin
  Result := Bottom - Top;
end;

function TRectF.Contains(const P: TPointF): Boolean;
begin
  Result := (P.X >= Left) and (P.X < Right) and (P.Y >= Top) and (P.Y < Bottom);
end;

function TRectF.CenterPoint: TPointF;
begin
  Result := PointF((Left + Right) / 2, (Top + Bottom) / 2);
end;

procedure TRectF.Offset(DX, DY: Single);
begin
  Left := Left + DX;
  Right := Right + DX;
  Top := Top + DY;
  Bottom := Bottom + DY;
end;

procedure TRectF.Inflate(DX, DY: Single);
begin
  Left := Left - DX;
  Right := Right + DX;
  Top := Top - DY;
  Bottom := Bottom + DY;
end;

{ TBitmap }

class function TBitmap.CreateFromStream(AStream: TStream): TBitmap;
begin
  Result := TBitmap.Create(AStream);
end;

function TBitmap.IsEmpty: Boolean;
begin
  Result := (Width = 0) or (Height = 0);
end;

{ TPathData }

procedure TPathData.Add(const P: TPointF);
begin
  if FCount = Length(FPts) then
    SetLength(FPts, FCount * 2 + 64);
  FPts[FCount] := P;
  Inc(FCount);
end;

procedure TPathData.Clear;
begin
  FCount := 0;
end;

procedure TPathData.MoveTo(const P: TPointF);
begin
  if FCount > 0 then
    Add(EmptyPointF);   // BGRABitmap: starts a new sub-path
  Add(P);
end;

procedure TPathData.LineTo(const P: TPointF);
begin
  Add(P);
end;

procedure TPathData.ClosePath;
var
  I: Integer;
begin
  // back to the start of the current sub-path
  I := FCount - 1;
  while (I > 0) and not isEmptyPointF(FPts[I - 1]) do
    Dec(I);
  if I >= 0 then
    Add(FPts[I]);
end;

function TPathData.IsEmpty: Boolean;
begin
  Result := FCount < 2;
end;

{ TCanvas }

constructor TCanvas.Create;
begin
  inherited Create;
  FFill := TBrush.Create;
  FFill.Kind := TBrushKind.Solid;
  FFill.Color := $FF000000;
  FStroke := TStrokeBrush.Create;
  FStroke.Kind := TBrushKind.Solid;
  FStroke.Color := $FF000000;
  FStroke.Thickness := 1;
  FFont := TFont.Create;
  FFont.Family := 'Segoe UI';
  FFont.Size := 12;
  FScale := 1;
end;

destructor TCanvas.Destroy;
begin
  FFont.Free;
  FStroke.Free;
  FFill.Free;
  inherited;
end;

function TCanvas.Pix(AColor: TAlphaColor; AOpacity: Single): TBGRAPixel;
begin
  Result := BGRA((AColor shr 16) and $FF, (AColor shr 8) and $FF, AColor and $FF,
    EnsureRange(System.Round((AColor shr 24) * AOpacity), 0, 255));
end;

procedure TCanvas.ApplyPen;
begin
  case FStroke.Dash of
    TStrokeDash.Dash: FBmp.PenStyle := psDash;
    TStrokeDash.Dot: FBmp.PenStyle := psDot;
  else
    FBmp.PenStyle := psSolid;
  end;
  if FStroke.Cap = TStrokeCap.Round then
    FBmp.LineCap := pecRound
  else
    FBmp.LineCap := pecFlat;
  case FStroke.Join of
    TStrokeJoin.Round: FBmp.JoinStyle := pjsRound;
    TStrokeJoin.Bevel: FBmp.JoinStyle := pjsBevel;
  else
    FBmp.JoinStyle := pjsMiter;
  end;
end;

procedure TCanvas.ApplyFont;
begin
  FBmp.FontName := FFont.Family;
  FBmp.FontHeight := System.Round(FFont.Size * FScale);
  FBmp.FontStyle := FFont.Style;
  FBmp.FontQuality := fqSystemClearType;
end;

function TCanvas.SaveState: TCanvasSaveState;
begin
  Result.Clip := FBmp.ClipRect;
end;

procedure TCanvas.RestoreState(const AState: TCanvasSaveState);
begin
  FBmp.ClipRect := AState.Clip;
end;

procedure TCanvas.IntersectClipRect(const R: TRectF);
var
  C, N: TRect;
begin
  C := FBmp.ClipRect;
  N := Rect(Floor(R.Left * FScale), Floor(R.Top * FScale), Ceil(R.Right * FScale), Ceil(R.Bottom * FScale));
  if not Types.IntersectRect(N, C, N) then
    N := Rect(0, 0, 0, 0);
  FBmp.ClipRect := N;
end;

// BGRABitmap puts whole numbers on pixel centres, FMX on pixel edges: hence the -0.5

procedure TCanvas.DrawLine(const A, B: TPointF; AOpacity: Single);
begin
  if FStroke.Kind = TBrushKind.None then
    Exit;
  ApplyPen;
  FBmp.DrawLineAntialias(A.X * FScale - 0.5, A.Y * FScale - 0.5, B.X * FScale - 0.5, B.Y * FScale - 0.5, Pix(FStroke.Color, AOpacity),
    FStroke.Thickness * FScale);
end;

procedure TCanvas.FillRect(const R: TRectF; XRadius, YRadius: Single; ACorners: TCorners; AOpacity: Single);
begin
  if FFill.Kind = TBrushKind.None then
    Exit;
  if (XRadius > 0) and (YRadius > 0) then
    FBmp.FillRoundRectAntialias(R.Left * FScale - 0.5, R.Top * FScale - 0.5, R.Right * FScale - 0.5, R.Bottom * FScale - 0.5, XRadius * FScale, YRadius * FScale,
      Pix(FFill.Color, AOpacity))
  else
    FBmp.FillRectAntialias(R.Left * FScale - 0.5, R.Top * FScale - 0.5, R.Right * FScale - 0.5, R.Bottom * FScale - 0.5,
      Pix(FFill.Color, AOpacity));
end;

procedure TCanvas.DrawRect(const R: TRectF; XRadius, YRadius: Single; ACorners: TCorners; AOpacity: Single);
begin
  if FStroke.Kind = TBrushKind.None then
    Exit;
  ApplyPen;
  if (XRadius > 0) and (YRadius > 0) then
    FBmp.RoundRectAntialias(R.Left * FScale - 0.5, R.Top * FScale - 0.5, R.Right * FScale - 0.5, R.Bottom * FScale - 0.5, XRadius * FScale, YRadius * FScale,
      Pix(FStroke.Color, AOpacity), FStroke.Thickness * FScale)
  else
    FBmp.RectangleAntialias(R.Left * FScale - 0.5, R.Top * FScale - 0.5, R.Right * FScale - 0.5, R.Bottom * FScale - 0.5,
      Pix(FStroke.Color, AOpacity), FStroke.Thickness * FScale);
end;

procedure TCanvas.FillEllipse(const R: TRectF; AOpacity: Single);
begin
  if FFill.Kind = TBrushKind.None then
    Exit;
  FBmp.FillEllipseAntialias((R.Left + R.Right) / 2 * FScale - 0.5, (R.Top + R.Bottom) / 2 * FScale - 0.5,
    R.Width / 2 * FScale, R.Height / 2 * FScale, Pix(FFill.Color, AOpacity));
end;

procedure TCanvas.DrawEllipse(const R: TRectF; AOpacity: Single);
begin
  if FStroke.Kind = TBrushKind.None then
    Exit;
  ApplyPen;
  FBmp.EllipseAntialias((R.Left + R.Right) / 2 * FScale - 0.5, (R.Top + R.Bottom) / 2 * FScale - 0.5,
    R.Width / 2 * FScale, R.Height / 2 * FScale, Pix(FStroke.Color, AOpacity), FStroke.Thickness * FScale);
end;

function Shifted(const APts: array of TPointF; ACount: Integer; AScale: Single): TPolygon;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    if isEmptyPointF(APts[I]) then
      Result[I] := APts[I]
    else
      Result[I] := PointF(APts[I].X * AScale - 0.5, APts[I].Y * AScale - 0.5);
end;

procedure TCanvas.DrawPath(APath: TPathData; AOpacity: Single);
begin
  if (FStroke.Kind = TBrushKind.None) or APath.IsEmpty then
    Exit;
  ApplyPen;
  FBmp.DrawPolyLineAntialias(Shifted(APath.FPts, APath.FCount, FScale), Pix(FStroke.Color, AOpacity),
    FStroke.Thickness * FScale);
end;

procedure TCanvas.FillPath(APath: TPathData; AOpacity: Single);
begin
  if (FFill.Kind = TBrushKind.None) or APath.IsEmpty then
    Exit;
  FBmp.FillPolyAntialias(Shifted(APath.FPts, APath.FCount, FScale), Pix(FFill.Color, AOpacity));
end;

procedure TCanvas.FillPolygon(const APoints: TPolygon; AOpacity: Single);
begin
  if (FFill.Kind = TBrushKind.None) or (Length(APoints) < 3) then
    Exit;
  FBmp.FillPolyAntialias(Shifted(APoints, Length(APoints), FScale), Pix(FFill.Color, AOpacity));
end;

procedure TCanvas.DrawPolygon(const APoints: TPolygon; AOpacity: Single);
begin
  if (FStroke.Kind = TBrushKind.None) or (Length(APoints) < 2) then
    Exit;
  ApplyPen;
  FBmp.DrawPolygonAntialias(Shifted(APoints, Length(APoints), FScale), Pix(FStroke.Color, AOpacity),
    FStroke.Thickness * FScale);
end;

procedure TCanvas.DrawBitmap(ABitmap: TBitmap; const ASrc, ADst: TRectF; AOpacity: Single;
  AHighSpeed: Boolean);
var
  D, S: TRect;
  Part: TBGRACustomBitmap;
  Alpha: Byte;
begin
  D := Rect(System.Round(ADst.Left * FScale), System.Round(ADst.Top * FScale),
    System.Round(ADst.Right * FScale), System.Round(ADst.Bottom * FScale));
  if (D.Right <= D.Left) or (D.Bottom <= D.Top) then
    Exit;
  Alpha := EnsureRange(System.Round(255 * AOpacity), 0, 255);
  S := Rect(System.Round(ASrc.Left), System.Round(ASrc.Top), System.Round(ASrc.Right),
    System.Round(ASrc.Bottom));
  if (S.Left <= 0) and (S.Top <= 0) and (S.Right >= ABitmap.Width) and (S.Bottom >= ABitmap.Height) then
  begin
    if (D.Right - D.Left = ABitmap.Width) and (D.Bottom - D.Top = ABitmap.Height) then
      FBmp.PutImage(D.Left, D.Top, ABitmap, dmDrawWithTransparency, Alpha)
    else
      FBmp.StretchPutImage(D, ABitmap, dmDrawWithTransparency, Alpha);
  end
  else
  begin
    if (S.Right <= S.Left) or (S.Bottom <= S.Top) then
      Exit;
    Part := ABitmap.GetPart(S);
    if Part = nil then
      Exit;
    try
      FBmp.StretchPutImage(D, Part, dmDrawWithTransparency, Alpha);
    finally
      Part.Free;
    end;
  end;
end;

procedure TCanvas.FillText(const R: TRectF; const AText: string; AWordWrap: Boolean; AOpacity: Single;
  AFlags: TFillTextFlags; AHorz: TTextAlign; AVert: TTextAlign);
var
  Sz: TSize;
  X, Y: Single;
begin
  if AText = '' then
    Exit;
  ApplyFont;
  Sz := FBmp.TextSize(AText);
  case AHorz of
    TTextAlign.Center: X := ((R.Left + R.Right) * FScale - Sz.cx) / 2;
    TTextAlign.Trailing: X := R.Right * FScale - Sz.cx;
  else
    X := R.Left * FScale;
  end;
  case AVert of
    TTextAlign.Center: Y := ((R.Top + R.Bottom) * FScale - Sz.cy) / 2;
    TTextAlign.Trailing: Y := R.Bottom * FScale - Sz.cy;
  else
    Y := R.Top * FScale;
  end;
  FBmp.TextOut(System.Round(X), System.Round(Y), AText, Pix(FFill.Color, AOpacity));
end;

function TCanvas.TextWidth(const AText: string): Single;
begin
  ApplyFont;
  Result := FBmp.TextSize(AText).cx / FScale;
end;

function TCanvas.TextHeight(const AText: string): Single;
begin
  ApplyFont;
  Result := FBmp.TextSize(AText).cy / FScale;
end;

{ TFmxControl }

constructor TFmxControl.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  FFx := TCanvas.Create;
  FBuf := TBGRABitmap.Create(1, 1);
  FFx.Bitmap := FBuf;
end;

destructor TFmxControl.Destroy;
begin
  FFx.Free;
  FBuf.Free;
  inherited;
end;

procedure TFmxControl.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // other controls may lie on top of this one, or in it (the info card on the map)
  Params.Style := Params.Style or WS_CLIPSIBLINGS or WS_CLIPCHILDREN;
end;

function TFmxControl.GetScale: Single;
begin
  Result := Font.PixelsPerInch / 96;
  if Result < 0.5 then
    Result := 1;
end;

function TFmxControl.GetLogWidth: Single;
begin
  Result := (inherited Width) / GetScale;
end;

function TFmxControl.GetLogHeight: Single;
begin
  Result := (inherited Height) / GetScale;
end;

procedure TFmxControl.Prepare;
var
  W, H: Integer;
begin
  W := Max(1, inherited Width);
  H := Max(1, inherited Height);
  if (FBuf.Width <> W) or (FBuf.Height <> H) then
    FBuf.SetSize(W, H);
  FBuf.NoClip;
  FFx.Scale := GetScale;
end;

function TFmxControl.LocalRect: TRectF;
begin
  Result := TRectF.Create(0, 0, Width, Height);
end;

procedure TFmxControl.Repaint;
begin
  Invalidate;
end;

procedure TFmxControl.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin
  Message.Result := 1;   // everything is painted by Paint: no flicker
end;

procedure TFmxControl.PaintWindow(DC: HDC);
var
  C: Graphics.TCanvas;
begin
  if (inherited Width < 1) or (inherited Height < 1) then
    Exit;
  Prepare;
  Paint;   // the subclass, drawing through Canvas
  C := Graphics.TCanvas.Create;
  try
    C.Handle := DC;
    FBuf.Draw(C, 0, 0, True);
  finally
    C.Handle := 0;
    C.Free;
  end;
end;

procedure TFmxControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  MouseDown(Button, Shift, X / GetScale, Y / GetScale);
end;

procedure TFmxControl.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  MouseMove(Shift, X / GetScale, Y / GetScale);
end;

procedure TFmxControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  MouseUp(Button, Shift, X / GetScale, Y / GetScale);
end;

function TFmxControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
    MouseWheel(Shift, WheelDelta, Result);
end;

procedure TFmxControl.MouseLeave;
begin
  inherited MouseLeave;
  DoMouseLeave;
end;

procedure TFmxControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
end;

procedure TFmxControl.MouseMove(Shift: TShiftState; X, Y: Single);
begin
end;

procedure TFmxControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
end;

procedure TFmxControl.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
end;

procedure TFmxControl.DoMouseLeave;
begin
end;

end.
