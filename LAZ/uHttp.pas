unit uHttp;

{ Lazarus only.  System.Net.HttpClient as far as the tile download uses it:
  a blocking GET into a stream.

  Windows: WinINet, which is part of the system and brings its own TLS.
  Elsewhere: fphttpclient, which needs the OpenSSL libraries for https. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils;

type
  IHTTPResponse = interface
    ['{3C0B3B4E-7E0A-4D53-9A5F-0E2B8E7C1D21}']
    function GetStatusCode: Integer;
    property StatusCode: Integer read GetStatusCode;
  end;

  THTTPClient = class
  private
    FUserAgent: string;
    FConnectionTimeout: Integer;
    FResponseTimeout: Integer;
    {$IFDEF WINDOWS}
    FSession: Pointer;
    {$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    { Raises an exception when the server cannot be reached. }
    function Get(const AUrl: string; AResponse: TStream): IHTTPResponse;
    property UserAgent: string read FUserAgent write FUserAgent;
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property ResponseTimeout: Integer read FResponseTimeout write FResponseTimeout;
  end;

implementation

{$IFDEF WINDOWS}
uses
  Windows, WinInet;
{$ELSE}
uses
  fphttpclient, opensslsockets;
{$ENDIF}

type
  THTTPResponse = class(TInterfacedObject, IHTTPResponse)
  private
    FStatus: Integer;
  public
    constructor Create(AStatus: Integer);
    function GetStatusCode: Integer;
  end;

constructor THTTPResponse.Create(AStatus: Integer);
begin
  inherited Create;
  FStatus := AStatus;
end;

function THTTPResponse.GetStatusCode: Integer;
begin
  Result := FStatus;
end;

constructor THTTPClient.Create;
begin
  inherited Create;
  FConnectionTimeout := 8000;
  FResponseTimeout := 12000;
end;

{$IFDEF WINDOWS}

destructor THTTPClient.Destroy;
begin
  if FSession <> nil then
    InternetCloseHandle(FSession);
  inherited;
end;

function THTTPClient.Get(const AUrl: string; AResponse: TStream): IHTTPResponse;
var
  Req: Pointer;
  Buf: array[0..16383] of Byte;
  Got, Status, Len, Index: DWORD;
  T: DWORD;
begin
  if FSession = nil then
  begin
    FSession := InternetOpenW(PWideChar(UnicodeString(FUserAgent)), INTERNET_OPEN_TYPE_PRECONFIG,
      nil, nil, 0);
    if FSession = nil then
      raise Exception.Create('no internet session (' + SysErrorMessage(GetLastError) + ')');
    T := FConnectionTimeout;
    InternetSetOptionW(FSession, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
    T := FResponseTimeout;
    InternetSetOptionW(FSession, INTERNET_OPTION_RECEIVE_TIMEOUT, @T, SizeOf(T));
  end;
  Req := InternetOpenUrlW(FSession, PWideChar(UnicodeString(AUrl)), nil, 0,
    INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_NO_UI or
    INTERNET_FLAG_KEEP_CONNECTION, 0);
  if Req = nil then
    raise Exception.Create(SysErrorMessage(GetLastError));
  try
    Status := 0;
    Len := SizeOf(Status);
    Index := 0;
    if not HttpQueryInfoW(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Status, Len, Index) then
      Status := 0;
    repeat
      Got := 0;
      if not InternetReadFile(Req, @Buf[0], SizeOf(Buf), Got) then
        raise Exception.Create(SysErrorMessage(GetLastError));
      if Got > 0 then
        AResponse.WriteBuffer(Buf[0], Got);
    until Got = 0;
    Result := THTTPResponse.Create(Status);
  finally
    InternetCloseHandle(Req);
  end;
end;

{$ELSE}

destructor THTTPClient.Destroy;
begin
  inherited;
end;

function THTTPClient.Get(const AUrl: string; AResponse: TStream): IHTTPResponse;
var
  C: TFPHTTPClient;
begin
  C := TFPHTTPClient.Create(nil);
  try
    C.AddHeader('User-Agent', FUserAgent);
    C.ConnectTimeout := FConnectionTimeout;
    C.IOTimeout := FResponseTimeout;
    C.AllowRedirect := True;
    C.HTTPMethod('GET', AUrl, AResponse, []);
    Result := THTTPResponse.Create(C.ResponseStatusCode);
  finally
    C.Free;
  end;
end;

{$ENDIF}

end.
