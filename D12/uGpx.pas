unit uGpx;

{ GPX document model. Keep the source XML in slices around track and route
  points so edits can preserve surrounding markup, extensions and whitespace. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;

const
  { How many points a fix changes. }
  FixLevelMin = 0;       // as few as possible
  FixLevelLess = 1;      // half way between the two
  FixLevelDefault = 2;   // every point that looks wrong

type
  EGpxError = class(Exception);

  TGpxPoint = record
    Lat, Lon: Double;
    MX, MY: Double;   // normalised web-mercator position, 0..1
    Raw: string;      // complete source text of the point element
    Sep: string;      // text between this element and the next point / closing tag
    Dirty: Boolean;   // Lat/Lon differ from what Raw says
    Ele: Double;      // metres; NaN when the point has no usable <ele>
    Time: TDateTime;  // UTC; 0 when the point has no usable <time>
    function HasEle: Boolean; inline;
    function HasTime: Boolean; inline;
  end;
  PGpxPoint = ^TGpxPoint;

  TGpxSegment = class
  private
    FPoints: TList<TGpxPoint>;
    function GetCount: Integer; inline;
    function GetPoint(AIndex: Integer): PGpxPoint; inline;
  public
    Name: string;     // name of the owning track / route
    Before: string;   // source text preceding the points container, incl. its open tag
    Head: string;     // text between the open tag and the first point
    constructor Create;
    destructor Destroy; override;
    property Count: Integer read GetCount;
    property Points[AIndex: Integer]: PGpxPoint read GetPoint; default;
  end;

  TGpxEditKind = (ekMove, ekDelete, ekInsert, ekBatch);

  TGpxBatchItem = record
    Seg, Idx: Integer;
    Before, After: TGpxPoint;
  end;

  { What Fix time would do: new times for the points First .. First + High(Times). }
  TGpxTimePlan = record
    Seg, First: Integer;
    Count: Integer;               // how many of them actually change
    Times: TArray<TDateTime>;
    Changed: TArray<Boolean>;
  end;
  PGpxTimePlan = ^TGpxTimePlan;

  { What Fix elevation would do: new elevations for the points First .. First + High(Values). }
  TGpxElePlan = record
    Seg, First: Integer;
    Count: Integer;               // how many of them actually change
    Values: TArray<Double>;       // metres
    Changed: TArray<Boolean>;
  end;

  { What Normalize would repair. Only points that can be repaired from good
    neighbours are counted: a segment without any elevation (or with fewer
    than two timestamps) has nothing to interpolate from and is left alone. }
  TGpxIssues = record
    NoEle: Integer;    // no <ele> at all
    BadEle: Integer;   // out of range, a drop-out to 0, or a single-point spike
    NoTime: Integer;   // no <time>
    BadTime: Integer;  // timestamp out of sequence
    function EleCount: Integer;
    function TimeCount: Integer;
  end;

  TGpxEdit = record
    Kind: TGpxEditKind;
    Seg, Idx: Integer;
    Before, After: TGpxPoint;
    PrevSepOld, PrevSepNew: string;  // separator in front of Idx, before / after the edit
    Nudge: Boolean;
    Batch: TArray<TGpxBatchItem>;    // ekBatch only
  end;

  TGpxDoc = class
  private
    FSegs: TObjectList<TGpxSegment>;
    FTrailer: string;
    FFileName: string;
    FEncoding: TEncoding;
    FOwnsEncoding: Boolean;
    FHasBom: Boolean;
    FEdits: TList<TGpxEdit>;
    FPos: Integer;        // number of edits currently applied
    FSavedPos: Integer;   // value of FPos that matches the file on disk
    FRevision: Integer;
    procedure ScanSeg(ASeg: TGpxSegment; out AEle, ATime: TBytes; out ACum: TArray<Double>);
    procedure Parse(const S: string);
    function BuildText: string;
    procedure Push(const AEdit: TGpxEdit);
    function GetPrevSep(ASeg: TGpxSegment; AIdx: Integer): string;
    procedure SetPrevSep(ASeg: TGpxSegment; AIdx: Integer; const AValue: string);
    function GetSegCount: Integer;
    function GetSegment(AIndex: Integer): TGpxSegment;
    function GetModified: Boolean;
    procedure ReleaseEncoding;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromText(const AText: string);
    function SaveToText: string;
    { Copies the file on disk to <name>.bak, then replaces it. }
    procedure Save;
    { Saves under another name; the document then belongs to that file. }
    procedure SaveAs(const AFileName: string);
    function PointCount: Integer;

    { Live positioning (used while dragging) - not recorded for undo. }
    procedure SetPos(ASeg, AIdx: Integer; AMX, AMY: Double);
    procedure RestorePoint(ASeg, AIdx: Integer; const APoint: TGpxPoint);
    { Records the difference between ABefore and the current point as one undo step. }
    procedure CommitMove(ASeg, AIdx: Integer; const ABefore: TGpxPoint; ANudge: Boolean);
    procedure DeletePoint(ASeg, AIdx: Integer);
    { Inserts a new point behind AIdx.  AFrac (0..1) is how far it sits on the
      way to the following point; used to interpolate elevation and time. }
    procedure InsertPointAfter(ASeg, AIdx: Integer; AMX, AMY, AFrac: Double);

    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Both return the point that should be selected afterwards (AIdx = -1: none). }
    function Undo(out ASeg, AIdx: Integer): Boolean;
    function Redo(out ASeg, AIdx: Integer): Boolean;

    class function ChildText(const APoint: TGpxPoint; const ATag: string): string; static;

    function Analyze: TGpxIssues;
    { Repairs the points counted by Analyze: elevation and/or time is
      interpolated (by distance along the track) between the nearest good
      neighbours.  One undo step.  Returns the number of points changed. }
    function Normalize(AEle, ATime: Boolean): Integer;
    { Fix elevation works on the selected point and any neighbours that are
      also out of line.  Each gets the elevation on the straight line (by
      distance along the track) between the good points either side. }
    function CanFixElevation(ASeg, AIdx: Integer): Boolean;
    function PlanFixElevation(ASeg, AIdx: Integer; out APlan: TGpxElePlan;
      ALevel: Integer = FixLevelDefault): Boolean;
    { Applies the chosen level as one undo step. }
    function FixElevation(ASeg, AIdx: Integer; ALevel: Integer = FixLevelDefault): Boolean;
    { Finds the two timed endpoints of the candidate repair. }
    function FixTimeSpan(ASeg, AIdx: Integer; out AFrom, ATo: Integer;
      ALevel: Integer = FixLevelDefault): Boolean;
    function CanFixTime(ASeg, AIdx: Integer): Boolean;
    { Applies the selected repair range as one undo step. }
    function FixTime(ASeg, AIdx: Integer; ALevel: Integer = FixLevelDefault): Boolean;
    { Plans timestamps between the endpoints in proportion to distance along the segment. }
    function PlanFixTime(ASeg, AIdx: Integer; out APlan: TGpxTimePlan;
      ALevel: Integer = FixLevelDefault): Boolean;
    function PlanSpeed(const APlan: TGpxTimePlan; AIdx: Integer): Double;
    function SpeedWith(ASeg, AIdx: Integer; APlan: PGpxTimePlan): Double;
    { Ground speed at a point in m/s, from the positions and timestamps of its
      neighbours; NaN when unknown. }
    function SpeedAt(ASeg, AIdx: Integer): Double;
    { What the edits applied so far have done (undone steps are not counted). }
    procedure EditCounts(out AMoved, ADeleted, AInserted, ANormalized: Integer);
    { Changes with every edit, undo and redo. }
    property Revision: Integer read FRevision;

    property FileName: string read FFileName;
    property Modified: Boolean read GetModified;
    property SegCount: Integer read GetSegCount;
    property Segments[AIndex: Integer]: TGpxSegment read GetSegment; default;
  end;

function LonToMX(ALon: Double): Double;
function LatToMY(ALat: Double): Double;
function MXToLon(AMX: Double): Double;
function MYToLat(AMY: Double): Double;
{ Great-circle distance in metres. }
function GeoDist(const A, B: TGpxPoint): Double;

const
  MinEleM = -152.4;    // -500 ft
  MaxEleM = 18288.0;   // 60,000 ft

implementation

uses
  System.IOUtils, System.StrUtils, System.DateUtils;

const
  MaxMercLat = 85.05112878;

var
  Inv: TFormatSettings;

{ ---- mercator -------------------------------------------------------------- }

function LonToMX(ALon: Double): Double;
begin
  Result := (ALon + 180) / 360;
end;

function LatToMY(ALat: Double): Double;
var
  S: Double;
