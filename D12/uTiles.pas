unit uTiles;

{ Slippy-map tile source: background download, disk cache, small in-memory
  LRU of decoded bitmaps.  All public methods are main-thread only. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.SyncObjs,
  System.Generics.Collections, System.Generics.Defaults, FMX.Graphics;

type
  TTileJob = record
    Key: UInt64;
    Z: Integer;
    Url: string;
    CacheFile: string;
  end;

  TTileResultEvent = procedure(AKey: UInt64; const AData: TBytes; const AError: string) of object;

  ITileQueue = interface
    ['{6E0D3D0B-7C54-4B0B-9E0B-0C7B5E1B7A11}']
    function Pop(out AJob: TTileJob): Boolean;
    procedure Wait;
    function Stopped: Boolean;
    procedure Deliver(AKey: UInt64; const AData: TBytes; const AError: string);
  end;

  { Shared between the store and its worker threads; reference counted so it
    outlives whichever side goes away first. }
  TTileQueue = class(TInterfacedObject, ITileQueue)
  private
    FLock: TCriticalSection;
    FSem: TSemaphore;
    FJobs: TList<TTileJob>;
    FStopped: Boolean;
    FOnResult: TTileResultEvent;   // main thread only
  public
    constructor Create;
    destructor Destroy; override;
    procedure Push(const AJob: TTileJob);
    procedure Prune(AKeepZ: Integer; ARemoved: TList<UInt64>);
    procedure Stop;
    function Pop(out AJob: TTileJob): Boolean;
    procedure Wait;
    function Stopped: Boolean;
    procedure Deliver(AKey: UInt64; const AData: TBytes; const AError: string);
  end;

  TTileEntry = class
  public
    Bmp: TBitmap;
    LastUsed: Integer;
    RetryAt: UInt64;
    destructor Destroy; override;
  end;

  TTileStore = class
  private
    FUrlTemplate: string;
    FApiKey: string;
    FMaxZoom: Integer;
    FCacheDir: string;
    FQueueObj: TTileQueue;
    FQueue: ITileQueue;
    FCache: TObjectDictionary<UInt64, TTileEntry>;
    FPending: TDictionary<UInt64, Byte>;
    FFrame: Integer;
    FLastError: string;
    FOnTileReady: TNotifyEvent;
    function CacheFileFor(Z, X, Y: Integer): string;
    function UrlFor(Z, X, Y: Integer): string;
    procedure HandleResult(AKey: UInt64; const AData: TBytes; const AError: string);
    procedure Evict;
  public
    constructor Create(const AUrlTemplate, AApiKey: string; AMaxZoom: Integer);
    destructor Destroy; override;
    { Call once per paint, before asking for tiles of zoom level Z. }
    procedure BeginFrame(Z: Integer);
    { Returns the decoded tile or nil; a missing tile is queued for download. }
    function GetTile(Z, X, Y: Integer): TBitmap;
    { Like GetTile but never triggers a download. }
    function PeekTile(Z, X, Y: Integer): TBitmap;
    property MaxZoom: Integer read FMaxZoom;
    property LastError: string read FLastError;
    property OnTileReady: TNotifyEvent read FOnTileReady write FOnTileReady;
  end;

implementation

uses
  System.IOUtils, System.Hash, System.Net.HttpClient, System.Net.URLClient;

const
  WorkerCount = 4;
  MaxCached = 512;
  KeepCached = 384;
  RetryDelayMs = 15000;
  UserAgent = 'TrackMender/1.0 (desktop GPX track editor)';

type
  TTileWorker = class(TThread)
  private
    FQueue: ITileQueue;
  protected
    procedure Execute; override;
  public
    constructor Create(const AQueue: ITileQueue);
  end;

function TileKey(Z, X, Y: Integer): UInt64; inline;
begin
  Result := (UInt64(Z) shl 56) or (UInt64(X) shl 28) or UInt64(Y);
end;

{ TTileEntry }

destructor TTileEntry.Destroy;
begin
  Bmp.Free;
  inherited;
end;

{ TTileQueue }

constructor TTileQueue.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSem := TSemaphore.Create(nil, 0, MaxInt, '');
  FJobs := TList<TTileJob>.Create;
end;

destructor TTileQueue.Destroy;
begin
  FJobs.Free;
  FSem.Free;
  FLock.Free;
  inherited;
end;

procedure TTileQueue.Push(const AJob: TTileJob);
begin
  FLock.Enter;
  try
    FJobs.Add(AJob);
  finally
    FLock.Leave;
  end;
  FSem.Release;
end;

function TTileQueue.Pop(out AJob: TTileJob): Boolean;
begin
  FLock.Enter;
  try
    // newest first: whatever the user is looking at right now wins
    Result := (FJobs.Count > 0) and not FStopped;
    if Result then
    begin
      AJob := FJobs.Last;
      FJobs.Delete(FJobs.Count - 1);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TTileQueue.Prune(AKeepZ: Integer; ARemoved: TList<UInt64>);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FJobs.Count - 1 downto 0 do
      if FJobs[I].Z <> AKeepZ then
      begin
        ARemoved.Add(FJobs[I].Key);
        FJobs.Delete(I);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TTileQueue.Stop;
begin
  FOnResult := nil;
  FLock.Enter;
  try
    FStopped := True;
    FJobs.Clear;
  finally
    FLock.Leave;
  end;
  FSem.Release(WorkerCount);
end;

function TTileQueue.Stopped: Boolean;
begin
  Result := FStopped;
end;

procedure TTileQueue.Wait;
begin
  FSem.WaitFor(1000);
end;

procedure TTileQueue.Deliver(AKey: UInt64; const AData: TBytes; const AError: string);
var
  Keep: ITileQueue;
  Data: TBytes;
  Err: string;
begin
  Keep := Self;
  Data := AData;
  Err := AError;
  TThread.Queue(nil,
    procedure
    begin
      if (Keep <> nil) and Assigned(FOnResult) then
        FOnResult(AKey, Data, Err);
    end);
end;

{ TTileWorker }

constructor TTileWorker.Create(const AQueue: ITileQueue);
begin
  FQueue := AQueue;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TTileWorker.Execute;
var
  Http: THTTPClient;
  Job: TTileJob;
  Data: TBytes;
  Err: string;
  Resp: IHTTPResponse;
  MS: TMemoryStream;
begin
  Http := THTTPClient.Create;
  try
    Http.UserAgent := UserAgent;
    Http.ConnectionTimeout := 8000;
    Http.ResponseTimeout := 12000;
    while not FQueue.Stopped do
    begin
      if not FQueue.Pop(Job) then
      begin
        FQueue.Wait;
        Continue;
      end;
      Data := nil;
      Err := '';
      try
        if TFile.Exists(Job.CacheFile) then
          Data := TFile.ReadAllBytes(Job.CacheFile)
        else
        begin
          MS := TMemoryStream.Create;
          try
            Resp := Http.Get(Job.Url, MS);
            if Resp.StatusCode = 200 then
            begin
              SetLength(Data, MS.Size);
              if MS.Size > 0 then
                Move(MS.Memory^, Data[0], MS.Size);
              try
                // ForceDirectories, not TDirectory.CreateDirectory: several workers
                // create the same folder at once, and the loser of that race must
                // not raise (the debugger stops on it even though it is handled)
                if ForceDirectories(ExtractFilePath(Job.CacheFile)) or
                  DirectoryExists(ExtractFilePath(Job.CacheFile)) then
                  TFile.WriteAllBytes(Job.CacheFile, Data);
              except
                // a read-only or full cache folder must not stop the map from working
              end;
            end
            else
              Err := Format('tile server answered HTTP %d', [Resp.StatusCode]);
          finally
            MS.Free;
          end;
        end;
      except
        on E: Exception do
        begin
          Data := nil;
          Err := 'tile download failed: ' + E.Message;
        end;
      end;
      if not FQueue.Stopped then
        FQueue.Deliver(Job.Key, Data, Err);
    end;
  finally
    Http.Free;
  end;
end;

{ TTileStore }

constructor TTileStore.Create(const AUrlTemplate, AApiKey: string; AMaxZoom: Integer);
var
  I: Integer;
begin
  inherited Create;
  FUrlTemplate := AUrlTemplate;
  FApiKey := AApiKey;
  FMaxZoom := AMaxZoom;
  // one cache folder per tile source, so switching providers never mixes tiles
  FCacheDir := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetCachePath, 'TrackMender'),
    'tiles'), THashBobJenkins.GetHashString(AUrlTemplate));
  FCache := TObjectDictionary<UInt64, TTileEntry>.Create([doOwnsValues]);
  FPending := TDictionary<UInt64, Byte>.Create;
  FQueueObj := TTileQueue.Create;
  FQueue := FQueueObj;
  FQueueObj.FOnResult := HandleResult;
  for I := 1 to WorkerCount do
    TTileWorker.Create(FQueue);
