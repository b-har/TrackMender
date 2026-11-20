unit uSettingsForm;

{ The Settings window: where the map comes from. The form holds the layout. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Controls.Presentation,
  uSettings;

type
  TfrmSettings = class(TForm)
    lblMap: TLabel;
    lblTileUrl: TLabel;
    edtTileUrl: TEdit;
    lblApiKey: TLabel;
    edtApiKey: TEdit;
    lblMaxZoom: TLabel;
    edtMaxZoom: TEdit;
    lblAttribution: TLabel;
    edtAttribution: TEdit;
    lblHelp: TLabel;
    btnDefaults: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    procedure btnDefaultsClick(Sender: TObject);
  public
    { Shows the window. True on OK, with the new values in Settings. }
    class function Execute: Boolean;
  end;

var
  frmSettings: TfrmSettings;

implementation

{$R *.fmx}

class function TfrmSettings.Execute: Boolean;
var
  F: TfrmSettings;
begin
  F := TfrmSettings.Create(Application);
  try
    F.edtTileUrl.Text := Settings.TileUrl;
    F.edtApiKey.Text := Settings.ApiKey;
    F.edtMaxZoom.Text := IntToStr(Settings.MaxZoom);
    F.edtAttribution.Text := Settings.Attribution;
    Result := F.ShowModal = mrOk;
    if Result then
    begin
      Settings.TileUrl := Trim(F.edtTileUrl.Text);
      if Settings.TileUrl = '' then
        Settings.TileUrl := DefTileUrl;
      Settings.ApiKey := Trim(F.edtApiKey.Text);
      Settings.MaxZoom := EnsureRange(StrToIntDef(Trim(F.edtMaxZoom.Text), DefMaxZoom), 1, 22);
      Settings.Attribution := Trim(F.edtAttribution.Text);
    end;
  finally
    F.Free;
  end;
end;

{ Back to the OpenStreetMap map. Nothing is kept until OK. }
procedure TfrmSettings.btnDefaultsClick(Sender: TObject);
begin
  edtTileUrl.Text := DefTileUrl;
  edtApiKey.Text := '';
  edtMaxZoom.Text := IntToStr(DefMaxZoom);
  edtAttribution.Text := DefAttribution;
end;

end.
