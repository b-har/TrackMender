# Keeps the Lazarus project in step with the Delphi one.
#
# D12 holds the source that is edited.  The units below are copied to LAZ with
# the handful of changes Free Pascal / the LCL need (listed as rules, so every
# difference between the two projects is written down here).  Not generated,
# and edited by hand in LAZ: the forms (uMain.lfm, uFixPreview.lfm, uAbout.lfm,
# uSettingsForm.lfm), the project files, and the Lazarus-only units uFmx, uCompat
# and uHttp.
#
#   python sync_laz.py            all units
#   python sync_laz.py uGpx.pas   one unit
#
# Validate every requested unit before writing any Lazarus files.
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'D12'
DST = ROOT / 'LAZ'

def nl(s):
    return s.replace('\r\n', '\n').replace('\n', '\r\n')

RULES = {}

RULES['uGpx.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;",
     "{$mode delphi}{$H+}{$POINTERMATH ON}\n\ninterface\n\nuses\n  SysUtils, Classes, Math, Generics.Collections;"),
    ("  System.IOUtils, System.StrUtils, System.DateUtils;", "  StrUtils, DateUtils, uCompat;"),
    # FPC's TList<T> has no List property: a subclass hands out the item array
    ("  PGpxPoint = ^TGpxPoint;\n",
     "  PGpxPoint = ^TGpxPoint;\n\n"
     "  TGpxPointList = class(TList<TGpxPoint>)\n"
     "  private\n"
     "    function GetList: PGpxPoint; inline;\n"
     "  public\n"
     "    property List: PGpxPoint read GetList;\n"
     "  end;\n"),
    ("    FPoints: TList<TGpxPoint>;", "    FPoints: TGpxPointList;"),
    ("  FPoints := TList<TGpxPoint>.Create;", "  FPoints := TGpxPointList.Create;"),
    ("function TGpxSegment.GetCount: Integer;",
     "function TGpxPointList.GetList: PGpxPoint;\nbegin\n  Result := @FItems[0];\nend;\n\n"
     "function TGpxSegment.GetCount: Integer;"),
]