end;

destructor TTileStore.Destroy;
begin
  // workers finish their current request on their own and then exit
  FQueueObj.Stop;
  FQueue := nil;
  FPending.Free;
  FCache.Free;
  inherited;
end;

function TTileStore.CacheFileFor(Z, X, Y: Integer): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(FCacheDir, Z.ToString), X.ToString),
    Y.ToString + '.tile');
end;

function TTileStore.UrlFor(Z, X, Y: Integer): string;
const
  Sub: array[0..2] of string = ('a', 'b', 'c');
begin
  Result := FUrlTemplate
    .Replace('{z}', Z.ToString, [rfReplaceAll, rfIgnoreCase])
    .Replace('{x}', X.ToString, [rfReplaceAll, rfIgnoreCase])
    .Replace('{y}', Y.ToString, [rfReplaceAll, rfIgnoreCase])
    .Replace('{s}', Sub[(X + Y) mod 3], [rfReplaceAll, rfIgnoreCase])
    .Replace('{key}', FApiKey, [rfReplaceAll, rfIgnoreCase]);
end;

procedure TTileStore.BeginFrame(Z: Integer);
var
  Removed: TList<UInt64>;
  K: UInt64;
begin
  Inc(FFrame);
  // drop queued downloads for zoom levels the user has already left
  Removed := TList<UInt64>.Create;
  try
    FQueueObj.Prune(Z, Removed);
    for K in Removed do
      FPending.Remove(K);
  finally
    Removed.Free;
  end;
  if FCache.Count > MaxCached then
    Evict;
