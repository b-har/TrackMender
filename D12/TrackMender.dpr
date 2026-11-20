program TrackMender;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {frmMain},
  uGpx in 'uGpx.pas',
  uTiles in 'uTiles.pas',
  uMapView in 'uMapView.pas',
  uProfile in 'uProfile.pas',
  uFixPreview in 'uFixPreview.pas' {frmFixPreview},
  uAbout in 'uAbout.pas' {frmAbout},
  uSettings in 'uSettings.pas',
  uSettingsForm in 'uSettingsForm.pas' {frmSettings};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