RULES['uTiles.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Classes, System.Types, System.SyncObjs,\n"
     "  System.Generics.Collections, System.Generics.Defaults, FMX.Graphics;",
     "{$mode delphi}{$H+}\n\ninterface\n\nuses\n  SysUtils, Classes, Types, SyncObjs,\n"
     "  Generics.Collections, Generics.Defaults, uFmx, uCompat;"),
    ("  System.IOUtils, System.Hash, System.Net.HttpClient, System.Net.URLClient;", "  uHttp;"),
    # FPC 3.2 has no anonymous methods: the queued call is a small object instead
    ("{ TTileQueue }\n\nconstructor TTileQueue.Create;",
     "{ Carries one finished download over to the main thread. }\n"
     "type\n"
     "  TTileDelivery = class\n"
     "  private\n"
     "    FKeep: ITileQueue;\n"
     "    FOwner: TTileQueue;\n"
     "    FKey: UInt64;\n"
     "    FData: TBytes;\n"
     "    FErr: string;\n"
     "    procedure Run;\n"
     "  public\n"
     "    constructor Create(AOwner: TTileQueue; AKey: UInt64; const AData: TBytes; const AErr: string);\n"
     "  end;\n\n"
     "constructor TTileDelivery.Create(AOwner: TTileQueue; AKey: UInt64; const AData: TBytes;\n"
     "  const AErr: string);\n"
     "begin\n"
     "  inherited Create;\n"
     "  FKeep := AOwner;\n"
     "  FOwner := AOwner;\n"
     "  FKey := AKey;\n"
     "  FData := AData;\n"
     "  FErr := AErr;\n"
     "  TThread.Queue(nil, Run);\n"
     "end;\n\n"
     "procedure TTileDelivery.Run;\n"
     "begin\n"
     "  try\n"
     "    if Assigned(FOwner.FOnResult) then\n"
     "      FOwner.FOnResult(FKey, FData, FErr);\n"
     "  finally\n"
     "    Free;\n"
     "  end;\n"
     "end;\n\n"
     "{ TTileQueue }\n\nconstructor TTileQueue.Create;"),
    ("  TThread.Queue(nil,\n"
     "    procedure\n"
     "    begin\n"
     "      if (Keep <> nil) and Assigned(FOnResult) then\n"
     "        FOnResult(AKey, Data, Err);\n"
     "    end);\n",
     "  if Keep <> nil then\n"
     "    TTileDelivery.Create(Self, AKey, Data, Err);\n"),
    ("procedure TTileStore.Evict;\nvar",
     "type\n  TTilePair = TPair<UInt64, TTileEntry>;\n\n"
     "function ByLastUsed(constref L, R: TTilePair): Integer;\n"
     "begin\n"
     "  Result := L.Value.LastUsed - R.Value.LastUsed;\n"
     "end;\n\n"
     "procedure TTileStore.Evict;\nvar"),
    ("    Items.Sort(TComparer<TPair<UInt64, TTileEntry>>.Construct(\n"
     "      function(const L, R: TPair<UInt64, TTileEntry>): Integer\n"
     "      begin\n"
     "        Result := L.Value.LastUsed - R.Value.LastUsed;\n"
     "      end));\n",
     "    Items.Sort(TComparer<TTilePair>.Construct(ByLastUsed));\n"),
    # FPC cannot parse a nested specialization inside an expression
    ("  Items: TList<TPair<UInt64, TTileEntry>>;\n  Pair: TPair<UInt64, TTileEntry>;",
     "  Items: TList<TTilePair>;\n  Pair: TTilePair;"),
    ("  Items := TList<TPair<UInt64, TTileEntry>>.Create;", "  Items := TList<TTilePair>.Create;"),
]

RULES['uMapView.pas'] = [
    ("interface\n\n"
     "uses\n  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,\n"
     "  System.Math.Vectors, FMX.Types, FMX.Controls, FMX.Graphics, uGpx, uTiles;",
     "{$mode delphi}{$H+}\n\ninterface\n\n"
     "uses\n  SysUtils, Classes, Types, Math, Controls, uFmx, uGpx, uTiles;"),
    ("  TMapView = class(TControl)", "  TMapView = class(TFmxControl)"),
    ("  CanFocus := True;\n  AutoCapture := True;\n", "  TabStop := True;\n"),
    ("  if Scene <> nil then\n    Scale := Scene.GetSceneScale\n  else\n    Scale := 1;\n", "  Scale := SceneScale;\n"),
]

