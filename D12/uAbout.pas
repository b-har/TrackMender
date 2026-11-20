unit uAbout;

{ About box. The form holds the text and the pictures: the emblem, and the
  faint map with a track on it behind everything (resources\about-map-faded.png). }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Objects,
  FMX.Controls.Presentation;

type
  TfrmAbout = class(TForm)
    imgBack: TImage;
    imgLogo: TImage;
    lblName: TLabel;
    lblDescription: TLabel;
    lblVersion: TLabel;
    lblCredits: TLabel;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
  public
    class procedure Execute;
  end;

{ The version shown to the user: which edition this is, then the file version
  stored in the executable (set in the project options or by the build). }
function AppVersion: string;

var
  frmAbout: TfrmAbout;

implementation

{$R *.fmx}

uses
  Winapi.Windows;

const
  Edition = 'DEL';

{ File version of the running program, '' when it has none. }
function FileVersionText: string;
type
  TTranslation = packed record
    Lang, CodePage: Word;
  end;
  PTranslation = ^TTranslation;
var
  Size, Dummy, Len: DWORD;
  Buf: TBytes;
  Trans: PTranslation;
  Value: PChar;
  Fixed: PVSFixedFileInfo;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(ParamStr(0)), 0, Size, @Buf[0]) then
    Exit;
  // the version as text, exactly as the build wrote it
  if VerQueryValue(@Buf[0], '\VarFileInfo\Translation', Pointer(Trans), Len) and (Len >= SizeOf(TTranslation)) then
    if VerQueryValue(@Buf[0], PChar(Format('\StringFileInfo\%.4x%.4x\FileVersion', [Trans.Lang, Trans.CodePage])),
      Pointer(Value), Len) and (Len > 0) then
      Result := Trim(Value);
  // otherwise the numeric one
  if (Result = '') and VerQueryValue(@Buf[0], '\', Pointer(Fixed), Len) and (Len >= SizeOf(TVSFixedFileInfo)) then
    Result := Format('%d.%d.%d.%d', [HiWord(Fixed.dwFileVersionMS), LoWord(Fixed.dwFileVersionMS),
      HiWord(Fixed.dwFileVersionLS), LoWord(Fixed.dwFileVersionLS)]);
end;

function AppVersion: string;
begin
  Result := FileVersionText;
  if Result = '' then
    Result := '?';
  Result := Edition + '-' + Result;
end;

class procedure TfrmAbout.Execute;
var
  F: TfrmAbout;
begin
  F := TfrmAbout.Create(Application);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TfrmAbout.FormCreate(Sender: TObject);
begin
  lblVersion.Text := 'Version ' + AppVersion;
end;

end.
