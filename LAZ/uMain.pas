unit uMain;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Types, Classes, LCLType,
  Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Buttons, Menus,
  uGpx, uMapView, uProfile, uFixPreview;

type
  TfrmMain = class(TForm)
    pnlToolbar: TPanel;
    btnOpen: TSpeedButton;
    btnOpenMore: TSpeedButton;
    btnSave: TSpeedButton;
    btnSaveMore: TSpeedButton;
    btnUndo: TSpeedButton;
    btnRedo: TSpeedButton;
    btnZoomIn: TSpeedButton;
    btnZoomOut: TSpeedButton;
    btnZoomFit: TSpeedButton;
    btnGraph: TSpeedButton;
    btnInfo: TSpeedButton;
    btnSettings: TSpeedButton;
    rectWarn: TPanel;
    lblWarn: TLabel;
    btnFixEle: TSpeedButton;
    btnFixSpeed: TSpeedButton;
    btnFixBoth: TSpeedButton;
    btnWarnClose: TSpeedButton;
    pnlGraph: TPanel;
    layGraphHead: TPanel;
    lblGraphInfo: TLabel;
    lblOutlier: TLabel;
    lblOutHead: TLabel;
    lblFixHead: TLabel;
    btnOutPrev: TSpeedButton;
    btnOutNext: TSpeedButton;
    btnFixEle1: TSpeedButton;
    btnFixTime1: TSpeedButton;
    btnXDist: TSpeedButton;
    btnXTime: TSpeedButton;
    splGraph: TSplitter;
    popUnits: TPopupMenu;
    miUnitsHead: TMenuItem;
    miImperial: TMenuItem;
    miMetric: TMenuItem;
    miAviation: TMenuItem;
    miMarine: TMenuItem;
    miSettingsSep: TMenuItem;
    miSettings: TMenuItem;
    miAboutSep: TMenuItem;
    miAbout: TMenuItem;
    popOpen: TPopupMenu;
    miRecentHead: TMenuItem;
    miRecent1: TMenuItem;
    miRecent2: TMenuItem;
    miRecent3: TMenuItem;
    miRecent4: TMenuItem;
    miRecent5: TMenuItem;
    miRecentNone: TMenuItem;
    popSave: TPopupMenu;
    miSaveAs: TMenuItem;
    pnlStatus: TPanel;
    lblStatus: TLabel;
    lblCursor: TLabel;
    pnlSegments: TPanel;
    lstSegments: TListBox;
    splSegments: TSplitter;
    pnlMap: TPanel;
    layInfo: TPanel;
    lblInfoTitle: TLabel;
    lblInfoKeys: TLabel;
    lblInfoVals: TLabel;
    lblChanges: TLabel;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnOpenClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnUndoClick(Sender: TObject);
    procedure btnRedoClick(Sender: TObject);
    procedure btnZoomInClick(Sender: TObject);
    procedure btnZoomOutClick(Sender: TObject);
    procedure btnZoomFitClick(Sender: TObject);
    procedure lstSegmentsSelectionChange(Sender: TObject; User: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure btnGraphClick(Sender: TObject);
    procedure btnInfoClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnXAxisClick(Sender: TObject);
    procedure btnOutPrevClick(Sender: TObject);
    procedure btnOutNextClick(Sender: TObject);
    procedure btnFixEle1Click(Sender: TObject);
    procedure btnFixTime1Click(Sender: TObject);
    procedure miUnitsClick(Sender: TObject);
    procedure miSettingsClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure btnOpenMoreClick(Sender: TObject);
    procedure btnSaveMoreClick(Sender: TObject);
    procedure miRecentClick(Sender: TObject);
    procedure miSaveAsClick(Sender: TObject);
    procedure btnFixClick(Sender: TObject);
    procedure btnWarnCloseClick(Sender: TObject);
  private
    FMap: TMapView;
    FProfile: TProfileView;
    FDoc: TGpxDoc;
    FFixBusy: Boolean;
    FGraphOn: Boolean;
    FQueuedFile: string;      // opened once the message loop is idle
    FInfoOn: Boolean;
    FListSync: Boolean;       // the segment list is being set by code, not by the user
    FIssues: TGpxIssues;
    FIssuesRev: Integer;      // document revision FIssues belongs to
    FWarnDismissed: Boolean;
    procedure CreateMap;
    procedure ConfigureMap;
    procedure RestoreWindow;
    procedure ShowInfo(AShow: Boolean);
    procedure UpdateInfo;
    procedure UpdateChanges;
    procedure CreateProfile;
    procedure SaveViewSettings;
    procedure ShowGraph(AShow: Boolean);
    procedure SetUnits(AUnits: TUnitSystem);
    procedure UpdateGraph;
    procedure StepOutlier(ADir: Integer);
    function TimePreviewPoints(ALevel: Integer): TArray<TPreviewPoint>;
    function ElePreviewPoints(ALevel: Integer): TArray<TPreviewPoint>;
    procedure UpdateWarning;
    procedure ProfileSelect(Sender: TObject; ASeg, AIdx: Integer);
    procedure MapChange(Sender: TObject);
    procedure MapCursorMove(Sender: TObject);
    procedure UpdateUI;
    procedure UpdateCursorInfo;
    procedure FillSegments;
    function SegmentCaption(AIndex: Integer): string;
    { True when it is fine to throw the current document away. }
    function CanDiscard: Boolean;
    function SaveDoc: Boolean;
    function SaveDocAs: Boolean;
    procedure FillRecent;
    procedure PopupBelow(AButton: TControl; AMenu: TPopupMenu);
    procedure OpenFile(const AFileName: string);
    procedure ShowError(const AText: string);
    procedure OpenQueued(AData: PtrInt);
    procedure OpenDropped(AData: PtrInt);
    procedure HandleKey(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

uses
  Math, StrUtils, uCompat, uSettings, uSettingsForm, uAbout;

const
  AppTitle = 'TrackMender';
  AppDescription = 'Frankie''s GPX Track Mender';

  // FMX names of the virtual keys
  vkUp = VK_UP;           vkDown = VK_DOWN;       vkLeft = VK_LEFT;     vkRight = VK_RIGHT;
  vkHome = VK_HOME;       vkEnd = VK_END;         vkPrior = VK_PRIOR;   vkNext = VK_NEXT;
  vkAdd = VK_ADD;         vkSubtract = VK_SUBTRACT;
  vkEqual = VK_OEM_PLUS;  vkMinus = VK_OEM_MINUS; vkNumpad0 = VK_NUMPAD0;
  vkEscape = VK_ESCAPE;   vkDelete = VK_DELETE;   vkInsert = VK_INSERT;
  vkF1 = VK_F1;           vkF6 = VK_F6;           vkF7 = VK_F7;         vkF8 = VK_F8;

function Num(AValue: Integer): string;
begin
  Result := FormatFloat('#,##0', AValue);
end;

{ ---- setup ----------------------------------------------------------------- }

procedure TfrmMain.FormCreate(Sender: TObject);
var
  FileName: string;
begin
  CreateMap;
  CreateProfile;
  RestoreWindow;
  UpdateUI;
  if ParamCount >= 1 then
  begin
    // after the first layout pass, so the track is fitted to the real map size
    FileName := ParamStr(1);
    FQueuedFile := FileName;
    Application.QueueAsyncCall(OpenQueued, 0);
  end;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  SaveViewSettings;
  FProfile.Doc := nil;
  FMap.Doc := nil;
  FDoc.Free;
end;

(* The map control is the one piece that is not on the form at design time: it
   is a custom control and would need a design-time package to be droppable.
   It simply fills pnlMap. *)
procedure TfrmMain.CreateMap;
begin
  FMap := TMapView.Create(Self);
  FMap.Parent := pnlMap;
  FMap.Align := alClient;
  // the design-time info card goes onto the map, pinned to its top right
  // corner: as a child window of the map it is never painted over
  layInfo.Parent := FMap;
  layInfo.AnchorSideTop.Control := FMap;
  layInfo.AnchorSideRight.Control := FMap;
  layInfo.AnchorSideRight.Side := asrRight;
  layInfo.BorderSpacing.Top := 12;
  layInfo.BorderSpacing.Right := 12;
  layInfo.Anchors := [akTop, akRight];
  layInfo.BringToFront;
  ConfigureMap;
  FMap.OnChange := MapChange;
  FMap.OnCursorMove := MapCursorMove;
end;

{ Where the map tiles come from, as set in the Settings window. }
procedure TfrmMain.ConfigureMap;
begin
  FMap.Configure(Settings.TileUrl, Settings.ApiKey, Settings.Attribution, Settings.MaxZoom);
end;

{ The graph is the other runtime-created control; it fills pnlGraph below the
  design-time header row.  What the user chose last time comes from the
  settings (see uSettings). }
procedure TfrmMain.CreateProfile;
var
  U, Units: TUnitSystem;
begin
  FProfile := TProfileView.Create(Self);
  FProfile.Parent := pnlGraph;
  FProfile.Align := alClient;
  FProfile.OnSelectPoint := ProfileSelect;

  Units := usImperial;
  for U := Low(TUnitSystem) to High(TUnitSystem) do
    if UnitInfo[U].Key = Settings.Units then
      Units := U;
  if Settings.GraphX = 'time' then
    FProfile.XMode := pxTime;
  if Settings.GraphHeight > 0 then
    pnlGraph.Height := EnsureRange(Settings.GraphHeight, 120, 600);
  if Settings.SegmentsWidth > 0 then
    pnlSegments.Width := EnsureRange(Settings.SegmentsWidth, 120, 800);
  FInfoOn := Settings.PointInfo;
  btnXTime.Down := FProfile.XMode = pxTime;
  btnXDist.Down := FProfile.XMode = pxDistance;
  SetUnits(Units);
  ShowGraph(Settings.Graph);
  ShowInfo(FInfoOn);
end;

{ Window position, size and maximized state from the last run.  A position
  that is no longer on any screen is ignored. }
procedure TfrmMain.RestoreWindow;
var
  L, T, W, H, I: Integer;
  R, Hit: TRect;
  OnScreen: Boolean;
begin
  L := Settings.WinLeft;
  T := Settings.WinTop;
  W := Settings.WinWidth;
  H := Settings.WinHeight;
  if Settings.HasWindowPos and (W >= 400) and (H >= 300) then
  begin
    // enough of the title bar must be on a screen to grab it
    R := Rect(L + 40, T, L + W - 40, T + 30);
    OnScreen := False;
    for I := 0 to Screen.MonitorCount - 1 do
      if IntersectRect(Hit, Screen.Monitors[I].WorkareaRect, R) then
        OnScreen := True;
    if OnScreen then
    begin
      Position := poDesigned;
      SetBounds(L, T, W, H);
    end;
  end;
  if Settings.Maximized then
    WindowState := wsMaximized;
end;

procedure TfrmMain.SaveViewSettings;
begin
  if FProfile = nil then
    Exit;
  Settings.Graph := FGraphOn;
  Settings.GraphX := IfThen(FProfile.XMode = pxTime, 'time', 'distance');
  Settings.GraphHeight := Round(pnlGraph.Height);
  Settings.PointInfo := FInfoOn;
  Settings.SegmentsWidth := Round(pnlSegments.Width);
  // the size of a maximized window is not worth keeping: leave the last normal one
  Settings.Maximized := WindowState = wsMaximized;
  if WindowState = wsNormal then
  begin
    Settings.HasWindowPos := True;
    Settings.WinLeft := Left;
    Settings.WinTop := Top;
    Settings.WinWidth := Width;
    Settings.WinHeight := Height;
  end;
  Settings.Units := UnitInfo[FProfile.Units].Key;
  Settings.Save;
end;

procedure TfrmMain.ShowGraph(AShow: Boolean);
begin
  FGraphOn := AShow;
  btnGraph.Down := AShow;
  if AShow then
  begin
    // bottom-aligned controls stack by position: keep the graph above the status bar
    pnlGraph.Top := pnlStatus.Top - pnlStatus.BorderSpacing.Top - pnlGraph.Height;
    splGraph.Top := pnlGraph.Top - splGraph.Height;
  end;
  pnlGraph.Visible := AShow;
  splGraph.Visible := AShow;
  if AShow then
    UpdateGraph;
end;

{ The "i" button: details of the selected point in a card on the map.  The
  card (layInfo) only shows while a point is selected. }
procedure TfrmMain.ShowInfo(AShow: Boolean);
begin
  FInfoOn := AShow;
  btnInfo.Down := AShow;
  UpdateInfo;
end;

procedure TfrmMain.UpdateInfo;
const
  None = '–';
var
  Seg: TGpxSegment;
  P: PGpxPoint;
  I: Integer;
  Dist, Speed: Double;
  S, Ele, Spd, Tm: string;
begin
  if not (FInfoOn and (FDoc <> nil) and FMap.HasSelection) then
  begin
    layInfo.Visible := False;
    Exit;
  end;
  Seg := FDoc[FMap.SelSeg];
  P := Seg[FMap.SelIdx];
  S := Format('Point %s of %s', [Num(FMap.SelIdx + 1), Num(Seg.Count)]);
  if FDoc.SegCount > 1 then
    S := S + Format('  ·  segment %d', [FMap.SelSeg + 1]);
  lblInfoTitle.Caption := S;

  Dist := 0;
  for I := 1 to FMap.SelIdx do
    Dist := Dist + GeoDist(Seg[I - 1]^, Seg[I]^);
  Speed := FDoc.SpeedAt(FMap.SelSeg, FMap.SelIdx);
  if P.HasEle then Ele := FProfile.FormatEle(P.Ele) else Ele := None;
  if IsNan(Speed) then Spd := None else Spd := FProfile.FormatSpeed(Speed);
  if P.HasTime then Tm := LocalTimeText(P.Time) else Tm := None;
  lblInfoVals.Caption :=
    Format('%.6f', [P.Lat], TFormatSettings.Invariant) + sLineBreak +
    Format('%.6f', [P.Lon], TFormatSettings.Invariant) + sLineBreak +
    Ele + sLineBreak + Spd + sLineBreak + Tm + sLineBreak +
    FProfile.FormatDist(Dist) + ' from start';
  layInfo.Visible := True;
  layInfo.BringToFront;
end;

{ Status bar: what has been done to the file since it was opened. }
procedure TfrmMain.UpdateChanges;
var
  Moved, Deleted, Inserted, Normalized: Integer;
  S: string;

  procedure Part(ACount: Integer; const AWhat: string);
  begin
    if ACount = 0 then
      Exit;
    if S <> '' then
      S := S + ';  ';
    S := S + Num(ACount) + ' ' + AWhat;
  end;

begin
  S := '';
  if FDoc <> nil then
  begin
    FDoc.EditCounts(Moved, Deleted, Inserted, Normalized);
    Part(Moved, 'moved');
    Part(Deleted, 'deleted');
    Part(Inserted, 'inserted');
    Part(Normalized, 'normalized');
  end;
  if lblChanges.Caption <> S then
    lblChanges.Caption := S;
end;

procedure TfrmMain.SetUnits(AUnits: TUnitSystem);
begin
  FProfile.Units := AUnits;
  miImperial.Checked := AUnits = usImperial;
  miMetric.Checked := AUnits = usMetric;
  miAviation.Checked := AUnits = usAviation;
  miMarine.Checked := AUnits = usMarine;
end;

procedure TfrmMain.ProfileSelect(Sender: TObject; ASeg, AIdx: Integer);
begin
  FMap.SelectPoint(ASeg, AIdx);
end;

{ ---- document -------------------------------------------------------------- }

procedure TfrmMain.ShowError(const AText: string);
begin
  MessageDlg(AppTitle, AText, mtError, [mbOK], 0);
end;

function TfrmMain.SaveDoc: Boolean;
begin
  Result := False;
  if FDoc = nil then
    Exit;
  try
    FDoc.Save;
    Result := True;
  except
    on E: Exception do
      ShowError('Could not save ' + ExtractFileName(FDoc.FileName) + sLineBreak + sLineBreak + E.Message);
  end;
  UpdateUI;
end;

{ Save as: the file gets another name and the window carries on with that one. }
function TfrmMain.SaveDocAs: Boolean;
begin
  Result := False;
  if FDoc = nil then
    Exit;
  dlgSave.InitialDir := ExtractFilePath(FDoc.FileName);
  dlgSave.FileName := ExtractFileName(FDoc.FileName);
  if not dlgSave.Execute then
    Exit;
  try
    FDoc.SaveAs(ExpandFileName(dlgSave.FileName));
    Result := True;
  except
    on E: Exception do
      ShowError('Could not save ' + ExtractFileName(dlgSave.FileName) + sLineBreak + sLineBreak + E.Message);
  end;
  if Result then
  begin
    Settings.AddRecent(FDoc.FileName);
    SaveViewSettings;
  end;
  UpdateUI;
end;

function TfrmMain.CanDiscard: Boolean;
var
  Answer: TModalResult;
begin
  if (FDoc = nil) or not FDoc.Modified then
    Exit(True);
  Answer := MessageDlg(AppTitle,
    Format('Save changes to %s?', [ExtractFileName(FDoc.FileName)]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case Answer of
    mrYes: Result := SaveDoc;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TfrmMain.OpenFile(const AFileName: string);
var
  NewDoc: TGpxDoc;
begin
  NewDoc := TGpxDoc.Create;
  try
    NewDoc.LoadFromFile(ExpandFileName(AFileName));
  except
    on E: Exception do
    begin
      NewDoc.Free;
      ShowError('Could not open ' + ExtractFileName(AFileName) + sLineBreak + sLineBreak + E.Message);
      Exit;
    end;
  end;

  FProfile.Doc := nil;
  FMap.Doc := nil;
  FreeAndNil(FDoc);
  FDoc := NewDoc;
  FWarnDismissed := False;
  FIssuesRev := -1;
  FillSegments;          // before the map fits the track: the list changes the map's width
  FProfile.Doc := FDoc;
  FMap.Doc := FDoc;
  Settings.AddRecent(FDoc.FileName);
  SaveViewSettings;
  UpdateUI;
end;

function TfrmMain.SegmentCaption(AIndex: Integer): string;
var
  Seg: TGpxSegment;
begin
  Seg := FDoc[AIndex];
  Result := (AIndex + 1).ToString + '.  ';
  if Seg.Name <> '' then
    Result := Result + Seg.Name
  else
    Result := Result + 'Segment';
  Result := Result + '  (' + Num(Seg.Count) + ')';
end;

procedure TfrmMain.FillSegments;
var
  I: Integer;
begin
  FListSync := True;
  lstSegments.Items.BeginUpdate;
  try
    lstSegments.Clear;
    if (FDoc <> nil) and (FDoc.SegCount > 1) then
    begin
      lstSegments.Items.Add('Show all');
      for I := 0 to FDoc.SegCount - 1 do
        lstSegments.Items.Add(SegmentCaption(I));
      lstSegments.ItemIndex := 0;
    end;
  finally
    lstSegments.Items.EndUpdate;
    FListSync := False;
  end;
  if lstSegments.Count > 0 then
    splSegments.Left := pnlSegments.Left + pnlSegments.Width;
  pnlSegments.Visible := lstSegments.Count > 0;
  splSegments.Visible := pnlSegments.Visible;
end;

{ ---- UI state -------------------------------------------------------------- }

procedure TfrmMain.MapChange(Sender: TObject);
begin
  UpdateUI;
end;

procedure TfrmMain.MapCursorMove(Sender: TObject);
begin
  UpdateCursorInfo;
end;

procedure TfrmMain.UpdateCursorInfo;
var
  Lat, Lon: Double;
  S: string;
begin
  S := FMap.TileError;
  if S <> '' then
    S := 'Map: ' + S
  else
  begin
    S := 'zoom ' + FormatFloat('0.#', FMap.Zoom);
    if FMap.CursorPos(Lat, Lon) then
      S := Format('%.5f, %.5f', [Lat, Lon], TFormatSettings.Invariant) + '   ' + '·' + '   ' + S;
  end;
  if lblCursor.Caption <> S then
    lblCursor.Caption := S;
end;

procedure TfrmMain.UpdateUI;
const
  Dot = '   ·   ';
var
  S: string;
  P: PGpxPoint;
  I: Integer;
  Speed: Double;
begin
  btnSave.Enabled := (FDoc <> nil) and FDoc.Modified;
  btnSaveMore.Enabled := FDoc <> nil;
  btnUndo.Enabled := (FDoc <> nil) and FDoc.CanUndo;
  btnRedo.Enabled := (FDoc <> nil) and FDoc.CanRedo;
  btnZoomFit.Enabled := FDoc <> nil;

  if FDoc = nil then
  begin
    Caption := AppTitle + ' - ' + AppDescription;
    lblStatus.Caption := 'Open a GPX file, or drop one onto the window.';
  end
  else
  begin
    S := ExtractFileName(FDoc.FileName);
    if FDoc.Modified then
      S := S + ' *';
    Caption := S + ' - ' + AppTitle;

    if FMap.HasSelection then
    begin
      P := FDoc[FMap.SelSeg][FMap.SelIdx];
      S := Format('Point %s of %s', [Num(FMap.SelIdx + 1), Num(FDoc[FMap.SelSeg].Count)]);
      if FDoc.SegCount > 1 then
        S := S + Format(' in segment %d', [FMap.SelSeg + 1]);
      S := S + Dot + Format('%.6f, %.6f', [P.Lat, P.Lon], TFormatSettings.Invariant);
      if P.HasEle then
        S := S + Dot + FProfile.FormatEle(P.Ele);
      Speed := FDoc.SpeedAt(FMap.SelSeg, FMap.SelIdx);
      if not IsNan(Speed) then
        S := S + Dot + FProfile.FormatSpeed(Speed);
      if P.HasTime then
        S := S + Dot + LocalTimeText(P.Time);
    end
    else
    begin
      S := Num(FDoc.PointCount) + ' points';
      if FDoc.SegCount > 1 then
        S := S + Format(' in %d segments', [FDoc.SegCount]);
      S := S + Dot + 'click a point to select it';
    end;
    lblStatus.Caption := S;

    // keep the segment list in step with edits and with the map
    if lstSegments.Count = FDoc.SegCount + 1 then
    begin
      for I := 0 to FDoc.SegCount - 1 do
      begin
        S := SegmentCaption(I);
        if lstSegments.Items[I + 1] <> S then
          lstSegments.Items[I + 1] := S;
      end;
      if lstSegments.ItemIndex <> FMap.VisibleSeg + 1 then
      begin
        FListSync := True;
        try
          lstSegments.ItemIndex := FMap.VisibleSeg + 1;
        finally
          FListSync := False;
        end;
      end;
    end;
  end;
  UpdateGraph;
  UpdateWarning;
  UpdateInfo;
  UpdateChanges;
  UpdateCursorInfo;
end;

procedure TfrmMain.UpdateGraph;
var
  S: string;
  N, Pos: Integer;
  ElePlan: TGpxElePlan;
begin
  if not FGraphOn then
    Exit;
  FProfile.VisibleSeg := FMap.VisibleSeg;
  FProfile.DataChanged;
  FProfile.SetSelection(FMap.SelSeg, FMap.SelIdx);
  btnXTime.Enabled := (FDoc = nil) or FProfile.HasTime;

  btnFixEle1.Enabled := FMap.HasSelection and FDoc.PlanFixElevation(FMap.SelSeg, FMap.SelIdx, ElePlan);
  btnFixTime1.Enabled := FMap.HasSelection and FDoc.CanFixTime(FMap.SelSeg, FMap.SelIdx);
  N := FProfile.OutlierCount;
  btnOutNext.Enabled := N > 0;
  btnOutPrev.Enabled := N > 0;
  Pos := -1;
  if FMap.HasSelection then
    Pos := FProfile.OutlierPos(FMap.SelSeg, FMap.SelIdx);
  if FDoc = nil then
    S := ''
  else if N = 0 then
    S := 'none'
  else if Pos >= 0 then
    S := Format('%d of %d:  %s', [Pos + 1, N, FProfile.OutlierText(Pos)])
  else
    S := Num(N) + ' found';
  if lblOutlier.Caption <> S then
    lblOutlier.Caption := S;
  S := FProfile.Summary;
  if S = '' then
    S := 'Elevation and speed';
  if lblGraphInfo.Caption <> S then
    lblGraphInfo.Caption := S;
end;

{ The warning strip in the toolbar: what Normalize would repair in this file.
  It follows the document, so it goes away once the points are fixed and comes
  back when that is undone. }
procedure TfrmMain.UpdateWarning;
var
  S: string;
  E, T: Integer;

  procedure Part(ACount: Integer; const AWhat: string);
  begin
    if ACount = 0 then
      Exit;
    if S = '' then
      S := Num(ACount) + IfThen(ACount = 1, ' point', ' points') + ' with ' + AWhat
    else
      S := S + ', ' + Num(ACount) + ' with ' + AWhat;
  end;

begin
  if (FDoc = nil) or FWarnDismissed then
  begin
    rectWarn.Visible := False;
    Exit;
  end;
  if FIssuesRev <> FDoc.Revision then
  begin
    FIssues := FDoc.Analyze;
    FIssuesRev := FDoc.Revision;
  end;
  E := FIssues.EleCount;
  T := FIssues.TimeCount;
  if E + T = 0 then
  begin
    rectWarn.Visible := False;
    Exit;
  end;

  S := '';
  Part(FIssues.NoEle, 'missing elevation');
  Part(FIssues.BadEle, 'implausible elevation');
  Part(FIssues.NoTime, 'missing timestamps');
  Part(FIssues.BadTime, 'out-of-order timestamps');
  S := S + '.  Normalize?';
  if lblWarn.Caption <> S then
  begin
    lblWarn.Caption := S;
    rectWarn.Hint := S;   // the full text, should the strip be too narrow for it
  end;
  // one kind of problem: a single Normalize button; both: a choice
  btnFixEle.Visible := (E > 0) and (T > 0);
  btnFixSpeed.Visible := (E > 0) and (T > 0);
  if (E > 0) and (T > 0) then
    btnFixBoth.Caption := 'Both'
  else
    btnFixBoth.Caption := 'Normalize';
  rectWarn.Visible := True;
end;

procedure TfrmMain.btnFixClick(Sender: TObject);
var
  Ele, Time: Boolean;
begin
  if FDoc = nil then
    Exit;
  Ele := (Sender <> btnFixSpeed) and (FIssues.EleCount > 0);
  Time := (Sender <> btnFixEle) and (FIssues.TimeCount > 0);
  FDoc.Normalize(Ele, Time);
  FMap.Repaint;
  UpdateUI;
end;

procedure TfrmMain.btnWarnCloseClick(Sender: TObject);
begin
  FWarnDismissed := True;
  UpdateWarning;
end;

{ ---- graph / units ---------------------------------------------------------- }

procedure TfrmMain.btnGraphClick(Sender: TObject);
begin
  ShowGraph(not FGraphOn);
  SaveViewSettings;
end;

procedure TfrmMain.btnInfoClick(Sender: TObject);
begin
  ShowInfo(not FInfoOn);
  SaveViewSettings;
end;

{ Walks along the track from one outlier marker to the next: forwards to the
  first one right of the selected point, backwards to the first one left of
  it, wrapping round at the ends.  Nothing selected: the first / last one. }
procedure TfrmMain.StepOutlier(ADir: Integer);
var
  N, Pos, S, I: Integer;
begin
  if FDoc = nil then
    Exit;
  FProfile.VisibleSeg := FMap.VisibleSeg;
  FProfile.DataChanged;
  N := FProfile.OutlierCount;
  if N = 0 then
    Exit;
  if FMap.HasSelection then
    Pos := FProfile.OutlierStep(FMap.SelSeg, FMap.SelIdx, ADir)
  else
    Pos := FProfile.OutlierStep(-1, -1, ADir);
  if FProfile.OutlierPoint(Pos, S, I) then
    FMap.SelectPoint(S, I);
end;

{ Fix Elevation also works on unflagged points.  Like Fix Timestamps it
  shows what would change first and lets the user pick a smaller fix. }
procedure TfrmMain.btnFixEle1Click(Sender: TObject);
var
  Level: Integer;
  Info: TPreviewInfo;
begin
  if FFixBusy or (FDoc = nil) or not FMap.HasSelection then
    Exit;
  if ElePreviewPoints(FixLevelDefault) = nil then
    Exit;
  Info.Caption := 'Fix elevation';
  Info.What := 'elevation';
  Info.ValueUnit := UnitInfo[FProfile.Units].EleName;
  Info.ShiftUnit := Info.ValueUnit;
  Info.ShiftDecimals := 0;
  FFixBusy := True;
  try
    if not TfrmFixPreview.Confirm(ElePreviewPoints, Info, Level) then
      Exit;
  finally
    FFixBusy := False;
  end;
  if FDoc.FixElevation(FMap.SelSeg, FMap.SelIdx, Level) then
  begin
    FMap.Repaint;
    UpdateUI;
  end;
end;

{ Elevations around the selected point as they are and as the fix would leave
  them.  Every level shows the same stretch so the choices can be compared. }
function TfrmMain.ElePreviewPoints(ALevel: Integer): TArray<TPreviewPoint>;
const
  Context = 10;   // unchanged points shown either side
var
  Plan, Full: TGpxElePlan;
  Seg: TGpxSegment;
  F: Double;
  I, K, Lo, Hi: Integer;
begin
  Result := nil;
  if (FDoc = nil) or not FMap.HasSelection then
    Exit;
  if not FDoc.PlanFixElevation(FMap.SelSeg, FMap.SelIdx, Full, FixLevelDefault) then
    Exit;
  if ALevel = FixLevelDefault then
    Plan := Full
  else if not FDoc.PlanFixElevation(FMap.SelSeg, FMap.SelIdx, Plan, ALevel) then
    Exit;
  Seg := FDoc[Plan.Seg];
  Lo := Max(0, Full.First - Context);
  Hi := Min(Seg.Count - 1, Full.First + High(Full.Values) + Context);
  F := UnitInfo[FProfile.Units].EleFactor;
  SetLength(Result, Hi - Lo + 1);
  for I := Lo to Hi do
  begin
    Result[I - Lo].Number := I + 1;
    Result[I - Lo].Selected := I = FMap.SelIdx;
    if Seg[I].HasEle then
      Result[I - Lo].Before := Seg[I].Ele * F
    else
      Result[I - Lo].Before := NaN;
    Result[I - Lo].After := Result[I - Lo].Before;
    K := I - Plan.First;
    if (K >= 0) and (K <= High(Plan.Changed)) and Plan.Changed[K] then
    begin
      Result[I - Lo].Changed := True;
      Result[I - Lo].After := Plan.Values[K] * F;
      if Seg[I].HasEle then
        Result[I - Lo].Shift := (Plan.Values[K] - Seg[I].Ele) * F;
    end;
  end;
end;

{ Use the full repair range plus nearby points for every preview so the
  chart covers the same stretch when the range changes. }
function TfrmMain.TimePreviewPoints(ALevel: Integer): TArray<TPreviewPoint>;
const
  Context = 10;   // unchanged points shown either side
var
  Plan, Full: TGpxTimePlan;
  Seg: TGpxSegment;
  U: TUnitInfo;
  I, K, Lo, Hi: Integer;
begin
  Result := nil;
  if (FDoc = nil) or not FMap.HasSelection then
    Exit;
  if not FDoc.PlanFixTime(FMap.SelSeg, FMap.SelIdx, Full, FixLevelDefault) then
    Exit;
  if ALevel = FixLevelDefault then
    Plan := Full
  else if not FDoc.PlanFixTime(FMap.SelSeg, FMap.SelIdx, Plan, ALevel) then
    Exit;
  Seg := FDoc[Plan.Seg];
  Lo := Max(0, Min(Full.First, FMap.SelIdx) - Context);
  Hi := Min(Seg.Count - 1, Max(Full.First + High(Full.Times), FMap.SelIdx) + Context);
  U := UnitInfo[FProfile.Units];
  SetLength(Result, Hi - Lo + 1);
  for I := Lo to Hi do
  begin
    Result[I - Lo].Number := I + 1;
    Result[I - Lo].Before := FDoc.SpeedAt(Plan.Seg, I) * U.SpeedFactor;
    Result[I - Lo].After := FDoc.PlanSpeed(Plan, I) * U.SpeedFactor;
    Result[I - Lo].Selected := I = FMap.SelIdx;
    K := I - Plan.First;
    if (K >= 0) and (K <= High(Plan.Changed)) and Plan.Changed[K] then
    begin
      Result[I - Lo].Changed := True;
      if Seg[I].HasTime then
        Result[I - Lo].Shift := (Plan.Times[K] - Seg[I].Time) * SecsPerDay;
    end;
  end;
end;

procedure TfrmMain.btnFixTime1Click(Sender: TObject);
var
  Level: Integer;
  Info: TPreviewInfo;
begin
  if FFixBusy or (FDoc = nil) or not FMap.HasSelection then
    Exit;
  if not FDoc.CanFixTime(FMap.SelSeg, FMap.SelIdx) then
    Exit;
  Info.Caption := 'Fix timestamps';
  Info.What := 'timestamp';
  Info.ValueUnit := UnitInfo[FProfile.Units].SpeedName;
  Info.ShiftUnit := 's';
  Info.ShiftDecimals := 1;
  FFixBusy := True;
  try
    if not TfrmFixPreview.Confirm(TimePreviewPoints, Info, Level) then
      Exit;
  finally
    FFixBusy := False;
  end;
  if FDoc.FixTime(FMap.SelSeg, FMap.SelIdx, Level) then
  begin
    FMap.Repaint;
    UpdateUI;
  end;
end;

procedure TfrmMain.btnOutNextClick(Sender: TObject);
begin
  StepOutlier(1);
end;

procedure TfrmMain.btnOutPrevClick(Sender: TObject);
begin
  StepOutlier(-1);
end;

procedure TfrmMain.btnXAxisClick(Sender: TObject);
begin
  FProfile.XMode := TProfileX((Sender as TComponent).Tag);
  btnXTime.Down := FProfile.XMode = pxTime;
  btnXDist.Down := FProfile.XMode = pxDistance;
  SaveViewSettings;
end;

procedure TfrmMain.btnSettingsClick(Sender: TObject);
var
  P: TPoint;
begin
  P := btnSettings.ClientToScreen(Point(btnSettings.Width - 230, btnSettings.Height + 2));
  popUnits.Popup(P.X, P.Y);
end;

procedure TfrmMain.miSettingsClick(Sender: TObject);
begin
  if TfrmSettings.Execute then
  begin
    SaveViewSettings;
    ConfigureMap;
  end;
end;

procedure TfrmMain.miAboutClick(Sender: TObject);
begin
  TfrmAbout.Execute;
end;

procedure TfrmMain.miUnitsClick(Sender: TObject);
begin
  SetUnits(TUnitSystem((Sender as TComponent).Tag));
  SaveViewSettings;
  UpdateUI;
end;

{ ---- toolbar --------------------------------------------------------------- }

procedure TfrmMain.btnOpenClick(Sender: TObject);
begin
  if not CanDiscard then
    Exit;
  if FDoc <> nil then
    dlgOpen.InitialDir := ExtractFilePath(FDoc.FileName);
  if dlgOpen.Execute then
    OpenFile(dlgOpen.FileName);
end;

procedure TfrmMain.btnSaveClick(Sender: TObject);
begin
  if (FDoc <> nil) and FDoc.Modified then
    SaveDoc;
end;

{ ---- the arrows beside Open and Save ---------------------------------------- }

{ Opens a menu under a toolbar button, lined up with its left edge. }
procedure TfrmMain.PopupBelow(AButton: TControl; AMenu: TPopupMenu);
var
  P: TPoint;
begin
  P := AButton.ClientToScreen(Point(0, AButton.Height + 2));
  AMenu.Popup(P.X, P.Y);
end;

{ The menu's five file lines are on the form; this gives them their names. }
procedure TfrmMain.FillRecent;
var
  I: Integer;
  Item: TMenuItem;
begin
  for I := 0 to MaxRecent - 1 do
  begin
    Item := FindComponent('miRecent' + IntToStr(I + 1)) as TMenuItem;
    Item.Visible := I < Length(Settings.Recent);
    if Item.Visible then
      Item.Caption := Settings.Recent[I];
  end;
  miRecentNone.Visible := Length(Settings.Recent) = 0;
end;

procedure TfrmMain.btnOpenMoreClick(Sender: TObject);
begin
  FillRecent;
  PopupBelow(btnOpen, popOpen);
end;

procedure TfrmMain.miRecentClick(Sender: TObject);
var
  I: Integer;
  Name: string;
begin
  I := (Sender as TComponent).Tag;
  if (I < 0) or (I >= Length(Settings.Recent)) then
    Exit;
  Name := Settings.Recent[I];
  if not CanDiscard then
    Exit;
  if not FileExists(Name) then
  begin
    // gone since last time: drop it from the list
    Settings.RemoveRecent(Name);
    SaveViewSettings;
    ShowError('Could not find ' + Name);
    Exit;
  end;
  OpenFile(Name);
end;

procedure TfrmMain.btnSaveMoreClick(Sender: TObject);
begin
  PopupBelow(btnSave, popSave);
end;

procedure TfrmMain.miSaveAsClick(Sender: TObject);
begin
  SaveDocAs;
end;

procedure TfrmMain.btnUndoClick(Sender: TObject);
begin
  FMap.Undo;
end;

procedure TfrmMain.btnRedoClick(Sender: TObject);
begin
  FMap.Redo;
end;

procedure TfrmMain.btnZoomInClick(Sender: TObject);
begin
  FMap.ZoomIn;
end;

procedure TfrmMain.btnZoomOutClick(Sender: TObject);
begin
  FMap.ZoomOut;
end;

procedure TfrmMain.btnZoomFitClick(Sender: TObject);
begin
  FMap.ZoomToTrack;
end;

procedure TfrmMain.lstSegmentsSelectionChange(Sender: TObject; User: Boolean);
begin
  // The list can change through the keyboard as well as a click.
  if FListSync or (FDoc = nil) or (lstSegments.ItemIndex < 0) or
    (lstSegments.ItemIndex - 1 = FMap.VisibleSeg) then
    Exit;
  FMap.VisibleSeg := lstSegments.ItemIndex - 1;
  FMap.ZoomToTrack;
end;

{ ---- drag & drop ----------------------------------------------------------- }

{ Files dropped anywhere on the window (the form has AllowDropFiles set). }
procedure TfrmMain.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) = 0 then
    Exit;
  FQueuedFile := FileNames[0];
  // let the drop finish first; a confirmation prompt must not block the drag source
  Application.QueueAsyncCall(OpenDropped, 0);
end;

procedure TfrmMain.OpenDropped(AData: PtrInt);
begin
  if CanDiscard then
    OpenFile(FQueuedFile);
end;

procedure TfrmMain.OpenQueued(AData: PtrInt);
begin
  OpenFile(FQueuedFile);
end;

{ ---- keyboard / closing ---------------------------------------------------- }

{ The form has KeyPreview set, so every key comes through here first. }
procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  KeyChar: System.WideChar;
begin
  KeyChar := #0;
  HandleKey(Key, KeyChar, Shift);
end;

procedure TfrmMain.HandleKey(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);
var
  C: Char;
  Ctrl, Handled: Boolean;
  Step, ZoomKey: Integer;

  // letter / digit keys arrive either as a virtual key or as a character
  function Is_(AKey: Char): Boolean;
  begin
    Result := (Key = Ord(AKey)) or (C = AKey);
  end;

begin
  // while the segment list has the focus, the keys that move through a list are its own
  if lstSegments.Focused and (Shift * [ssCtrl, ssAlt, ssMeta] = []) then
    case Key of
      vkUp, vkDown, vkHome, vkEnd, vkPrior, vkNext:
        Exit;
    end;

  C := UpChar(KeyChar);
  Ctrl := (ssCtrl in Shift) or (ssMeta in Shift);
  Handled := True;

  // The LCL handles Alt shortcuts for the graph buttons.
  ZoomKey := 0;
  // Accept zoom keys from either keyboard section, with or without Ctrl.
  if not (ssAlt in Shift) then
  begin
    if (C = '+') or (C = '=') or ((KeyChar = #0) and ((Key = vkAdd) or (Key = vkEqual))) then
      ZoomKey := 1
    else if (C = '-') or ((KeyChar = #0) and ((Key = vkSubtract) or (Key = vkMinus))) then
      ZoomKey := -1;
  end;

  if ZoomKey > 0 then FMap.ZoomIn
  else if ZoomKey < 0 then FMap.ZoomOut
  else if Ctrl and not (ssAlt in Shift) then
  begin
    // Ctrl+arrows: fine positioning by one screen pixel, so the step follows the map scale
    Step := IfThen(ssShift in Shift, 10, 1);
    if Key = vkLeft then FMap.Nudge(-Step, 0)
    else if Key = vkRight then FMap.Nudge(Step, 0)
    else if Key = vkUp then FMap.Nudge(0, -Step)
    else if Key = vkDown then FMap.Nudge(0, Step)
    else if Is_('Z') then
    begin
      if ssShift in Shift then FMap.Redo else FMap.Undo;
    end
    else if Is_('Y') then FMap.Redo
    else if Is_('O') then btnOpenClick(nil)
    else if Is_('S') then
    begin
      if ssShift in Shift then SaveDocAs else btnSaveClick(nil);
    end
    else if Is_('0') or (Key = vkNumpad0) then FMap.ZoomToTrack
    else if Is_('G') then btnGraphClick(nil)
    else Handled := False;
  end
  else if ssAlt in Shift then
    Handled := False
  else
    case Key of
      vkEscape: FMap.Escape;
      vkDelete: FMap.DeleteSelected;
      vkInsert: FMap.InsertAfterSelected;
      vkF1: miAboutClick(nil);
      vkF6: FMap.ZoomToTrack;
      vkF7:
        if ssShift in Shift then btnFixTime1Click(nil) else btnFixEle1Click(nil);
      vkF8: StepOutlier(IfThen(ssShift in Shift, -1, 1));
      vkLeft:
        if FMap.HasSelection then FMap.SelectStep(-1) else FMap.PanBy(-80, 0);
      vkRight:
        if FMap.HasSelection then FMap.SelectStep(1) else FMap.PanBy(80, 0);
      vkUp:
        if not FMap.HasSelection then FMap.PanBy(0, -80);
      vkDown:
        if not FMap.HasSelection then FMap.PanBy(0, 80);
      vkHome: FMap.SelectEnd(False);
      vkEnd: FMap.SelectEnd(True);
    else
      Handled := False;
    end;

  if Handled then
  begin
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := CanDiscard;
end;

end.
