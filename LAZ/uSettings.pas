unit uSettings;

{ What the program remembers between runs: the map source, the view and the
  window.  Kept in settings.json in the user's application data folder
  (on Windows: %APPDATA%\TrackMender).

  The same file is used by the Delphi and the Lazarus project; the few lines
  that differ are marked with FPC. }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

const
  DefTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  DefAttribution = '© OpenStreetMap contributors';
  DefMaxZoom = 19;
  MaxRecent = 5;            // how many recent files are kept

type
  TSettings = class
  public
    // map
    TileUrl: string;          // may use {z} {x} {y}, {s} (a, b or c) and {key} (the API key)
    ApiKey: string;
    MaxZoom: Integer;
    Attribution: string;
    // view
    Graph: Boolean;
    GraphX: string;           // 'distance' or 'time'
    GraphHeight: Integer;     // 0: not saved yet
    Units: string;            // 'imperial', 'metric', 'aviation' or 'marine'
    PointInfo: Boolean;
    SegmentsWidth: Integer;   // 0: not saved yet
    // window
    HasWindowPos: Boolean;
    WinLeft, WinTop, WinWidth, WinHeight: Integer;
    Maximized: Boolean;
    // files opened or saved lately, newest first
    Recent: TArray<string>;
    constructor Create;
    { A missing or damaged file leaves the defaults. }
    procedure Load;
    { If the file cannot be written the settings are simply not remembered. }
    procedure Save;
    { Puts a file at the top of the recent list. }
    procedure AddRecent(const AFileName: string);
    procedure RemoveRecent(const AFileName: string);
  end;

function SettingsFileName: string;

{ The settings of this run, loaded on first use. }
function Settings: TSettings;

implementation

uses
  {$IFDEF FPC}
  SysUtils, Classes, fpjson, jsonparser;
  {$ELSE}
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, System.JSON;
  {$ENDIF}

{$IFDEF FPC}
type
  TJSONValue = TJSONData;
{$ENDIF}

const
  BoolText: array[Boolean] of string = ('false', 'true');

var
  GSettings: TSettings;

function Settings: TSettings;
begin
  if GSettings = nil then
  begin
    GSettings := TSettings.Create;
    GSettings.Load;
  end;
  Result := GSettings;
end;

function SettingsFileName: string;
var
  Folder: string;
begin
  {$IFDEF FPC}
    {$IFDEF WINDOWS}
  Folder := GetEnvironmentVariable('APPDATA');
    {$ELSE}
  Folder := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Folder = '' then
    Folder := IncludeTrailingPathDelimiter(GetUserDir) + '.config';
    {$ENDIF}
  {$ELSE}
  Folder := TPath.GetHomePath;
  {$ENDIF}
  if Folder = '' then
    Folder := ExtractFilePath(ParamStr(0));
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Folder) + 'TrackMender') +
    'settings.json';
end;

{ ---- the file as text (UTF-8, no byte order mark) --------------------------- }

function ReadText(const AName: string): string;
var
  F: TFileStream;
  B: TBytes;
  Skip, Len: Integer;