begin
  ALat := EnsureRange(ALat, -MaxMercLat, MaxMercLat);
  S := Sin(DegToRad(ALat));
  Result := 0.5 - Ln((1 + S) / (1 - S)) / (4 * Pi);
end;

function MXToLon(AMX: Double): Double;
begin
  Result := AMX * 360 - 180;
end;

function MYToLat(AMY: Double): Double;
begin
  Result := RadToDeg(ArcTan(Sinh(Pi * (1 - 2 * AMY))));
end;

function GeoDist(const A, B: TGpxPoint): Double;
const
  R = 6371008.8;
var
  P1, P2, SLat, SLon, H: Double;
begin
  P1 := DegToRad(A.Lat);
  P2 := DegToRad(B.Lat);
  SLat := Sin((P2 - P1) / 2);
  SLon := Sin(DegToRad(B.Lon - A.Lon) / 2);
  H := SLat * SLat + Cos(P1) * Cos(P2) * SLon * SLon;
  Result := 2 * R * ArcSin(Min(1, Sqrt(H)));
end;

function TGpxPoint.HasEle: Boolean;
begin
  Result := not IsNan(Ele);
end;

function TGpxPoint.HasTime: Boolean;
begin
  Result := Time <> 0;
end;

function TGpxIssues.EleCount: Integer;
begin
  Result := NoEle + BadEle;
end;

function TGpxIssues.TimeCount: Integer;
begin
  Result := NoTime + BadTime;
end;

{ ---- text helpers ---------------------------------------------------------- }