end;

procedure TTileStore.Evict;
var
  Items: TList<TPair<UInt64, TTileEntry>>;
  Pair: TPair<UInt64, TTileEntry>;
  I: Integer;
begin
  Items := TList<TPair<UInt64, TTileEntry>>.Create;
  try
    for Pair in FCache do
      if Pair.Value.LastUsed < FFrame - 1 then
        Items.Add(Pair);
    Items.Sort(TComparer<TPair<UInt64, TTileEntry>>.Construct(
      function(const L, R: TPair<UInt64, TTileEntry>): Integer
      begin
        Result := L.Value.LastUsed - R.Value.LastUsed;
      end));
    I := 0;
    while (FCache.Count > KeepCached) and (I < Items.Count) do
    begin
      FCache.Remove(Items[I].Key);
      Inc(I);
    end;
  finally
    Items.Free;
  end;
end;

function TTileStore.PeekTile(Z, X, Y: Integer): TBitmap;
var
  E: TTileEntry;
begin
  Result := nil;
  if FCache.TryGetValue(TileKey(Z, X, Y), E) and (E.Bmp <> nil) then
  begin
    E.LastUsed := FFrame;
    Result := E.Bmp;
  end;
end;

function TTileStore.GetTile(Z, X, Y: Integer): TBitmap;
var
  Key: UInt64;
  E: TTileEntry;
  Job: TTileJob;
begin
  Result := nil;
  Key := TileKey(Z, X, Y);
  if FCache.TryGetValue(Key, E) then
  begin
    E.LastUsed := FFrame;
    if E.Bmp <> nil then
      Exit(E.Bmp);
    if TThread.GetTickCount64 < E.RetryAt then
      Exit;
    FCache.Remove(Key);
  end;
  if FPending.ContainsKey(Key) then
    Exit;
  FPending.Add(Key, 0);
  Job.Key := Key;
  Job.Z := Z;
  Job.Url := UrlFor(Z, X, Y);
  Job.CacheFile := CacheFileFor(Z, X, Y);
  FQueueObj.Push(Job);
end;

procedure TTileStore.HandleResult(AKey: UInt64; const AData: TBytes; const AError: string);
var
  E: TTileEntry;
  Stream: TBytesStream;
  Z, X, Y: Integer;
begin
  FPending.Remove(AKey);
  E := TTileEntry.Create;
  E.LastUsed := FFrame;
  if Length(AData) > 0 then
  begin
    Stream := TBytesStream.Create(AData);
    try
      try
        E.Bmp := TBitmap.CreateFromStream(Stream);
      except
        E.Bmp := nil;
      end;
    finally
      Stream.Free;
    end;
    if (E.Bmp = nil) or E.Bmp.IsEmpty then
    begin
      // undecodable payload: make sure it does not stay in the disk cache
      FreeAndNil(E.Bmp);
      Z := AKey shr 56;
      X := (AKey shr 28) and $FFFFFFF;
      Y := AKey and $FFFFFFF;
      try
        TFile.Delete(CacheFileFor(Z, X, Y));
      except
      end;
      FLastError := 'tile server sent something that is not an image';
    end
    else
      FLastError := '';
  end
  else
    FLastError := AError;
  if E.Bmp = nil then
    E.RetryAt := TThread.GetTickCount64 + RetryDelayMs;
  FCache.AddOrSetValue(AKey, E);
  if Assigned(FOnTileReady) then
    FOnTileReady(Self);
end;

end.
