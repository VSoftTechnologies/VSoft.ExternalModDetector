unit VSoft.ExternalModDetector.IDENotifier;

interface

uses
  ToolsAPI,
  VSoft.ExternalModDetector.ProjectMonitor;

type
  TExternalModIDENotifier = class(TNotifierObject, IOTANotifier, IOTAIDENotifier, IOTAIDENotifier50)
  private
    FProjectMonitor : TExternalModProjectMonitor;
    function FindProjectByFileName(const fileName : string) : IOTAProject;
  public
    constructor Create(projectMonitor : TExternalModProjectMonitor);

    // IOTAIDENotifier
    procedure FileNotification(notifyCode : TOTAFileNotification;
      const fileName : string; var cancel : Boolean);
    procedure BeforeCompile(const project : IOTAProject;
      var cancel : Boolean); overload;
    procedure AfterCompile(succeeded : Boolean); overload;

    // IOTAIDENotifier50
    procedure BeforeCompile(const project : IOTAProject;
      isCodeInsight : Boolean; var cancel : Boolean); overload;
    procedure AfterCompile(succeeded : Boolean;
      isCodeInsight : Boolean); overload;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

{ TExternalModIDENotifier }

constructor TExternalModIDENotifier.Create(projectMonitor : TExternalModProjectMonitor);
begin
  inherited Create;
  FProjectMonitor := projectMonitor;
end;

function TExternalModIDENotifier.FindProjectByFileName(const fileName : string) : IOTAProject;
var
  moduleServices : IOTAModuleServices;
  i : Integer;
  module : IOTAModule;
  project : IOTAProject;
begin
  Result := nil;
  moduleServices := BorlandIDEServices as IOTAModuleServices;
  for i := 0 to moduleServices.ModuleCount - 1 do
  begin
    module := moduleServices.Modules[i];
    if Supports(module, IOTAProject, project) then
    begin
      if SameText(project.FileName, fileName) then
        Exit(project);
    end;
  end;
end;

procedure TExternalModIDENotifier.FileNotification(notifyCode : TOTAFileNotification;
  const fileName : string; var cancel : Boolean);
var
  project : IOTAProject;
begin
  case notifyCode of
    ofnProjectDesktopLoad :
    begin
      project := FindProjectByFileName(fileName);
      if project <> nil then
      begin
        FProjectMonitor.ScanAndWatchProject(project);
        OutputDebugString(PChar('[ExternalModDetector] Project loaded: ' + fileName));
      end;
    end;

    ofnFileClosing :
    begin
      if SameText(ExtractFileExt(fileName), '.dproj') or
         SameText(ExtractFileExt(fileName), '.dpk') then
      begin
        project := FindProjectByFileName(fileName);
        if project <> nil then
        begin
          FProjectMonitor.UnwatchProject(project);
          OutputDebugString(PChar('[ExternalModDetector] Project closing: ' + fileName));
        end;
      end;
    end;

    ofnActiveProjectChanged :
    begin
      // Rescan when active project changes to ensure we're watching everything
      project := FindProjectByFileName(fileName);
      if project <> nil then
        FProjectMonitor.ScanAndWatchProject(project);
    end;
  end;
end;

procedure TExternalModIDENotifier.BeforeCompile(const project : IOTAProject;
  var cancel : Boolean);
begin
  FProjectMonitor.SetCompileSuppression(True);
end;

procedure TExternalModIDENotifier.AfterCompile(succeeded : Boolean);
begin
  FProjectMonitor.SetCompileSuppression(False);
end;

procedure TExternalModIDENotifier.BeforeCompile(const project : IOTAProject;
  isCodeInsight : Boolean; var cancel : Boolean);
begin
  if not isCodeInsight then
    FProjectMonitor.SetCompileSuppression(True);
end;

procedure TExternalModIDENotifier.AfterCompile(succeeded : Boolean;
  isCodeInsight : Boolean);
begin
  if not isCodeInsight then
    FProjectMonitor.SetCompileSuppression(False);
end;

end.