begin
  Result := '';
  F := TFileStream.Create(AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(B, F.Size);
    if Length(B) > 0 then
      F.ReadBuffer(B[0], Length(B));
  finally
    F.Free;
  end;
  // an editor may have added a byte order mark
  Skip := 0;
  if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    Skip := 3;
  Len := Length(B) - Skip;
  if Len <= 0 then
    Exit;
  {$IFDEF FPC}
  SetString(Result, PAnsiChar(@B[Skip]), Len);
  {$ELSE}
  Result := TEncoding.UTF8.GetString(B, Skip, Len);
  {$ENDIF}
end;

procedure WriteText(const AName, AText: string);
var
  F: TFileStream;
  B: TBytes;
begin
  {$IFDEF FPC}
  SetLength(B, Length(AText));
  if Length(B) > 0 then
    Move(AText[1], B[0], Length(B));
  {$ELSE}
  B := TEncoding.UTF8.GetBytes(AText);
  {$ENDIF}
  F := TFileStream.Create(AName, fmCreate);
  try
    if Length(B) > 0 then
      F.WriteBuffer(B[0], Length(B));
  finally
    F.Free;
  end;
end;

{ ---- reading JSON ----------------------------------------------------------- }

{ The file's top level, nil when it is not usable.  The caller frees it. }
function Parse(const AText: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  try
    {$IFDEF FPC}
    V := GetJSON(AText);
    {$ELSE}
    V := TJSONObject.ParseJSONValue(AText);
    {$ENDIF}
  except
    V := nil;
  end;
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    V.Free;
end;

function Child(AObj: TJSONObject; const AName: string): TJSONValue;
begin
  if AObj = nil then
    Result := nil
  else
    {$IFDEF FPC}
    Result := AObj.Find(AName);
    {$ELSE}
    Result := AObj.GetValue(AName);
    {$ENDIF}
end;

function Group(ARoot: TJSONObject; const AName: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := Child(ARoot, AName);
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    Result := nil;
end;

function Has(AObj: TJSONObject; const AName: string): Boolean;
begin
  Result := Child(AObj, AName) <> nil;
end;

function GetStr(AObj: TJSONObject; const AName, ADefault: string): string;
var
  V: TJSONValue;
begin
  V := Child(AObj, AName);
  Result := ADefault;
  {$IFDEF FPC}
  if (V <> nil) and (V.JSONType = jtString) then
    Result := V.AsString;
  {$ELSE}
  if (V is TJSONString) and not (V is TJSONNumber) then
    Result := TJSONString(V).Value;
  {$ENDIF}
end;

function GetInt(AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  V := Child(AObj, AName);
  Result := ADefault;
  try
    {$IFDEF FPC}
    if (V <> nil) and (V.JSONType = jtNumber) then
      Result := Round(V.AsFloat);
    {$ELSE}
    if V is TJSONNumber then
      Result := Round(TJSONNumber(V).AsDouble);
    {$ENDIF}
  except
    Result := ADefault;
  end;
end;

function GetBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := Child(AObj, AName);
  Result := ADefault;
  {$IFDEF FPC}
  if (V <> nil) and (V.JSONType = jtBoolean) then
    Result := V.AsBoolean;
  {$ELSE}
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean;
  {$ENDIF}
end;

{ A list of texts, e.g. "recent": ["a.gpx", "b.gpx"]. }
function GetList(AObj: TJSONObject; const AName: string): TArray<string>;
var
  V: TJSONValue;
  A: TJSONArray;
  I, N: Integer;
  S: string;
begin
  Result := nil;
  V := Child(AObj, AName);
  if not (V is TJSONArray) then
    Exit;
  A := TJSONArray(V);
  N := 0;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    S := '';
    {$IFDEF FPC}
    if A.Items[I].JSONType = jtString then
      S := A.Items[I].AsString;
    {$ELSE}
    if (A.Items[I] is TJSONString) and not (A.Items[I] is TJSONNumber) then
      S := TJSONString(A.Items[I]).Value;
    {$ENDIF}
    if S <> '' then
    begin
      Result[N] := S;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

{ ---- writing JSON ----------------------------------------------------------- }

{ Written by hand so the file looks the same from both projects and stays
  easy to read: an address keeps its plain slashes. }
function Quote(const S: string): string;
var
  I: Integer;
begin
  Result := '"';
  for I := 1 to Length(S) do
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #0..#31: Result := Result + '\u' + IntToHex(Ord(S[I]), 4);
    else
      Result := Result + S[I];
    end;
  Result := Result + '"';
end;

{ ---- TSettings -------------------------------------------------------------- }

constructor TSettings.Create;
begin
  inherited Create;
  TileUrl := DefTileUrl;
  MaxZoom := DefMaxZoom;
  Attribution := DefAttribution;
  GraphX := 'distance';
  Units := 'imperial';
  PointInfo := True;
end;

procedure TSettings.Load;
var
  Root, G: TJSONObject;
begin
  Root := nil;
  try
    if FileExists(SettingsFileName) then
      Root := Parse(ReadText(SettingsFileName));
  except
    Root := nil;
  end;
  if Root = nil then
    Exit;
  try
    G := Group(Root, 'map');
    TileUrl := Trim(GetStr(G, 'tileUrl', TileUrl));
    if TileUrl = '' then
      TileUrl := DefTileUrl;
    ApiKey := Trim(GetStr(G, 'apiKey', ApiKey));
    MaxZoom := GetInt(G, 'maxZoom', MaxZoom);
    Attribution := GetStr(G, 'attribution', Attribution);

    G := Group(Root, 'view');
    Graph := GetBool(G, 'graph', Graph);
    GraphX := LowerCase(Trim(GetStr(G, 'graphX', GraphX)));
    GraphHeight := GetInt(G, 'graphHeight', GraphHeight);
    Units := LowerCase(Trim(GetStr(G, 'units', Units)));
    PointInfo := GetBool(G, 'pointInfo', PointInfo);
    SegmentsWidth := GetInt(G, 'segmentsWidth', SegmentsWidth);

    G := Group(Root, 'window');
    HasWindowPos := Has(G, 'left') and Has(G, 'top') and Has(G, 'width') and Has(G, 'height');
    WinLeft := GetInt(G, 'left', 0);
    WinTop := GetInt(G, 'top', 0);
    WinWidth := GetInt(G, 'width', 0);
    WinHeight := GetInt(G, 'height', 0);
    Maximized := GetBool(G, 'maximized', Maximized);

    Recent := GetList(Root, 'recent');
    if Length(Recent) > MaxRecent then
      SetLength(Recent, MaxRecent);
  finally
    Root.Free;
  end;
end;

procedure TSettings.Save;
var
  S: string;
  I: Integer;

  procedure Line(const AText: string);
  begin
    S := S + AText + sLineBreak;
  end;

begin
  S := '';
  Line('{');
  Line('  "map": {');
  Line('    "tileUrl": ' + Quote(TileUrl) + ',');
  Line('    "apiKey": ' + Quote(ApiKey) + ',');
  Line('    "maxZoom": ' + IntToStr(MaxZoom) + ',');
  Line('    "attribution": ' + Quote(Attribution));
  Line('  },');
  Line('  "view": {');
  Line('    "graph": ' + BoolText[Graph] + ',');
  Line('    "graphX": ' + Quote(GraphX) + ',');
  Line('    "graphHeight": ' + IntToStr(GraphHeight) + ',');
  Line('    "units": ' + Quote(Units) + ',');
  Line('    "pointInfo": ' + BoolText[PointInfo] + ',');
  Line('    "segmentsWidth": ' + IntToStr(SegmentsWidth));
  Line('  },');
  Line('  "window": {');
  if HasWindowPos then
  begin
    Line('    "left": ' + IntToStr(WinLeft) + ',');
    Line('    "top": ' + IntToStr(WinTop) + ',');
    Line('    "width": ' + IntToStr(WinWidth) + ',');
    Line('    "height": ' + IntToStr(WinHeight) + ',');
  end;
  Line('    "maximized": ' + BoolText[Maximized]);
  Line('  },');
  Line('  "recent": [');
  for I := 0 to High(Recent) do
    if I < High(Recent) then
      Line('    ' + Quote(Recent[I]) + ',')
    else
      Line('    ' + Quote(Recent[I]));
  Line('  ]');
  Line('}');
  try
    if ForceDirectories(ExtractFileDir(SettingsFileName)) then
      WriteText(SettingsFileName, S);
  except
    // not remembered this time
  end;
end;

procedure TSettings.RemoveRecent(const AFileName: string);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(Recent) do
    if not SameText(Recent[I], AFileName) then
    begin
      Recent[N] := Recent[I];
      Inc(N);
    end;
  SetLength(Recent, N);
end;

procedure TSettings.AddRecent(const AFileName: string);
var
  I: Integer;
begin
  if AFileName = '' then
    Exit;
  RemoveRecent(AFileName);
  SetLength(Recent, Length(Recent) + 1);
  for I := High(Recent) downto 1 do
    Recent[I] := Recent[I - 1];
  Recent[0] := AFileName;
  if Length(Recent) > MaxRecent then
    SetLength(Recent, MaxRecent);
end;

initialization

finalization
  FreeAndNil(GSettings);

end.