function IsWs(C: Char): Boolean; inline;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function HasNonWs(const S: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if not IsWs(S[I]) then
      Exit(True);
  Result := False;
end;

function TrailingWs(const S: string): string;
var
  I: Integer;
begin
  I := Length(S);
  while (I > 0) and IsWs(S[I]) do
    Dec(I);
  Result := Copy(S, I + 1, MaxInt);
end;

function StartsAt(const S: string; AIndex: Integer; const ASub: string): Boolean;
begin
  Result := (AIndex + Length(ASub) - 1 <= Length(S)) and
    (StrLComp(PChar(S) + AIndex - 1, PChar(ASub), Length(ASub)) = 0);
end;

{ Index of the '>' that closes the tag starting at AStart; 0 if unterminated. }
function FindTagEnd(const S: string; AStart: Integer): Integer;
var
  I, N: Integer;
  Q: Char;
begin
  N := Length(S);
  I := AStart + 1;
  while I <= N do
  begin
    case S[I] of
      '>':
        Exit(I);
      '"', '''':
        begin
          Q := S[I];
          Inc(I);
          while (I <= N) and (S[I] <> Q) do
            Inc(I);
        end;
    end;
    Inc(I);
  end;
  Result := 0;
end;

{ Element name of the tag starting at AStart ('<' or '</'), namespace prefix removed. }
function TagName(const S: string; AStart: Integer; AKeepPrefix: Boolean = False): string;
var
  I, B, N: Integer;
begin
  N := Length(S);
  I := AStart + 1;
  if (I <= N) and (S[I] = '/') then
    Inc(I);
  B := I;
  while (I <= N) and not IsWs(S[I]) and (S[I] <> '>') and (S[I] <> '/') do
  begin
    if (S[I] = ':') and not AKeepPrefix then
      B := I + 1;
    Inc(I);
  end;
  Result := Copy(S, B, I - B);
end;

{ Locates the value of attribute AName in the tag that starts at AStart. }
function FindAttr(const S: string; AStart: Integer; const AName: string;
  out AValStart, AValLen: Integer): Boolean;
var
  I, N, NS, NE: Integer;
  Q: Char;
begin
  Result := False;
  AValStart := 0;
  AValLen := 0;
  N := Length(S);
  I := AStart + 1;
  while (I <= N) and not IsWs(S[I]) and (S[I] <> '>') and (S[I] <> '/') do
    Inc(I);
  while I <= N do
  begin
    while (I <= N) and IsWs(S[I]) do
      Inc(I);
    if (I > N) or (S[I] = '>') or (S[I] = '/') then
      Exit;
    NS := I;
    while (I <= N) and (S[I] <> '=') and (S[I] <> '>') and not IsWs(S[I]) do
      Inc(I);
    NE := I;
    while (I <= N) and IsWs(S[I]) do
      Inc(I);
    if (I > N) or (S[I] <> '=') then
      Exit;
    Inc(I);
    while (I <= N) and IsWs(S[I]) do
      Inc(I);
    if (I > N) or ((S[I] <> '"') and (S[I] <> '''')) then
      Exit;
    Q := S[I];
    Inc(I);
    AValStart := I;
    while (I <= N) and (S[I] <> Q) do
      Inc(I);
    if I > N then
      Exit;
    AValLen := I - AValStart;
    if (NE - NS = Length(AName)) and
      (StrLComp(PChar(S) + NS - 1, PChar(AName), NE - NS) = 0) then
      Exit(True);
    Inc(I);
  end;
end;

function DecodeEntities(const S: string): string;
begin
  Result := S;
  if Pos('&', Result) = 0 then
    Exit;
  Result := Result.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"')
    .Replace('&apos;', '''').Replace('&amp;', '&');
end;

function CoordStr(AValue: Double): string;
begin
  Result := FormatFloat('0.0000000', AValue, Inv);
end;

procedure PatchCoords(var P: TGpxPoint);

  procedure Put(const AName: string; AValue: Double);
  var
    VS, VL: Integer;
  begin
    if FindAttr(P.Raw, 1, AName, VS, VL) then
      P.Raw := Copy(P.Raw, 1, VS - 1) + CoordStr(AValue) + Copy(P.Raw, VS + VL, MaxInt);
  end;

begin
  Put('lat', P.Lat);
  Put('lon', P.Lon);
  P.Dirty := False;
end;

{ yyyy-mm-ddThh:mm:ss[.fff][Z|+hh:mm] -> UTC.  No exceptions on bad input. }
function TryParseIsoTime(const S: string; out ATime: TDateTime): Boolean;
var
  N, I, Sign, OH, OM: Integer;
  Y, Mo, D, H, Mi, Sec: Integer;
  Frac, Scale: Double;
  DatePart, TimePart: TDateTime;

  function Digits(AFrom, ACount: Integer; out AValue: Integer): Boolean;
  var
    K: Integer;
  begin
    AValue := 0;
    if AFrom + ACount - 1 > N then
      Exit(False);
    for K := AFrom to AFrom + ACount - 1 do
    begin
      if (S[K] < '0') or (S[K] > '9') then
        Exit(False);
      AValue := AValue * 10 + Ord(S[K]) - Ord('0');
    end;
    Result := True;
  end;

begin
  Result := False;
  ATime := 0;
  N := Length(S);
  if (N < 19) or (S[5] <> '-') or (S[8] <> '-') or ((S[11] <> 'T') and (S[11] <> ' ')) or
    (S[14] <> ':') or (S[17] <> ':') then
    Exit;
  if not (Digits(1, 4, Y) and Digits(6, 2, Mo) and Digits(9, 2, D) and Digits(12, 2, H) and
    Digits(15, 2, Mi) and Digits(18, 2, Sec)) then
    Exit;
  I := 20;
  Frac := 0;
  if (I <= N) and ((S[I] = '.') or (S[I] = ',')) then
  begin
    Inc(I);
    Scale := 0.1;
    while (I <= N) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      Frac := Frac + (Ord(S[I]) - Ord('0')) * Scale;
      Scale := Scale / 10;
      Inc(I);
    end;
  end;
  OH := 0;
  OM := 0;
  Sign := 0;
  if (I <= N) and ((S[I] = '+') or (S[I] = '-')) then
  begin
    if S[I] = '+' then Sign := 1 else Sign := -1;
    if not Digits(I + 1, 2, OH) then
      Exit;
    Inc(I, 3);
    if (I <= N) and (S[I] = ':') then
      Inc(I);
    if I <= N then
      if not Digits(I, 2, OM) then
        Exit;
  end;
  if Sec > 59 then
    Sec := 59;   // leap second
  if not (TryEncodeDate(Y, Mo, D, DatePart) and TryEncodeTime(H, Mi, Sec, 0, TimePart)) then
    Exit;
  ATime := DatePart + TimePart + Frac / SecsPerDay - Sign * (OH * 60 + OM) / MinsPerDay;
  Result := ATime <> 0;
end;

function IsoTime(ATime: TDateTime; AMillis: Boolean): string;
begin
  if AMillis then
    Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz"Z"', ATime)
  else
    // round to the whole second instead of truncating
    Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ATime + 0.5 / SecsPerDay);
end;

{ Fills Ele / Time from the point's source text. }
procedure ReadMeta(var P: TGpxPoint);
var
  S: string;
begin
  P.Ele := NaN;
  P.Time := 0;
  S := TGpxDoc.ChildText(P, 'ele');
  if (S <> '') and not TryStrToFloat(S, P.Ele, Inv) then
    P.Ele := NaN;
  S := TGpxDoc.ChildText(P, 'time');
  if S <> '' then
    TryParseIsoTime(S, P.Time);
end;

{ Sets the text of a direct child element (ele / time), adding it when absent.
  GPX wants <ele> first and <time> right behind it. }
procedure SetChild(var ARaw: string; const ATag, AValue: string);
var
  P, Q, TE, I: Integer;
  Open, Elem, ChildSep, Tag: string;
begin
  Open := '<' + ATag + '>';
  P := Pos(Open, ARaw);
  if P > 0 then
  begin
    Inc(P, Length(Open));
    Q := PosEx('<', ARaw, P);
    if Q > 0 then
    begin
      ARaw := Copy(ARaw, 1, P - 1) + AValue + Copy(ARaw, Q, MaxInt);
      Exit;
    end;
  end;

  Elem := Open + AValue + '</' + ATag + '>';
  P := Pos('<' + ATag + '/>', ARaw);
  if P > 0 then
  begin
    ARaw := Copy(ARaw, 1, P - 1) + Elem + Copy(ARaw, P + Length(ATag) + 3, MaxInt);
    Exit;
  end;

  TE := FindTagEnd(ARaw, 1);
  if TE = 0 then
    Exit;
  if ARaw[TE - 1] = '/' then
  begin
    // <trkpt .../> becomes an element with content
    Tag := TagName(ARaw, 1, True);
    ARaw := TrimRight(Copy(ARaw, 1, TE - 2)) + '>' + Elem + '</' + Tag + '>';
    Exit;
  end;
  I := TE + 1;
  while (I <= Length(ARaw)) and IsWs(ARaw[I]) do
    Inc(I);
  ChildSep := Copy(ARaw, TE + 1, I - TE - 1);
  P := TE;
  if ATag = 'time' then
  begin
    Q := Pos('</ele>', ARaw);
    if Q > 0 then
      P := Q + 5;
  end;
  ARaw := Copy(ARaw, 1, P) + ChildSep + Elem + Copy(ARaw, P + 1, MaxInt);
end;

{ ---- TGpxSegment ----------------------------------------------------------- }

constructor TGpxSegment.Create;
begin
  inherited Create;
  FPoints := TList<TGpxPoint>.Create;
end;

destructor TGpxSegment.Destroy;
begin
  FPoints.Free;
  inherited;
end;

function TGpxSegment.GetCount: Integer;
begin
  Result := FPoints.Count;
end;

function TGpxSegment.GetPoint(AIndex: Integer): PGpxPoint;
begin
  Result := @FPoints.List[AIndex];
end;

{ ---- TGpxDoc --------------------------------------------------------------- }

constructor TGpxDoc.Create;
begin
  inherited Create;
  FSegs := TObjectList<TGpxSegment>.Create(True);
  FEdits := TList<TGpxEdit>.Create;
  FEncoding := TEncoding.UTF8;
end;

destructor TGpxDoc.Destroy;
begin
  ReleaseEncoding;
  FEdits.Free;
  FSegs.Free;
  inherited;
end;

procedure TGpxDoc.ReleaseEncoding;
begin
  if FOwnsEncoding then
    FEncoding.Free;
  FEncoding := TEncoding.UTF8;
  FOwnsEncoding := False;
end;

function TGpxDoc.GetSegCount: Integer;
begin
  Result := FSegs.Count;
end;

function TGpxDoc.GetSegment(AIndex: Integer): TGpxSegment;
begin
  Result := FSegs[AIndex];
end;

function TGpxDoc.GetModified: Boolean;
begin
  Result := FPos <> FSavedPos;
end;

function TGpxDoc.PointCount: Integer;
var
  Seg: TGpxSegment;
begin
  Result := 0;
  for Seg in FSegs do
    Inc(Result, Seg.Count);
end;

procedure TGpxDoc.LoadFromFile(const AFileName: string);
var
  Bytes: TBytes;
  Enc: TEncoding;
  Ofs, P, Q: Integer;
  Decl, EncName, Text: string;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  ReleaseEncoding;

  Enc := nil;
  Ofs := TEncoding.GetBufferEncoding(Bytes, Enc, TEncoding.UTF8);
  FHasBom := Ofs > 0;
  FEncoding := Enc;

  if not FHasBom then
  begin
    // honour <?xml ... encoding="..."?> for legacy single-byte files
    Decl := LowerCase(TEncoding.ANSI.GetString(Bytes, 0, Min(Length(Bytes), 200)));
    P := Pos('encoding=', Decl);
    if (P > 0) and (P + 9 < Length(Decl)) then
    begin
      Q := PosEx(Decl[P + 9], Decl, P + 10);
      if Q > 0 then
      begin
        EncName := Copy(Decl, P + 10, Q - P - 10);
        if (EncName <> '') and (EncName <> 'utf-8') and (EncName <> 'utf8') then
          try
            FEncoding := TEncoding.GetEncoding(EncName);
            FOwnsEncoding := True;
          except
            FEncoding := TEncoding.UTF8;
          end;
      end;
    end;
  end;

  try
    Text := FEncoding.GetString(Bytes, Ofs, Length(Bytes) - Ofs);
  except
    on EEncodingError do
    begin
      // not valid UTF-8 after all
      ReleaseEncoding;
      FEncoding := TEncoding.ANSI;
      Text := FEncoding.GetString(Bytes, Ofs, Length(Bytes) - Ofs);
    end;
  end;

  LoadFromText(Text);
  FFileName := AFileName;
end;

procedure TGpxDoc.LoadFromText(const AText: string);
begin
  FSegs.Clear;
  FEdits.Clear;
  FPos := 0;
  FSavedPos := 0;
  Inc(FRevision);
  FTrailer := '';
  Parse(AText);
  if FSegs.Count = 0 then
    raise EGpxError.Create('This file contains no tracks or routes.');
end;

procedure TGpxDoc.Parse(const S: string);
var
  N, I, TagEnd, LastEmit, PtStart, SegDepth, VS, VL, J: Integer;
  Stack: TList<string>;
  Seg: TGpxSegment;
  InPt, SelfClose: Boolean;
  Name, SegTag, PtTag, TrackName: string;
  Pt: TGpxPoint;

  procedure AddGap(AUpTo: Integer);
  var
    Gap: string;
  begin
    Gap := Copy(S, LastEmit, AUpTo - LastEmit);
    if Seg.Count = 0 then
      Seg.Head := Seg.Head + Gap
    else
      Seg[Seg.Count - 1].Sep := Gap;
  end;

  procedure AddPoint(AEnd: Integer);
  begin
    Pt.Raw := Copy(S, PtStart, AEnd - PtStart + 1);
    Pt.Sep := '';
    Pt.Dirty := False;
    ReadMeta(Pt);
    Seg.FPoints.Add(Pt);
    LastEmit := AEnd + 1;
  end;

  function SkipTo(const AClose: string; AFrom: Integer): Boolean;
  var
    P: Integer;
  begin
    P := PosEx(AClose, S, AFrom);
    Result := P > 0;
    if Result then
      I := P + Length(AClose);
  end;

  function InnerText(AFrom: Integer): string;
  var
    P: Integer;
  begin
    P := PosEx('<', S, AFrom);
    if P = 0 then
      Exit('');
    Result := DecodeEntities(Trim(Copy(S, AFrom, P - AFrom)));
  end;

begin
  N := Length(S);
  I := 1;
  LastEmit := 1;
  PtStart := 0;
  SegDepth := 0;
  Seg := nil;
  InPt := False;
  TrackName := '';
  Stack := TList<string>.Create;
  try
    while I <= N do
    begin
      if S[I] <> '<' then
      begin
        Inc(I);
        Continue;
      end;

      if StartsAt(S, I, '<!--') then
      begin
        if not SkipTo('-->', I + 4) then Break;
        Continue;
      end;
      if StartsAt(S, I, '<![CDATA[') then
      begin
        if not SkipTo(']]>', I + 9) then Break;
        Continue;
      end;
      if StartsAt(S, I, '<?') then
      begin
        if not SkipTo('?>', I + 2) then Break;
        Continue;
      end;
      if StartsAt(S, I, '<!') then
      begin
        if not SkipTo('>', I + 2) then Break;
        Continue;
      end;

      // ---- closing tag
      if (I < N) and (S[I + 1] = '/') then
      begin
        TagEnd := PosEx('>', S, I);
        if TagEnd = 0 then Break;
        Name := TagName(S, I);
        if InPt then
        begin
          if Name = PtTag then
          begin
            AddPoint(TagEnd);
            InPt := False;
          end;
        end
        else if (Seg <> nil) and (Name = SegTag) and (Stack.Count = SegDepth + 1) then
        begin
          AddGap(I);
          LastEmit := I;
          Seg := nil;
        end;
        if Stack.Count > 0 then
          Stack.Delete(Stack.Count - 1);
        I := TagEnd + 1;
        Continue;
      end;

      // ---- opening tag
      TagEnd := FindTagEnd(S, I);
      if TagEnd = 0 then Break;
      SelfClose := S[TagEnd - 1] = '/';
      Name := TagName(S, I);

      if not InPt then
      begin
        if Seg = nil then
        begin
          if ((Name = 'trkseg') or (Name = 'rte')) and not SelfClose then
          begin
            Seg := TGpxSegment.Create;
            FSegs.Add(Seg);
            Seg.Before := Copy(S, LastEmit, TagEnd + 1 - LastEmit);
            LastEmit := TagEnd + 1;
            SegTag := Name;
            SegDepth := Stack.Count;
            if Name = 'rte' then
            begin
              PtTag := 'rtept';
              Seg.Name := '';
            end
            else
            begin
              PtTag := 'trkpt';
              Seg.Name := TrackName;
            end;
          end
          else if Name = 'trk' then
            TrackName := ''
          else if (Name = 'name') and not SelfClose and (Stack.Count > 0) and
            (Stack.Last = 'trk') then
            TrackName := InnerText(TagEnd + 1);
        end
        else if (Name = PtTag) and (Stack.Count = SegDepth + 1) then
        begin
          AddGap(I);
          PtStart := I;
          Pt := Default(TGpxPoint);
          if not (FindAttr(S, I, 'lat', VS, VL) and
            TryStrToFloat(Trim(Copy(S, VS, VL)), Pt.Lat, Inv) and
            FindAttr(S, I, 'lon', VS, VL) and
            TryStrToFloat(Trim(Copy(S, VS, VL)), Pt.Lon, Inv)) then
          begin
            J := 1 + Length(S.Substring(0, I).Split([#10]));
            raise EGpxError.CreateFmt('Point without valid lat/lon near line %d.', [J - 1]);
          end;
          Pt.MX := LonToMX(Pt.Lon);
          Pt.MY := LatToMY(Pt.Lat);
          if SelfClose then
            AddPoint(TagEnd)
          else
            InPt := True;
        end
        else if (Name = 'name') and (SegTag = 'rte') and not SelfClose and
          (Stack.Count = SegDepth + 1) then
          Seg.Name := InnerText(TagEnd + 1);
      end;

      if not SelfClose then
        Stack.Add(Name);
      I := TagEnd + 1;
    end;

    if InPt or (Seg <> nil) then
      raise EGpxError.Create('The file is truncated or not well-formed XML.');
    FTrailer := Copy(S, LastEmit, MaxInt);
  finally
    Stack.Free;
  end;
end;

function TGpxDoc.BuildText: string;
var
  SB: TStringBuilder;
  Seg: TGpxSegment;
  I: Integer;
  P: PGpxPoint;
begin
  SB := TStringBuilder.Create;
  try
    for Seg in FSegs do
    begin
      SB.Append(Seg.Before).Append(Seg.Head);
      for I := 0 to Seg.Count - 1 do
      begin
        P := Seg[I];
        if P.Dirty then
          PatchCoords(P^);
        SB.Append(P.Raw).Append(P.Sep);
      end;
    end;
    SB.Append(FTrailer);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TGpxDoc.SaveToText: string;
begin
  Result := BuildText;
end;

procedure TGpxDoc.SaveAs(const AFileName: string);
var
  Old: string;
begin
  Old := FFileName;
  FFileName := AFileName;
  try
    Save;
  except
    FFileName := Old;
    raise;
  end;
end;

procedure TGpxDoc.Save;
var
  Bytes: TBytes;
  Tmp: string;
begin
  if FFileName = '' then
    raise EGpxError.Create('No file name.');
  Bytes := FEncoding.GetBytes(BuildText);
  if FHasBom then
    Bytes := FEncoding.GetPreamble + Bytes;

  // Finish writing the temporary file before backing up and replacing the GPX.
  Tmp := FFileName + '.tmp';
  TFile.WriteAllBytes(Tmp, Bytes);
  try
    if TFile.Exists(FFileName) then
    begin
      TFile.Copy(FFileName, FFileName + '.bak', True);
      TFile.Delete(FFileName);
    end;
    TFile.Move(Tmp, FFileName);
  except
    if TFile.Exists(Tmp) and TFile.Exists(FFileName) then
      TFile.Delete(Tmp);
    raise;
  end;
  FSavedPos := FPos;
end;

{ ---- editing --------------------------------------------------------------- }

function TGpxDoc.GetPrevSep(ASeg: TGpxSegment; AIdx: Integer): string;
begin
  if AIdx > 0 then
    Result := ASeg[AIdx - 1].Sep
  else
    Result := ASeg.Head;
end;

procedure TGpxDoc.SetPrevSep(ASeg: TGpxSegment; AIdx: Integer; const AValue: string);
begin
  if AIdx > 0 then
    ASeg[AIdx - 1].Sep := AValue
  else
    ASeg.Head := AValue;
end;

procedure TGpxDoc.Push(const AEdit: TGpxEdit);
begin
  if FPos < FEdits.Count then
  begin
    FEdits.DeleteRange(FPos, FEdits.Count - FPos);
    if FSavedPos > FPos then
      FSavedPos := -1;   // the saved state is no longer reachable
  end;
  FEdits.Add(AEdit);
  Inc(FPos);
  Inc(FRevision);
end;

procedure TGpxDoc.SetPos(ASeg, AIdx: Integer; AMX, AMY: Double);
var
  P: PGpxPoint;
begin
  P := FSegs[ASeg][AIdx];
  AMX := EnsureRange(AMX, 0, 1);
  AMY := EnsureRange(AMY, 0, 1);
  P.MX := AMX;
  P.MY := AMY;
  P.Lon := MXToLon(AMX);
  P.Lat := MYToLat(AMY);
  P.Dirty := True;
end;

procedure TGpxDoc.RestorePoint(ASeg, AIdx: Integer; const APoint: TGpxPoint);
begin
  FSegs[ASeg][AIdx]^ := APoint;
end;

procedure TGpxDoc.CommitMove(ASeg, AIdx: Integer; const ABefore: TGpxPoint; ANudge: Boolean);
var
  E: TGpxEdit;
  Cur: PGpxPoint;
begin
  Cur := FSegs[ASeg][AIdx];
  if (Cur.MX = ABefore.MX) and (Cur.MY = ABefore.MY) then
    Exit;

  // a run of arrow-key nudges on one point collapses into a single undo step
  if ANudge and (FPos = FEdits.Count) and (FPos > 0) and (FPos <> FSavedPos) then
  begin
    E := FEdits[FPos - 1];
    if (E.Kind = ekMove) and E.Nudge and (E.Seg = ASeg) and (E.Idx = AIdx) then
    begin
      E.After := Cur^;
      FEdits[FPos - 1] := E;
      Inc(FRevision);
      Exit;
    end;
  end;

  E := Default(TGpxEdit);
  E.Kind := ekMove;
  E.Seg := ASeg;
  E.Idx := AIdx;
  E.Before := ABefore;
  E.After := Cur^;
  E.Nudge := ANudge;
  Push(E);
end;

procedure TGpxDoc.DeletePoint(ASeg, AIdx: Integer);
var
  Seg: TGpxSegment;
  E: TGpxEdit;
begin
  Seg := FSegs[ASeg];
  E := Default(TGpxEdit);
  E.Kind := ekDelete;
  E.Seg := ASeg;
  E.Idx := AIdx;
  E.Before := Seg[AIdx]^;
  E.PrevSepOld := GetPrevSep(Seg, AIdx);

  // Keep whatever followed the point.  Anything that is not plain whitespace
  // (comments, <extensions>) must survive; whitespace is only taken over when
  // the last point goes, so the closing tag keeps its indentation.
  if HasNonWs(E.Before.Sep) then
    E.PrevSepNew := E.PrevSepOld + E.Before.Sep
  else if (AIdx = Seg.Count - 1) and (AIdx > 0) and not HasNonWs(E.PrevSepOld) then
    E.PrevSepNew := E.Before.Sep
  else
    E.PrevSepNew := E.PrevSepOld;

  Seg.FPoints.Delete(AIdx);
  SetPrevSep(Seg, AIdx, E.PrevSepNew);
  Push(E);
end;

procedure TGpxDoc.InsertPointAfter(ASeg, AIdx: Integer; AMX, AMY, AFrac: Double);
var
  Seg: TGpxSegment;
  A, B: PGpxPoint;
  NewPt: TGpxPoint;
  E: TGpxEdit;
  Tag, ChildSep, CloseSep, Ele, Tm, EA, TA, TB: string;
  FA, FB: Double;
  DA, DB: TDateTime;
  TE, I, J: Integer;
begin
  Seg := FSegs[ASeg];
  A := Seg[AIdx];

  NewPt := Default(TGpxPoint);
  NewPt.MX := EnsureRange(AMX, 0, 1);
  NewPt.MY := EnsureRange(AMY, 0, 1);
  NewPt.Lon := MXToLon(NewPt.MX);
  NewPt.Lat := MYToLat(NewPt.MY);

  // elevation / time: interpolate between the neighbours where possible
  Ele := '';
  Tm := '';
  EA := ChildText(A^, 'ele');
  if AIdx < Seg.Count - 1 then
  begin
    B := Seg[AIdx + 1];
    if TryStrToFloat(EA, FA, Inv) and TryStrToFloat(ChildText(B^, 'ele'), FB, Inv) then
      Ele := FormatFloat('0.##', FA + (FB - FA) * AFrac, Inv);
    TA := ChildText(A^, 'time');
    TB := ChildText(B^, 'time');
    if (TA <> '') and (TB <> '') then
      try
        DA := ISO8601ToDate(TA, True);
        DB := ISO8601ToDate(TB, True);
        Tm := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', DA + (DB - DA) * AFrac);
      except
        Tm := '';
      end;
  end
  else
    Ele := EA;

  // mirror the formatting of the point we are inserting next to
  Tag := TagName(A.Raw, 1, True);
  NewPt.Raw := '<' + Tag + ' lat="' + CoordStr(NewPt.Lat) + '" lon="' + CoordStr(NewPt.Lon) + '"';
  if (Ele = '') and (Tm = '') then
    NewPt.Raw := NewPt.Raw + '/>'
  else
  begin
    TE := FindTagEnd(A.Raw, 1);
    I := TE + 1;
    while (I <= Length(A.Raw)) and IsWs(A.Raw[I]) do
      Inc(I);
    ChildSep := Copy(A.Raw, TE + 1, I - TE - 1);
    J := LastDelimiter('<', A.Raw);
    I := J;
    while (I > 1) and IsWs(A.Raw[I - 1]) do
      Dec(I);
    CloseSep := Copy(A.Raw, I, J - I);
    NewPt.Raw := NewPt.Raw + '>';
    if Ele <> '' then
      NewPt.Raw := NewPt.Raw + ChildSep + '<ele>' + Ele + '</ele>';
    if Tm <> '' then
      NewPt.Raw := NewPt.Raw + ChildSep + '<time>' + Tm + '</time>';
    NewPt.Raw := NewPt.Raw + CloseSep + '</' + Tag + '>';
  end;

  // the new point inherits what followed A; A gets a plain between-points separator
  E := Default(TGpxEdit);
  E.Kind := ekInsert;
  E.Seg := ASeg;
  E.Idx := AIdx + 1;
  E.PrevSepOld := A.Sep;
  E.PrevSepNew := TrailingWs(GetPrevSep(Seg, AIdx));
  NewPt.Sep := A.Sep;
  ReadMeta(NewPt);
  E.After := NewPt;

  A.Sep := E.PrevSepNew;
  Seg.FPoints.Insert(AIdx + 1, NewPt);
  Push(E);
end;

procedure TGpxDoc.EditCounts(out AMoved, ADeleted, AInserted, ANormalized: Integer);
var
  I: Integer;
begin
  AMoved := 0;
  ADeleted := 0;
  AInserted := 0;
  ANormalized := 0;
  for I := 0 to FPos - 1 do
    case FEdits[I].Kind of
      ekMove: Inc(AMoved);
      ekDelete: Inc(ADeleted);
      ekInsert: Inc(AInserted);
      ekBatch: Inc(ANormalized, Length(FEdits[I].Batch));
    end;
end;

function TGpxDoc.CanUndo: Boolean;
begin
  Result := FPos > 0;
end;

function TGpxDoc.CanRedo: Boolean;
begin
  Result := FPos < FEdits.Count;
end;

function TGpxDoc.Undo(out ASeg, AIdx: Integer): Boolean;
var
  E: TGpxEdit;
  Seg: TGpxSegment;
  I: Integer;
begin
  ASeg := -1;
  AIdx := -1;
  Result := CanUndo;
  if not Result then
    Exit;
  Dec(FPos);
  Inc(FRevision);
  E := FEdits[FPos];
  E.Nudge := False;        // never extend a step that has been undone
  FEdits[FPos] := E;
  if E.Kind = ekBatch then
  begin
    for I := 0 to High(E.Batch) do
      FSegs[E.Batch[I].Seg][E.Batch[I].Idx]^ := E.Batch[I].Before;
    Exit;                  // ASeg = -1: the selection is not affected
  end;
  Seg := FSegs[E.Seg];
  ASeg := E.Seg;
  case E.Kind of
    ekMove:
      begin
        Seg[E.Idx]^ := E.Before;
        AIdx := E.Idx;
      end;
    ekDelete:
      begin
        SetPrevSep(Seg, E.Idx, E.PrevSepOld);
        Seg.FPoints.Insert(E.Idx, E.Before);
        AIdx := E.Idx;
      end;
    ekInsert:
      begin
        Seg.FPoints.Delete(E.Idx);
        SetPrevSep(Seg, E.Idx, E.PrevSepOld);
        AIdx := E.Idx - 1;
      end;
  end;
end;

function TGpxDoc.Redo(out ASeg, AIdx: Integer): Boolean;
var
  E: TGpxEdit;
  Seg: TGpxSegment;
  I: Integer;
begin
  ASeg := -1;
  AIdx := -1;
  Result := CanRedo;
  if not Result then
    Exit;
  E := FEdits[FPos];
  Inc(FPos);
  Inc(FRevision);
  if E.Kind = ekBatch then
  begin
    for I := 0 to High(E.Batch) do
      FSegs[E.Batch[I].Seg][E.Batch[I].Idx]^ := E.Batch[I].After;
    Exit;
  end;
  Seg := FSegs[E.Seg];
  ASeg := E.Seg;
  case E.Kind of
    ekMove:
      begin
        Seg[E.Idx]^ := E.After;
        AIdx := E.Idx;
      end;
    ekDelete:
      begin
        Seg.FPoints.Delete(E.Idx);
        SetPrevSep(Seg, E.Idx, E.PrevSepNew);
        AIdx := Min(E.Idx, Seg.Count - 1);
      end;
    ekInsert:
      begin
        SetPrevSep(Seg, E.Idx, E.PrevSepNew);
        Seg.FPoints.Insert(E.Idx, E.After);
        AIdx := E.Idx;
      end;
  end;
end;

class function TGpxDoc.ChildText(const APoint: TGpxPoint; const ATag: string): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos('<' + ATag + '>', APoint.Raw);
  if P = 0 then
    Exit;
  Inc(P, Length(ATag) + 2);
  Q := PosEx('<', APoint.Raw, P);
  if Q > 0 then
    Result := Trim(Copy(APoint.Raw, P, Q - P));
end;

{ ---- elevation / time repair ------------------------------------------------ }

const
  fxOk = 0;
  fxMissing = 1;
  fxBad = 2;
  SpikeM = 30.0;   // an elevation jump smaller than this is never called a spike

{ Flags every point of a segment whose elevation / time should be repaired and
  returns the cumulative distance along the segment. }
procedure TGpxDoc.ScanSeg(ASeg: TGpxSegment; out AEle, ATime: TBytes; out ACum: TArray<Double>);
var
  N, I, J, K, Lo, Hi, Mid, Len, Good, Timed: Integer;
  P, A, B: PGpxPoint;
  D1, D2, V: Double;
  Tails, Prev: TArray<Integer>;
  InRange: TArray<Boolean>;
begin
  N := ASeg.Count;
  SetLength(AEle, N);
  SetLength(ATime, N);
  SetLength(ACum, N);
  if N = 0 then
    Exit;
  ACum[0] := 0;
  for I := 1 to N - 1 do
    ACum[I] := ACum[I - 1] + GeoDist(ASeg[I - 1]^, ASeg[I]^);

  // ---- elevation
  SetLength(InRange, N);
  Good := 0;
  for I := 0 to N - 1 do
  begin
    P := ASeg[I];
    InRange[I] := P.HasEle and (P.Ele >= MinEleM) and (P.Ele <= MaxEleM);
    if InRange[I] then
      Inc(Good);
  end;
  if Good > 0 then
  begin
    for I := 0 to N - 1 do
      if not ASeg[I].HasEle then
        AEle[I] := fxMissing
      else if not InRange[I] then
        AEle[I] := fxBad;

    // single-point spikes: far above (or below) both neighbours, which agree
    // with each other, and steeper than 100 % on both sides
    for I := 1 to N - 2 do
      if InRange[I] and InRange[I - 1] and InRange[I + 1] then
      begin
        P := ASeg[I];
        D1 := P.Ele - ASeg[I - 1].Ele;
        D2 := P.Ele - ASeg[I + 1].Ele;
        if (D1 * D2 > 0) and (Abs(D1) > SpikeM) and (Abs(D2) > SpikeM) and
          (Abs(D1 - D2) < 0.5 * Min(Abs(D1), Abs(D2))) and
          (Abs(D1) > ACum[I] - ACum[I - 1]) and (Abs(D2) > ACum[I + 1] - ACum[I]) then
          AEle[I] := fxBad;
      end;

    // drop-outs: runs of exactly 0 between points that are nowhere near 0
    I := 0;
    while I < N do
    begin
      if (AEle[I] = fxOk) and (ASeg[I].Ele = 0) then
      begin
        J := I;
        while (J + 1 < N) and (AEle[J + 1] = fxOk) and (ASeg[J + 1].Ele = 0) do
          Inc(J);
        A := nil;
        B := nil;
        for K := I - 1 downto 0 do
          if AEle[K] = fxOk then
          begin
            A := ASeg[K];
            Break;
          end;
        for K := J + 1 to N - 1 do
          if AEle[K] = fxOk then
          begin
            B := ASeg[K];
            Break;
          end;
        if ((A <> nil) or (B <> nil)) and ((A = nil) or (Abs(A.Ele) > SpikeM)) and
          ((B = nil) or (Abs(B.Ele) > SpikeM)) then
          for K := I to J do
            AEle[K] := fxBad;
        I := J;
      end;
      Inc(I);
    end;

    // nothing good left to interpolate from: leave the segment alone
    Good := 0;
    for I := 0 to N - 1 do
      if AEle[I] = fxOk then
        Inc(Good);
    if Good = 0 then
      FillChar(AEle[0], N, fxOk);
  end;

  // ---- time: everything outside the longest non-decreasing run of timestamps
  Timed := 0;
  for I := 0 to N - 1 do
    if ASeg[I].HasTime then
      Inc(Timed);
  if Timed < 2 then
    Exit;
  SetLength(Tails, Timed);
  SetLength(Prev, N);
  Len := 0;
  for I := 0 to N - 1 do
  begin
    P := ASeg[I];
    if not P.HasTime then
    begin
      ATime[I] := fxMissing;
      Continue;
    end;
    ATime[I] := fxBad;
    V := P.Time;
    Lo := 0;
    Hi := Len;
    while Lo < Hi do   // first tail that is later than V
    begin
      Mid := (Lo + Hi) div 2;
      if ASeg[Tails[Mid]].Time <= V then
        Lo := Mid + 1
      else
        Hi := Mid;
    end;
    if Lo > 0 then
      Prev[I] := Tails[Lo - 1]
    else
      Prev[I] := -1;
    Tails[Lo] := I;
    if Lo = Len then
      Inc(Len);
  end;
  I := Tails[Len - 1];
  while I >= 0 do
  begin
    ATime[I] := fxOk;
    I := Prev[I];
  end;
  if Len < 2 then
    FillChar(ATime[0], N, fxOk);
end;

function TGpxDoc.Analyze: TGpxIssues;
var
  Seg: TGpxSegment;
  FE, FT: TBytes;
  Cum: TArray<Double>;
  I: Integer;
begin
  Result := Default(TGpxIssues);
  for Seg in FSegs do
  begin
    ScanSeg(Seg, FE, FT, Cum);
    for I := 0 to Seg.Count - 1 do
    begin
      case FE[I] of
        fxMissing: Inc(Result.NoEle);
        fxBad: Inc(Result.BadEle);
      end;
      case FT[I] of
        fxMissing: Inc(Result.NoTime);
        fxBad: Inc(Result.BadTime);
      end;
    end;
  end;
end;

function TGpxDoc.Normalize(AEle, ATime: Boolean): Integer;
var
  S, I, N, A, B, First, Last: Integer;
  Seg: TGpxSegment;
  FE, FT: TBytes;
  Cum: TArray<Double>;
  Items: TList<TGpxBatchItem>;
  Item: TGpxBatchItem;
  E: TGpxEdit;
  Pt: TGpxPoint;
  V, Rate: Double;
  Changed, Millis: Boolean;

  // nearest good neighbours of I in AFlags; -1 when there is none
  procedure Neighbours(const AFlags: TBytes);
  begin
    A := I - 1;
    while (A >= 0) and (AFlags[A] <> fxOk) do
      Dec(A);
    B := I + 1;
    while (B < N) and (AFlags[B] <> fxOk) do
      Inc(B);
    if B >= N then
      B := -1;
  end;

  // position of I between A and B, 0..1
  function Fraction: Double;
  begin
    if Cum[B] > Cum[A] then
      Result := (Cum[I] - Cum[A]) / (Cum[B] - Cum[A])
    else
      Result := (I - A) / (B - A);
  end;

begin
  Items := TList<TGpxBatchItem>.Create;
  try
    for S := 0 to FSegs.Count - 1 do
    begin
      Seg := FSegs[S];
      N := Seg.Count;
      ScanSeg(Seg, FE, FT, Cum);

      // pace used to continue the clock past the first / last good timestamp
      Rate := 0;
      Millis := False;
      if ATime then
      begin
        First := -1;
        Last := -1;
        for I := 0 to N - 1 do
          if (FT[I] = fxOk) and Seg[I].HasTime then
          begin
            if First < 0 then
              First := I;
            Last := I;
            if not Millis and (Pos('.', ChildText(Seg[I]^, 'time')) > 0) then
              Millis := True;
          end;
        if (First >= 0) and (Cum[Last] > Cum[First]) then
          Rate := (Seg[Last].Time - Seg[First].Time) / (Cum[Last] - Cum[First]);
      end;

      for I := 0 to N - 1 do
      begin
        Pt := Seg[I]^;
        Changed := False;

        if AEle and (FE[I] <> fxOk) then
        begin
          Neighbours(FE);
          if (A >= 0) and (B >= 0) then
            V := Seg[A].Ele + (Seg[B].Ele - Seg[A].Ele) * Fraction
          else if A >= 0 then
            V := Seg[A].Ele
          else
            V := Seg[B].Ele;
          SetChild(Pt.Raw, 'ele', FormatFloat('0.##', V, Inv));
          Changed := True;
        end;

        if ATime and (FT[I] <> fxOk) then
        begin
          Neighbours(FT);
          V := 0;
          if (A >= 0) and (B >= 0) then
            V := Seg[A].Time + (Seg[B].Time - Seg[A].Time) * Fraction
          else if A >= 0 then
            V := Seg[A].Time + (Cum[I] - Cum[A]) * Rate
          else if B >= 0 then
            V := Seg[B].Time - (Cum[B] - Cum[I]) * Rate;
          if V <> 0 then
          begin
            SetChild(Pt.Raw, 'time', IsoTime(V, Millis));
            Changed := True;
          end;
        end;

        if Changed then
        begin
          ReadMeta(Pt);
          Item.Seg := S;
          Item.Idx := I;
          Item.Before := Seg[I]^;
          Item.After := Pt;
          Items.Add(Item);
        end;
      end;
    end;

    Result := Items.Count;
    if Result = 0 then
      Exit;
    E := Default(TGpxEdit);
    E.Kind := ekBatch;
    E.Batch := Items.ToArray;
    for I := 0 to High(E.Batch) do
      FSegs[E.Batch[I].Seg][E.Batch[I].Idx]^ := E.Batch[I].After;
    Push(E);
  finally
    Items.Free;
  end;
end;

function EleUsable(P: PGpxPoint): Boolean; inline;
begin
  Result := P.HasEle and (P.Ele >= MinEleM) and (P.Ele <= MaxEleM);
end;

function TGpxDoc.CanFixElevation(ASeg, AIdx: Integer): Boolean;
var
  Seg: TGpxSegment;
  I: Integer;
begin
  Result := False;
  if (ASeg < 0) or (ASeg >= FSegs.Count) then
    Exit;
  Seg := FSegs[ASeg];
  if (AIdx < 0) or (AIdx >= Seg.Count) then
    Exit;
  for I := 0 to Seg.Count - 1 do
    if (I <> AIdx) and EleUsable(Seg[I]) then
      Exit(True);
end;

{ True when the point's elevation is missing, impossible, or well off the
  elevations around it.  "Around it" is the middle value of up to 15 points
  either side, so a short run of bad readings does not hide itself. }
function EleOutOfLine(ASeg: TGpxSegment; AIdx: Integer): Boolean;
const
  Span = 15;
  MinTol = 20.0;      // metres, about 65 ft
  StepFactor = 6;
var
  Vals, Steps: TList<Double>;
  I: Integer;
  Med, Tol: Double;
begin
  if not EleUsable(ASeg[AIdx]) then
    Exit(True);
  Result := False;
  Vals := TList<Double>.Create;
  Steps := TList<Double>.Create;
  try
    for I := Max(0, AIdx - Span) to Min(ASeg.Count - 1, AIdx + Span) do
    begin
      if (I <> AIdx) and EleUsable(ASeg[I]) then
        Vals.Add(ASeg[I].Ele);
      if (I > 0) and EleUsable(ASeg[I]) and EleUsable(ASeg[I - 1]) then
        Steps.Add(Abs(ASeg[I].Ele - ASeg[I - 1].Ele));
    end;
    if Vals.Count < 3 then
      Exit;
    Vals.Sort;
    Med := Vals[Vals.Count div 2];
    // rough ground has bigger steps from point to point: allow for it
    Tol := MinTol;
    if Steps.Count > 0 then
    begin
      Steps.Sort;
      Tol := Max(MinTol, StepFactor * Steps[Steps.Count div 2]);
    end;
    Result := Abs(ASeg[AIdx].Ele - Med) > Tol;
  finally
    Steps.Free;
    Vals.Free;
  end;
end;

function TGpxDoc.PlanFixElevation(ASeg, AIdx: Integer; out APlan: TGpxElePlan; ALevel: Integer): Boolean;
const
  MaxReach = 60;   // how far a run of bad readings is followed
var
  Seg: TGpxSegment;
  Lo, Hi, A, B, I, K, From, Upto: Integer;
  Total, Run, V: Double;
begin
  APlan := Default(TGpxElePlan);
  Result := False;
  if not CanFixElevation(ASeg, AIdx) then
    Exit;
  Seg := FSegs[ASeg];

  // the selected point, plus the out-of-line points that touch it
  Lo := AIdx;
  while (Lo > 0) and (AIdx - Lo < MaxReach) and EleOutOfLine(Seg, Lo - 1) do
    Dec(Lo);
  Hi := AIdx;
  while (Hi < Seg.Count - 1) and (Hi - AIdx < MaxReach) and EleOutOfLine(Seg, Hi + 1) do
    Inc(Hi);

  // the good points either side that the new elevations are taken from
  A := Lo - 1;
  while (A >= 0) and not EleUsable(Seg[A]) do
    Dec(A);
  B := Hi + 1;
  while (B < Seg.Count) and not EleUsable(Seg[B]) do
    Inc(B);
  if B >= Seg.Count then
    B := -1;
  if (A < 0) and (B < 0) then
    Exit;

  // a lower level changes fewer of those points, nearest the selected one first
  From := Lo;
  Upto := Hi;
  if ALevel <= FixLevelMin then
  begin
    From := AIdx;
    Upto := AIdx;
  end
  else if ALevel = FixLevelLess then
  begin
    From := AIdx - (AIdx - Lo) div 2;
    Upto := AIdx + (Hi - AIdx) div 2;
  end;

  Total := 0;
  if (A >= 0) and (B >= 0) then
    for I := A + 1 to B do
      Total := Total + GeoDist(Seg[I - 1]^, Seg[I]^);

  APlan.Seg := ASeg;
  APlan.First := Lo;
  SetLength(APlan.Values, Hi - Lo + 1);
  SetLength(APlan.Changed, Hi - Lo + 1);
  Run := 0;
  if (A >= 0) and (B >= 0) then
    for I := A + 1 to Lo - 1 do
      Run := Run + GeoDist(Seg[I - 1]^, Seg[I]^);
  for I := Lo to Hi do
  begin
    K := I - Lo;
    if (A >= 0) and (B >= 0) then
    begin
      Run := Run + GeoDist(Seg[I - 1]^, Seg[I]^);
      if Total > 0 then
        V := Seg[A].Ele + (Seg[B].Ele - Seg[A].Ele) * Run / Total
      else
        V := (Seg[A].Ele + Seg[B].Ele) / 2;
    end
    else if A >= 0 then
      V := Seg[A].Ele
    else
      V := Seg[B].Ele;
    // as it will be written to the file
    V := Round(V * 100) / 100;
    if (I < From) or (I > Upto) or (Seg[I].HasEle and (Abs(Seg[I].Ele - V) < 0.005)) then
    begin
      // left as it is
      if Seg[I].HasEle then
        APlan.Values[K] := Seg[I].Ele
      else
        APlan.Values[K] := NaN;
    end
    else
    begin
      APlan.Values[K] := V;
      APlan.Changed[K] := True;
      Inc(APlan.Count);
      Result := True;
    end;
  end;
end;

function TGpxDoc.FixElevation(ASeg, AIdx: Integer; ALevel: Integer): Boolean;
var
  Seg: TGpxSegment;
  Plan: TGpxElePlan;
  I, K, N: Integer;
  Pt: TGpxPoint;
  E: TGpxEdit;
begin
  Result := False;
  if not PlanFixElevation(ASeg, AIdx, Plan, ALevel) then
    Exit;
  Seg := FSegs[ASeg];
  E := Default(TGpxEdit);
  E.Kind := ekBatch;
  N := 0;
  for K := 0 to High(Plan.Values) do
  begin
    if not Plan.Changed[K] then
      Continue;
    I := Plan.First + K;
    Pt := Seg[I]^;
    SetChild(Pt.Raw, 'ele', FormatFloat('0.##', Plan.Values[K], Inv));
    ReadMeta(Pt);
    if Pt.Raw = Seg[I].Raw then
      Continue;
    SetLength(E.Batch, N + 1);
    E.Batch[N].Seg := ASeg;
    E.Batch[N].Idx := I;
    E.Batch[N].Before := Seg[I]^;
    E.Batch[N].After := Pt;
    Seg[I]^ := Pt;
    Inc(N);
  end;
  if N = 0 then
    Exit;
  Push(E);
  Result := True;
end;

{ A bad timestamp can distort the measured pace on both sides of a point.
  Look for a run of unusual intervals around the selection before choosing endpoints. }
function TGpxDoc.FixTimeSpan(ASeg, AIdx: Integer; out AFrom, ATo: Integer; ALevel: Integer): Boolean;
const
  Around = 20;      // legs either side used to find the usual pace
  MaxReach = 12;    // how far a disturbed run may extend from AIdx
  Pad = 2;
  MaxPad = 6;
var
  Seg: TGpxSegment;
  Paces, Gaps: TList<Double>;
  Pace, Gap, Want: Double;
  I, Lo, Hi, P, MinFrom, MinTo: Integer;

  // leg K runs from point K to point K + 1
  function Bad(K: Integer): Boolean;
  var
    DT, Want: Double;
  begin
    Result := False;
    if (K < 0) or (K >= Seg.Count - 1) then
      Exit;
    if not (Seg[K].HasTime and Seg[K + 1].HasTime) then
      Exit(True);
    DT := (Seg[K + 1].Time - Seg[K].Time) * SecsPerDay;
    Want := Pace * GeoDist(Seg[K]^, Seg[K + 1]^);
    // off the pace AND off the logger's beat: braking to a stop changes the
    // pace of every leg, but the stamps still come one interval apart
    Result := (DT < 0) or ((Abs(DT - Want) > Max(0.15, 0.15 * Want)) and
      (Abs(DT - Gap) > Max(0.15, 0.15 * Gap)));
  end;

begin
  Result := False;
  if (ASeg < 0) or (ASeg >= FSegs.Count) then
    Exit;
  Seg := FSegs[ASeg];
  if (AIdx <= 0) or (AIdx >= Seg.Count - 1) then
    Exit;

  // usual pace (seconds per metre) of the legs round about
  Pace := -1;
  Gap := 0;
  Paces := TList<Double>.Create;
  Gaps := TList<Double>.Create;
  try
    for I := Max(0, AIdx - Around) to Min(Seg.Count - 2, AIdx + Around - 1) do
      if Seg[I].HasTime and Seg[I + 1].HasTime and (Seg[I + 1].Time > Seg[I].Time) and
        (GeoDist(Seg[I]^, Seg[I + 1]^) > 0.01) then
      begin
        Paces.Add((Seg[I + 1].Time - Seg[I].Time) * SecsPerDay / GeoDist(Seg[I]^, Seg[I + 1]^));
        Gaps.Add((Seg[I + 1].Time - Seg[I].Time) * SecsPerDay);
      end;
    if Paces.Count >= 5 then
    begin
      Paces.Sort;
      Pace := Paces[Paces.Count div 2];
      Gaps.Sort;
      Gap := Gaps[Gaps.Count div 2];   // the logging interval
    end;
  finally
    Paces.Free;
    Gaps.Free;
  end;

  Lo := AIdx;
  Hi := AIdx;
  if Pace > 0 then
  begin
    // a single good leg between two bad ones does not end the run
    while AIdx - Lo < MaxReach do
      if Bad(Lo - 1) then Dec(Lo)
      else if Bad(Lo - 2) then Dec(Lo, 2)
      else Break;
    while Hi - AIdx < MaxReach do
      if Bad(Hi) then Inc(Hi)
      else if Bad(Hi + 1) then Inc(Hi, 2)
      else Break;
  end;
  if (Lo = Hi) and (Pace > 0) then
    Exit;   // nothing here stands out
  if Lo = Hi then
  begin
    // too little to judge the pace by: the point and one either side
    Lo := AIdx - 1;
    Hi := AIdx + 1;
    AFrom := Lo - 1;
    ATo := Hi + 1;
  end
  else
  begin
    // Extend the padding if the interval between endpoints is still over 10% off the estimated pace.
    P := Pad;
    repeat
      AFrom := Max(0, Lo - P);
      ATo := Min(Seg.Count - 1, Hi + P);
      Want := 0;
      for I := AFrom to ATo - 1 do
        Want := Want + Pace * GeoDist(Seg[I]^, Seg[I + 1]^);
      Inc(P);
    until (P > MaxPad) or not (Seg[AFrom].HasTime and Seg[ATo].HasTime) or
      (Abs((Seg[ATo].Time - Seg[AFrom].Time) * SecsPerDay - Want) <= 0.1 * Want);
  end;
  AFrom := Max(0, AFrom);
  ATo := Min(Seg.Count - 1, ATo);
  if ALevel < FixLevelDefault then
  begin
    // a shorter reach: three points round the selected one, or half way to the full run
    MinFrom := Max(AFrom, AIdx - 2);
    MinTo := Min(ATo, AIdx + 2);
    if ALevel <= FixLevelMin then
    begin
      AFrom := MinFrom;
      ATo := MinTo;
    end
    else
    begin
      AFrom := (AFrom + MinFrom) div 2;
      ATo := (ATo + MinTo + 1) div 2;
    end;
  end;
  while (AFrom < AIdx) and not Seg[AFrom].HasTime do
    Inc(AFrom);
  ATo := Min(Seg.Count - 1, ATo);
  while (ATo > AIdx) and not Seg[ATo].HasTime do
    Dec(ATo);
  Result := (AFrom < AIdx) and (ATo > AIdx) and (Seg[ATo].Time > Seg[AFrom].Time);
end;

function TGpxDoc.CanFixTime(ASeg, AIdx: Integer): Boolean;
var
  A, B: Integer;
begin
  Result := FixTimeSpan(ASeg, AIdx, A, B);
end;

function TGpxDoc.PlanFixTime(ASeg, AIdx: Integer; out APlan: TGpxTimePlan; ALevel: Integer): Boolean;
var
  Seg: TGpxSegment;
  A, B, I, K: Integer;
  Total, Run, V: Double;
begin
  APlan := Default(TGpxTimePlan);
  Result := False;
  if not FixTimeSpan(ASeg, AIdx, A, B, ALevel) then
    Exit;
  Seg := FSegs[ASeg];
  Total := 0;
  for I := A + 1 to B do
    Total := Total + GeoDist(Seg[I - 1]^, Seg[I]^);
  APlan.Seg := ASeg;
  APlan.First := A + 1;
  SetLength(APlan.Times, B - A - 1);
  SetLength(APlan.Changed, B - A - 1);
  Run := 0;
  for I := A + 1 to B - 1 do
  begin
    K := I - APlan.First;
    Run := Run + GeoDist(Seg[I - 1]^, Seg[I]^);
    if Total > 0 then
      V := Seg[A].Time + (Seg[B].Time - Seg[A].Time) * Run / Total
    else
      V := Seg[A].Time + (Seg[B].Time - Seg[A].Time) * (I - A) / (B - A);
    // to the millisecond
    V := Round(V * MSecsPerDay) / MSecsPerDay;
    // a point that is already where it belongs is left alone
    if Seg[I].HasTime and (Abs(Seg[I].Time - V) * SecsPerDay < 0.0006) then
      APlan.Times[K] := Seg[I].Time
    else
    begin
      APlan.Times[K] := V;
      APlan.Changed[K] := True;
      Inc(APlan.Count);
      Result := True;
    end;
  end;
end;

function TGpxDoc.FixTime(ASeg, AIdx: Integer; ALevel: Integer): Boolean;
var
  Seg: TGpxSegment;
  Plan: TGpxTimePlan;
  I, K, N: Integer;
  V, Secs: Double;
  Pt: TGpxPoint;
  E: TGpxEdit;
  Millis, SrcMillis: Boolean;
begin
  Result := False;
  if not PlanFixTime(ASeg, AIdx, Plan, ALevel) then
    Exit;
  Seg := FSegs[ASeg];
  SrcMillis := Pos('.', ChildText(Seg[Plan.First - 1]^, 'time')) > 0;
  E := Default(TGpxEdit);
  E.Kind := ekBatch;
  N := 0;
  for K := 0 to High(Plan.Times) do
  begin
    if not Plan.Changed[K] then
      Continue;
    I := Plan.First + K;
    V := Plan.Times[K];
    // whole seconds are usually too coarse for this: keep the fraction when there is one
    Secs := Frac(V) * SecsPerDay;
    Millis := (Abs(Secs - Round(Secs)) > 0.0005) or SrcMillis;
    Pt := Seg[I]^;
    SetChild(Pt.Raw, 'time', IsoTime(V, Millis));
    ReadMeta(Pt);
    if Pt.Raw = Seg[I].Raw then
      Continue;
    SetLength(E.Batch, N + 1);
    E.Batch[N].Seg := ASeg;
    E.Batch[N].Idx := I;
    E.Batch[N].Before := Seg[I]^;
    E.Batch[N].After := Pt;
    Seg[I]^ := Pt;
    Inc(N);
  end;
  if N = 0 then
    Exit;
  Push(E);
  Result := True;
end;

function TGpxDoc.SpeedAt(ASeg, AIdx: Integer): Double;
begin
  Result := SpeedWith(ASeg, AIdx, nil);
end;

function TGpxDoc.PlanSpeed(const APlan: TGpxTimePlan; AIdx: Integer): Double;
begin
  Result := SpeedWith(APlan.Seg, AIdx, @APlan);
end;

{ Speed at a point: the way from the point before to the point after, over the
  time between those two.  With a plan, as it would be once the plan is applied. }
function TGpxDoc.SpeedWith(ASeg, AIdx: Integer; APlan: PGpxTimePlan): Double;
var
  Seg: TGpxSegment;
  A, B: Integer;
  DT, D: Double;

  function InPlan(K: Integer): Boolean;
  begin
    Result := (APlan <> nil) and (K >= APlan.First) and (K < APlan.First + Length(APlan.Times));
  end;

  function Timed(K: Integer): Boolean;
  begin
    Result := InPlan(K) or Seg[K].HasTime;
  end;

  function TimeOf(K: Integer): TDateTime;
  begin
    if InPlan(K) then
      Result := APlan.Times[K - APlan.First]
    else
      Result := Seg[K].Time;
  end;

begin
  Result := NaN;
  Seg := FSegs[ASeg];
  if not Timed(AIdx) then
    Exit;
  A := AIdx;
  B := AIdx;
  if (AIdx > 0) and Timed(AIdx - 1) then
    A := AIdx - 1;
  if (AIdx < Seg.Count - 1) and Timed(AIdx + 1) then
    B := AIdx + 1;
  if A = B then
    Exit;
  DT := (TimeOf(B) - TimeOf(A)) * SecsPerDay;
  if DT < 0.0005 then
    Exit;
  D := 0;
  if A < AIdx then
    D := D + GeoDist(Seg[A]^, Seg[AIdx]^);
  if B > AIdx then
    D := D + GeoDist(Seg[AIdx]^, Seg[B]^);
  Result := D / DT;
end;

initialization
  Inv := TFormatSettings.Invariant;

end.