RULES['uProfile.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,\n"
     "  System.Math.Vectors,\n  FMX.Types, FMX.Controls, FMX.Graphics, uGpx;",
     "{$mode delphi}{$H+}\n\ninterface\n\nuses\n  SysUtils, Classes, Types, Math, Controls, uFmx, uGpx;"),
    ("  TProfileView = class(TControl)", "  TProfileView = class(TFmxControl)"),
    ("  System.Generics.Collections, System.Generics.Defaults, System.DateUtils, System.StrUtils;",
     "  Generics.Collections, Generics.Defaults, DateUtils, StrUtils, uCompat;"),
    ("    TArray.Sort<Double>(Sorted);", "    TArrayHelper<Double>.Sort(Sorted);"),
    ("      TArray.Sort<Double>(Sorted, TComparer<Double>.Default, 0, N);",
     "      TArrayHelper<Double>.Sort(Sorted, TComparer<Double>.Default, 0, N);"),
    # FPC 3.2 has no anonymous methods: the two orderings are plain functions
    ("procedure TProfileView.Recalc;",
     "function ByScore(constref L, R: TOutlier): Integer;\n"
     "begin\n"
     "  Result := CompareValue(R.Score, L.Score);\n"
     "  if Result = 0 then\n"
     "    Result := L.K - R.K;\n"
     "end;\n\n"
     "function ByPosition(constref L, R: TOutlier): Integer;\n"
     "begin\n"
     "  Result := L.K - R.K;\n"
     "  if Result = 0 then\n"
     "    Result := CompareValue(R.Score, L.Score);\n"
     "end;\n\n"
     "procedure TProfileView.Recalc;"),
    ("    Cand.Sort(TComparer<TOutlier>.Construct(\n"
     "      function(const L, R: TOutlier): Integer\n"
     "      begin\n"
     "        Result := CompareValue(R.Score, L.Score);\n"
     "        if Result = 0 then\n"
     "          Result := L.K - R.K;\n"
     "      end));\n",
     "    Cand.Sort(TComparer<TOutlier>.Construct(ByScore));\n"),
    ("    Cand.Sort(TComparer<TOutlier>.Construct(\n"
     "      function(const L, R: TOutlier): Integer\n"
     "      begin\n"
     "        Result := L.K - R.K;\n"
     "        if Result = 0 then\n"
     "          Result := CompareValue(R.Score, L.Score);\n"
     "      end));\n",
     "    Cand.Sort(TComparer<TOutlier>.Construct(ByPosition));\n"),
]

RULES['uFixPreview.pas'] = [
    ("interface\n\n"
     "uses\n  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math, System.StrUtils,\n"
     "  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Objects,\n"
     "  FMX.Layouts, FMX.Controls.Presentation;",
     "{$mode delphi}{$H+}\n\ninterface\n\n"
     "uses\n  SysUtils, Types, Classes, Math, StrUtils,\n"
     "  Forms, Controls, Graphics, StdCtrls, ExtCtrls, Buttons, BGRABitmap, BGRABitmapTypes, uFmx;"),
    ("    rectChart: TRectangle;", "    rectChart: TPanel;"),
    ("    layButtons: TLayout;\n    layLegend: TLayout;\n    lineNow: TRectangle;",
     "    layButtons: TPanel;\n    layLegend: TPanel;\n    lineNow: TShape;"),
    ("    lineAfter: TRectangle;", "    lineAfter: TShape;"),
    ("    rectBand: TRectangle;", "    rectBand: TShape;"),
    # the LCL paint box hands out an LCL canvas: PaintChart is the FMX paint
    # handler unchanged, pbChartPaint gives it an FMX style canvas to draw on
    ("    procedure pbChartPaint(Sender: TObject; Canvas: TCanvas);\n",
     "    procedure pbChartPaint(Sender: TObject);\n"),
    ("    procedure SetupLevels;\n  public\n"
     "    procedure KeyDown(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState); override;\n",
     "    procedure SetupLevels;\n"
     "    procedure PaintChart(Canvas: TCanvas; AWidth, AHeight: Single);\n  public\n"),
    ("{$R *.fmx}", "{$R *.lfm}"),
    # Alt+A / Alt+C: the LCL does the underlined letters of buttons itself
    ("procedure TfrmFixPreview.KeyDown(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);\n"
     "var\n  C: Char;\nbegin\n  C := UpCase(Char(KeyChar));\n"
     "  if (ssAlt in Shift) and ((Key = Ord('A')) or (C = 'A') or (Key = Ord('C')) or (C = 'C')) then\n"
     "  begin\n    if (Key = Ord('A')) or (C = 'A') then\n      ModalResult := mrOk\n    else\n"
     "      ModalResult := mrCancel;\n    Key := 0;\n    KeyChar := #0;\n    Exit;\n  end;\n  inherited;\nend;\n\n",
     ""),
    ("re", r"\b((?:lbl|btn)\w+)\.Text\b", r"\1.Caption", 7),
    ("re", r"\.IsPressed\b", ".Down", 3),
    ("procedure TfrmFixPreview.pbChartPaint(Sender: TObject; Canvas: TCanvas);\n",
     "procedure TfrmFixPreview.pbChartPaint(Sender: TObject);\n"
     "var\n"
     "  Bmp: TBGRABitmap;\n"
     "  C: TCanvas;\n"
     "  Scale: Single;\n"
     "begin\n"
     "  if (pbChart.Width < 1) or (pbChart.Height < 1) then\n"
     "    Exit;\n"
     "  Scale := Font.PixelsPerInch / 96;\n"
     "  Bmp := TBGRABitmap.Create(pbChart.Width, pbChart.Height, BGRAWhite);\n"
     "  C := TCanvas.Create;\n"
     "  try\n"
     "    C.Bitmap := Bmp;\n"
     "    C.Scale := Scale;\n"
     "    PaintChart(C, pbChart.Width / Scale, pbChart.Height / Scale);\n"
     "    Bmp.Draw(pbChart.Canvas, 0, 0, True);\n"
     "  finally\n"
     "    C.Free;\n"
     "    Bmp.Free;\n"
     "  end;\n"
     "end;\n\n"
     "procedure TfrmFixPreview.PaintChart(Canvas: TCanvas; AWidth, AHeight: Single);\n"),
    ("  W := pbChart.Width;\n  H := pbChart.Height;\n", "  W := AWidth;\n  H := AHeight;\n"),
]

