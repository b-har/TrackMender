unit uCompat;

{ Lazarus only.  A few names from the Delphi run-time library that Free Pascal
  3.2 does not have, so the shared units can use them unchanged. }

{$mode delphi}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Classes, SysUtils, DateUtils;

type
  { System.IOUtils.TFile, the part that is used. }
  TFile = record
    class function Exists(const AName: string): Boolean; static;
    class function ReadAllBytes(const AName: string): TBytes; static;
    class procedure WriteAllBytes(const AName: string; const ABytes: TBytes); static;
    class procedure Copy(const ASource, ADest: string; AOverwrite: Boolean); static;
    class procedure Move(const ASource, ADest: string); static;
    class procedure Delete(const AName: string); static;
  end;

  { System.IOUtils.TPath, the part that is used. }
  TPath = record
    class function Combine(const A, B: string): string; static;
    { Where per-user caches go: %LOCALAPPDATA% on Windows, ~/.cache elsewhere. }
    class function GetCachePath: string; static;
  end;

  { TFormatSettings.Invariant }
  TFormatSettingsHelper = record helper for TFormatSettings
    class function Invariant: TFormatSettings; static;
  end;

  { System.Hash.THashBobJenkins: only used to turn a tile URL into a folder
    name, so any stable hash will do (the value differs from Delphi's). }
  THashBobJenkins = record
    class function GetHashString(const S: string): string; static;
  end;

  { System.SyncObjs.TSemaphore: a counting semaphore. }
  TSemaphore = class
  private
    FLock: TRTLCriticalSection;
    FEvent: PRTLEvent;
    FCount: Integer;
  public
    constructor Create(AAttributes: Pointer; AInitial, AMax: Integer; const AName: string);
    destructor Destroy; override;
    procedure Release(ACount: Integer = 1);
    { True when a count was taken, False on time-out. }
    function WaitFor(ATimeoutMs: Cardinal): Boolean;
  end;

  { System.DateUtils.TTimeZone: UTC to local time, with the daylight saving
    rule that applied on that date (not today's). }
  TTimeZone = record
    class function Local: TTimeZone; static;
    function ToLocalTime(const AUtc: TDateTime): TDateTime;
  end;

{ System.Character: Char.ToUpper for the plain ASCII range. }
function UpChar(C: WideChar): Char;

implementation

class function TFile.Exists(const AName: string): Boolean;
begin
  Result := FileExists(AName);
end;

class function TFile.ReadAllBytes(const AName: string): TBytes;
var
  F: TFileStream;
begin
  Result := nil;
  F := TFileStream.Create(AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

class procedure TFile.WriteAllBytes(const AName: string; const ABytes: TBytes);
var
  F: TFileStream;
begin
  F := TFileStream.Create(AName, fmCreate);
  try
    if Length(ABytes) > 0 then
      F.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    F.Free;
  end;
end;

class procedure TFile.Copy(const ASource, ADest: string; AOverwrite: Boolean);
var
  Src, Dst: TFileStream;
begin
  if not AOverwrite and FileExists(ADest) then
    raise EInOutError.CreateFmt('%s already exists', [ADest]);
  Src := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  try
    Dst := TFileStream.Create(ADest, fmCreate);
    try
      Dst.CopyFrom(Src, 0);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
end;

class procedure TFile.Move(const ASource, ADest: string);
begin
  if not RenameFile(ASource, ADest) then
    raise EInOutError.CreateFmt('Cannot rename %s to %s', [ASource, ADest]);
end;

class procedure TFile.Delete(const AName: string);
begin
  if FileExists(AName) and not DeleteFile(AName) then
    raise EInOutError.CreateFmt('Cannot delete %s', [AName]);
end;

class function TPath.Combine(const A, B: string): string;
begin
  if A = '' then
    Result := B
  else
    Result := IncludeTrailingPathDelimiter(A) + B;
end;

class function TPath.GetCachePath: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  if Result = '' then
    Result := GetTempDir(False);
  {$ELSE}
  Result := GetEnvironmentVariable('XDG_CACHE_HOME');
  if Result = '' then
    Result := IncludeTrailingPathDelimiter(GetUserDir) + '.cache';
  {$ENDIF}
  Result := ExcludeTrailingPathDelimiter(Result);
end;

class function TFormatSettingsHelper.Invariant: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
  Result.DateSeparator := '/';
  Result.TimeSeparator := ':';
  Result.ShortDateFormat := 'mm/dd/yyyy';
  Result.LongTimeFormat := 'hh:nn:ss';
  Result.ShortTimeFormat := 'hh:nn';
end;

class function THashBobJenkins.GetHashString(const S: string): string;
var
  H: Cardinal;
  I: Integer;
begin
  H := 2166136261;   // FNV-1a
  for I := 1 to Length(S) do
    H := (H xor Ord(S[I])) * 16777619;
  Result := LowerCase(IntToHex(H, 8));
end;

constructor TSemaphore.Create(AAttributes: Pointer; AInitial, AMax: Integer; const AName: string);
begin
  inherited Create;
  InitCriticalSection(FLock);
  FEvent := RTLEventCreate;
  FCount := AInitial;
end;

destructor TSemaphore.Destroy;
begin
  RTLEventDestroy(FEvent);
  DoneCriticalSection(FLock);
  inherited;
end;

procedure TSemaphore.Release(ACount: Integer);
begin
  EnterCriticalSection(FLock);
  Inc(FCount, ACount);
  LeaveCriticalSection(FLock);
  RTLEventSetEvent(FEvent);
end;

function TSemaphore.WaitFor(ATimeoutMs: Cardinal): Boolean;

  function Take: Boolean;
  begin
    EnterCriticalSection(FLock);
    Result := FCount > 0;
    if Result then
      Dec(FCount);
    // the event wakes one waiter only: pass it on while there is more to take
    if FCount > 0 then
      RTLEventSetEvent(FEvent);
    LeaveCriticalSection(FLock);
  end;

begin
  Result := Take;
  if Result then
    Exit;
  RTLEventWaitFor(FEvent, ATimeoutMs);
  Result := Take;
end;

class function TTimeZone.Local: TTimeZone;
begin
  Result := Default(TTimeZone);
end;

function TTimeZone.ToLocalTime(const AUtc: TDateTime): TDateTime;
{$IFDEF WINDOWS}
var
  U, L: TSystemTime;
begin
  DateTimeToSystemTime(AUtc, U);
  if SystemTimeToTzSpecificLocalTime(nil, U, L) then
    Result := SystemTimeToDateTime(L)
  else
    Result := UniversalTimeToLocal(AUtc);
end;
{$ELSE}
begin
  Result := UniversalTimeToLocal(AUtc);
end;
{$ENDIF}

function UpChar(C: WideChar): Char;
begin
  if Ord(C) < 128 then
    Result := UpCase(Char(Ord(C)))
  else
    Result := #0;
end;

end.
