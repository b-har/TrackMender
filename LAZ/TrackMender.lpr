program TrackMender;

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uMain, uGpx, uTiles, uMapView, uProfile, uFixPreview, uAbout, uSettings, uSettingsForm,
  uFmx, uCompat, uHttp;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