RULES['uAbout.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,\n"
     "  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Objects,\n"
     "  FMX.Controls.Presentation;",
     "{$mode delphi}{$H+}\n\ninterface\n\nuses\n  SysUtils, Types, Classes, Math,\n"
     "  Forms, Controls, Graphics, StdCtrls, ExtCtrls;"),
    ("{$R *.fmx}", "{$R *.lfm}"),
    ("uses\n  Winapi.Windows;\n", "uses\n  fileinfo, winpeimagereader, elfreader, machoreader;\n"),
    ("  Edition = 'DEL';", "  Edition = 'LAZ';"),
    # Free Pascal reads the version resource through its fileinfo unit
    ('block',
     "function FileVersionText: string;\n",
     "function AppVersion: string;\nbegin\n",
     "function FileVersionText: string;\n"
     "var\n"
     "  Info: TFileVersionInfo;\n"
     "begin\n"
     "  Result := '';\n"
     "  Info := TFileVersionInfo.Create(nil);\n"
     "  try\n"
     "    try\n"
     "      Info.ReadFileInfo;\n"
     "      Result := Trim(Info.VersionStrings.Values['FileVersion']);\n"
     "    except\n"
     "      // no version resource in this build\n"
     "    end;\n"
     "  finally\n"
     "    Info.Free;\n"
     "  end;\n"
     "end;\n\n"
     "function AppVersion: string;\nbegin\n"),
    ("re", r"\b((?:lbl|btn)\w+)\.Text\b", r"\1.Caption", 1),
]

# uSettings is the same file in both projects (its few differences are marked
# with FPC inside the unit), so it is copied as it is
RULES['uSettings.pas'] = []

RULES['uSettingsForm.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,\n"
     "  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Controls.Presentation,\n"
     "  uSettings;",
     "{$mode delphi}{$H+}\n\ninterface\n\nuses\n  SysUtils, Types, Classes, Math,\n"
     "  Forms, Controls, StdCtrls, uSettings;"),
    ("{$R *.fmx}", "{$R *.lfm}"),
]

MAIN_FIELDS_OLD = "    pnlToolbar: TLayout;\n"
MAIN_FIELDS_END = "    dlgOpen: TOpenDialog;\n"
MAIN_FIELDS_NEW = """    pnlToolbar: TPanel;
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
"""

