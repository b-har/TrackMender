unit uAbout;

{ About box. The form holds the text and the pictures: the emblem, and the
  faint map with a track on it behind everything (resources\about-map-faded.png). }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Types, Classes, Math,
  Forms, Controls, Graphics, StdCtrls, ExtCtrls;

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

{$R *.lfm}

uses
  fileinfo, winpeimagereader, elfreader, machoreader;

const
  Edition = 'LAZ';

{ File version of the running program, '' when it has none. }
function FileVersionText: string;
var
  Info: TFileVersionInfo;
begin
  Result := '';
  Info := TFileVersionInfo.Create(nil);
  try
    try
      Info.ReadFileInfo;
      Result := Trim(Info.VersionStrings.Values['FileVersion']);
    except
      // no version resource in this build
    end;
  finally
    Info.Free;
  end;
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
  lblVersion.Caption := 'Version ' + AppVersion;
end;

end.