RULES['uMain.pas'] = [
    ("interface\n\nuses\n  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,\n"
     "  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,\n"
     "  FMX.Objects, FMX.Layouts, FMX.ListBox, FMX.Controls.Presentation, FMX.Menus,\n"
     "  uGpx, uMapView, uProfile, uFixPreview;",
     "{$mode delphi}{$H+}\n\ninterface\n\nuses\n  SysUtils, Types, Classes, LCLType,\n"
     "  Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Buttons, Menus,\n"
     "  uGpx, uMapView, uProfile, uFixPreview;"),
    ('block', MAIN_FIELDS_OLD, MAIN_FIELDS_END, MAIN_FIELDS_NEW),
    ("    procedure lstSegmentsItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);\n"
     "    procedure lstSegmentsChange(Sender: TObject);\n",
     "    procedure lstSegmentsSelectionChange(Sender: TObject; User: Boolean);\n"
     "    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);\n"
     "    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);\n"),
    ("    FGraphOn: Boolean;\n", "    FGraphOn: Boolean;\n    FQueuedFile: string;      // opened once the message loop is idle\n"),
    ("    procedure ShowError(const AText: string);\n  public\n"
     "    procedure KeyDown(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState); override;\n"
     "    procedure DragOver(const Data: TDragObject; const Point: TPointF;\n"
     "      var Operation: TDragOperation); override;\n"
     "    procedure DragDrop(const Data: TDragObject; const Point: TPointF); override;\n",
     "    procedure ShowError(const AText: string);\n"
     "    procedure OpenQueued(AData: PtrInt);\n"
     "    procedure OpenDropped(AData: PtrInt);\n"
     "    procedure HandleKey(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);\n"
     "  public\n"),
    ("{$R *.fmx}", "{$R *.lfm}"),
    ("  System.Math, System.StrUtils, System.Character, FMX.DialogService,\n  uSettings, uSettingsForm, uAbout;",
     "  Math, StrUtils, uCompat, uSettings, uSettingsForm, uAbout;"),
    ("  AppDescription = 'Frankie''s GPX Track Mender';\n",
     "  AppDescription = 'Frankie''s GPX Track Mender';\n\n"
     "  // FMX names of the virtual keys\n"
     "  vkUp = VK_UP;           vkDown = VK_DOWN;       vkLeft = VK_LEFT;     vkRight = VK_RIGHT;\n"
     "  vkHome = VK_HOME;       vkEnd = VK_END;         vkPrior = VK_PRIOR;   vkNext = VK_NEXT;\n"
     "  vkAdd = VK_ADD;         vkSubtract = VK_SUBTRACT;\n"
     "  vkEqual = VK_OEM_PLUS;  vkMinus = VK_OEM_MINUS; vkNumpad0 = VK_NUMPAD0;\n"
     "  vkEscape = VK_ESCAPE;   vkDelete = VK_DELETE;   vkInsert = VK_INSERT;\n"
     "  vkF1 = VK_F1;           vkF6 = VK_F6;           vkF7 = VK_F7;         vkF8 = VK_F8;\n"),
    ("    FileName := ParamStr(1);\n"
     "    TThread.ForceQueue(nil,\n"
     "      procedure\n"
     "      begin\n"
     "        OpenFile(FileName);\n"
     "      end);\n",
     "    FileName := ParamStr(1);\n"
     "    FQueuedFile := FileName;\n"
     "    Application.QueueAsyncCall(OpenQueued, 0);\n"),
    ("  FMap.Align := TAlignLayout.Contents;\n",
     "  FMap.Align := alClient;\n"
     "  // the design-time info card goes onto the map, pinned to its top right\n"
     "  // corner: as a child window of the map it is never painted over\n"
     "  layInfo.Parent := FMap;\n"
     "  layInfo.AnchorSideTop.Control := FMap;\n"
     "  layInfo.AnchorSideRight.Control := FMap;\n"
     "  layInfo.AnchorSideRight.Side := asrRight;\n"
     "  layInfo.BorderSpacing.Top := 12;\n"
     "  layInfo.BorderSpacing.Right := 12;\n"
     "  layInfo.Anchors := [akTop, akRight];\n"),
    ("  FProfile.Align := TAlignLayout.Client;\n  FProfile.Margins.Rect := TRectF.Create(1, 0, 1, 1);\n",
     "  FProfile.Align := alClient;\n"),
    ("  L, T, W, H, I: Integer;\n  R: TRectF;\n", "  L, T, W, H, I: Integer;\n  R, Hit: TRect;\n"),
    ("    R := TRectF.Create(L + 40, T, L + W - 40, T + 30);\n"
     "    OnScreen := False;\n"
     "    for I := 0 to Screen.DisplayCount - 1 do\n"
     "      if Screen.Displays[I].WorkArea.IntersectsWith(R) then\n"
     "        OnScreen := True;\n",
     "    R := Rect(L + 40, T, L + W - 40, T + 30);\n"
     "    OnScreen := False;\n"
     "    for I := 0 to Screen.MonitorCount - 1 do\n"
     "      if IntersectRect(Hit, Screen.Monitors[I].WorkareaRect, R) then\n"
     "        OnScreen := True;\n"),
    ("      Position := TFormPosition.Designed;\n", "      Position := poDesigned;\n"),
    ("  btnGraph.IsPressed := AShow;\n"
     "  if AShow then\n"
     "    pathGraph.Fill.Color := $FF2A78D6\n"
     "  else\n"
     "    pathGraph.Fill.Color := pathZoomFit.Fill.Color;\n",
     "  btnGraph.Down := AShow;\n"),
    ("    pnlGraph.Position.Y := pnlStatus.Position.Y - pnlStatus.Margins.Top - pnlGraph.Height;\n"
     "    splGraph.Position.Y := pnlGraph.Position.Y - splGraph.Height;\n",
     "    pnlGraph.Top := pnlStatus.Top - pnlStatus.BorderSpacing.Top - pnlGraph.Height;\n"
     "    splGraph.Top := pnlGraph.Top - splGraph.Height;\n"),
    ("  btnInfo.IsPressed := AShow;\n"
     "  if AShow then\n"
     "    pathInfo.Fill.Color := $FF2A78D6\n"
     "  else\n"
     "    pathInfo.Fill.Color := pathZoomFit.Fill.Color;\n",
     "  btnInfo.Down := AShow;\n"),
    ("  layInfo.Visible := True;\n",
     "  layInfo.Visible := True;\n  layInfo.BringToFront;\n"),
    ("re", r"\b((?:lbl|btn)\w+)\.Text\b", r"\1.Caption", 16),
    ("re", r"\.IsPressed\b", ".Down", 4),
    ("re", r"\.IsChecked\b", ".Checked", 4),
    ("      Item.Text := Settings.Recent[I];\n", "      Item.Caption := Settings.Recent[I];\n"),
    ("var\n  P: TPointF;\nbegin\n  P := AButton.LocalToScreen(PointF(0, AButton.Height + 2));\n",
     "var\n  P: TPoint;\nbegin\n  P := AButton.ClientToScreen(Point(0, AButton.Height + 2));\n"),
    ("  TDialogService.MessageDialog(AText, TMsgDlgType.mtError, [TMsgDlgBtn.mbOK],\n"
     "    TMsgDlgBtn.mbOK, 0, nil);\n",
     "  MessageDlg(AppTitle, AText, mtError, [mbOK], 0);\n"),
    ("  Answer := mrCancel;\n"
     "  TDialogService.MessageDialog(\n"
     "    Format('Save changes to %s?', [ExtractFileName(FDoc.FileName)]),\n"
     "    TMsgDlgType.mtConfirmation,\n"
     "    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel], TMsgDlgBtn.mbYes, 0,\n"
     "    procedure(const AResult: TModalResult)\n"
     "    begin\n"
     "      Answer := AResult;\n"
     "    end);\n",
     "  Answer := MessageDlg(AppTitle,\n"
     "    Format('Save changes to %s?', [ExtractFileName(FDoc.FileName)]),\n"
     "    mtConfirmation, [mbYes, mbNo, mbCancel], 0);\n"),
    ("  lstSegments.BeginUpdate;\n", "  lstSegments.Items.BeginUpdate;\n"),
    ("    lstSegments.EndUpdate;\n", "    lstSegments.Items.EndUpdate;\n"),
    ("    splSegments.Position.X := pnlSegments.Position.X + pnlSegments.Width;\n",
     "    splSegments.Left := pnlSegments.Left + pnlSegments.Width;\n"),
    ("        if lstSegments.ListItems[I + 1].Text <> S then\n"
     "          lstSegments.ListItems[I + 1].Text := S;\n",
     "        if lstSegments.Items[I + 1] <> S then\n"
     "          lstSegments.Items[I + 1] := S;\n"),
    ("procedure TfrmMain.btnSettingsClick(Sender: TObject);\nvar\n  P: TPointF;\nbegin\n"
     "  P := btnSettings.LocalToScreen(PointF(btnSettings.Width - 230, btnSettings.Height + 2));\n",
     "procedure TfrmMain.btnSettingsClick(Sender: TObject);\nvar\n  P: TPoint;\nbegin\n"
     "  P := btnSettings.ClientToScreen(Point(btnSettings.Width - 230, btnSettings.Height + 2));\n"),
    ('block',
     "procedure TfrmMain.lstSegmentsItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);\n",
     "procedure TfrmMain.lstSegmentsChange(Sender: TObject);\n",
     "procedure TfrmMain.lstSegmentsSelectionChange(Sender: TObject; User: Boolean);\n"),
    ('block',
     "procedure TfrmMain.DragOver(const Data: TDragObject; const Point: TPointF;\n",
     "procedure TfrmMain.KeyDown(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);\n",
     "{ Files dropped anywhere on the window (the form has AllowDropFiles set). }\n"
     "procedure TfrmMain.FormDropFiles(Sender: TObject; const FileNames: array of string);\n"
     "begin\n"
     "  if Length(FileNames) = 0 then\n"
     "    Exit;\n"
     "  FQueuedFile := FileNames[0];\n"
     "  // let the drop finish first; a confirmation prompt must not block the drag source\n"
     "  Application.QueueAsyncCall(OpenDropped, 0);\n"
     "end;\n\n"
     "procedure TfrmMain.OpenDropped(AData: PtrInt);\n"
     "begin\n"
     "  if CanDiscard then\n"
     "    OpenFile(FQueuedFile);\n"
     "end;\n\n"
     "procedure TfrmMain.OpenQueued(AData: PtrInt);\n"
     "begin\n"
     "  OpenFile(FQueuedFile);\n"
     "end;\n\n"
     "{ ---- keyboard / closing ---------------------------------------------------- }\n\n"
     "{ The form has KeyPreview set, so every key comes through here first. }\n"
     "procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);\n"
     "var\n"
     "  KeyChar: System.WideChar;\n"
     "begin\n"
     "  KeyChar := #0;\n"
     "  HandleKey(Key, KeyChar, Shift);\n"
     "end;\n\n"
     "procedure TfrmMain.HandleKey(var Key: Word; var KeyChar: System.WideChar; Shift: TShiftState);\n"),
    ("  if lstSegments.IsFocused and (Shift * [ssCtrl, ssAlt, ssCommand] = []) then\n"
     "    case Key of\n"
     "      vkUp, vkDown, vkHome, vkEnd, vkPrior, vkNext:\n"
     "        begin\n"
     "          inherited;\n"
     "          Exit;\n"
     "        end;\n"
     "    end;\n",
     "  if lstSegments.Focused and (Shift * [ssCtrl, ssAlt, ssMeta] = []) then\n"
     "    case Key of\n"
     "      vkUp, vkDown, vkHome, vkEnd, vkPrior, vkNext:\n"
     "        Exit;\n"
     "    end;\n"),
    ("  C := Char(KeyChar).ToUpper;\n  Ctrl := (ssCtrl in Shift) or (ssCommand in Shift);\n",
     "  C := UpChar(KeyChar);\n  Ctrl := (ssCtrl in Shift) or (ssMeta in Shift);\n"),
    # Alt + underlined letter: the LCL does that for its buttons by itself
    ('block',
     "  if (ssAlt in Shift) and not Ctrl and not (ssShift in Shift) and\n",
     "  ZoomKey := 0;\n",
     "  // The LCL handles Alt shortcuts for the graph buttons.\n"
     "  ZoomKey := 0;\n"),
    ("  if Handled then\n  begin\n    Key := 0;\n    KeyChar := #0;\n  end\n  else\n    inherited;\nend;\n",
     "  if Handled then\n  begin\n    Key := 0;\n    KeyChar := #0;\n  end;\nend;\n"),
    ("re", r"TWindowState\.(ws\w+)", r"\1", 3),
]

def utf8_literals(s):
    """'a'#$00B7'b' -> 'a·b'.  Lazarus sources are UTF-8 and so are its strings,
    so characters are written as themselves instead of as UTF-16 codes."""
    run = re.compile(r"(?:'(?:[^'\r\n]|'')*'|#\$[0-9A-Fa-f]{2,4}|#\d+)+")
    tok = re.compile(r"'(?:[^'\r\n]|'')*'|#\$[0-9A-Fa-f]{2,4}|#\d+")
    def fix(m):
        text = m.group(0)
        if not re.search(r"#\$[0-9A-Fa-f]{4}", text):
            return text
        out, cur = [], None          # cur: text of the quoted piece being built
        for t in tok.findall(text):
            if t.startswith("'"):
                cur = (cur or '') + t[1:-1]
            elif t.startswith('#$') and int(t[2:], 16) >= 0x80:
                cur = (cur or '') + chr(int(t[2:], 16))
            else:
                if cur is not None:
                    out.append("'" + cur + "'")
                    cur = None
                out.append(t)
        if cur is not None:
            out.append("'" + cur + "'")
        return ''.join(out)
    return run.sub(fix, s)

def render_unit(name):
    if name not in RULES:
        raise ValueError(f'Unknown unit: {name}')
    s = (SRC / name).read_bytes().decode('utf-8-sig')
    for rule in RULES[name]:
        if rule[0] == 'block':
            start, end, replacement = map(nl, rule[1:])
            for marker in (start, end):
                if s.count(marker) != 1:
                    raise ValueError(f'{name}: expected one block marker {marker[:80]!r}')
            a = s.index(start)
            b = s.index(end)
            if b < a + len(start):
                raise ValueError(f'{name}: block markers out of order for {start[:80]!r}')
            s = s[:a] + replacement + s[b + len(end):]
            continue
        if rule[0] == 're':
            _, pattern, replacement, expected = rule
            s, matches = re.subn(pattern, replacement, s)
        else:
            pattern, replacement = map(nl, rule[:2])
            expected = rule[2] if len(rule) > 2 else 1
            matches = s.count(pattern)
            s = s.replace(pattern, replacement)
        if matches != expected:
            raise ValueError(f'{name}: expected {expected} matches, found {matches} for {pattern[:80]!r}')
    return utf8_literals(s).encode('utf-8')


def main(names):
    rendered = {name: render_unit(name) for name in names}
    for name, content in rendered.items():
        (DST / name).write_bytes(content)
        print('ported', name)


if __name__ == '__main__':
    try:
        main(sys.argv[1:] or RULES)
    except (ValueError, OSError) as error:
        sys.exit(str(error))
