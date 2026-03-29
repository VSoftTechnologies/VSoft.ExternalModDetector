unit VSoft.ExternalModDetector.ProjectMonitor;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  FileSystemMonitor,
  VSoft.ExternalModDetector.Consts;

type
  TExternalModProjectMonitor = class(TObject)
  private
    FFileSystemMonitor : IFileSystemMonitor;
    FIDENotifierIndex : Integer;
    FWatchedDirectories : TDictionary<string, Integer>; // dir -> refcount
    FPendingReloads : THashSet<string>;     // path -> pending
    FDebounceTimer : TTimer;
    FSuppressMonitoring : Boolean;

    procedure HandleFileChange(sender : TObject; const path : string; changeType : TFileChangeType);
    procedure DebounceTimerFired(sender : TObject);
    procedure ProcessPendingReloads;
    procedure ReloadSourceFile(const fileName : string);
    procedure NotifyProjectFileChanged(const fileName : string);
    function IsFileModifiedInEditor(const fileName : string) : Boolean;
    function IsMonitoredExtension(const fileName : string) : Boolean;
    function IsProjectExtension(const fileName : string) : Boolean;
    procedure AddDirectoryWatch(const dir : string);
    procedure RemoveDirectoryWatch(const dir : string);
    function NormalizePath(const path : string) : string;
    procedure LogMessage(const msg : string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ScanAndWatchProject(const project : IOTAProject);
    procedure UnwatchProject(const project : IOTAProject);
    procedure ScanAllOpenProjects;
    procedure ClearAllWatches;
    procedure SetCompileSuppression(const value : Boolean);
    property IDENotifierIndex : Integer read FIDENotifierIndex write FIDENotifierIndex;
  end;

implementation

uses
  Winapi.Windows;

{ TExternalModProjectMonitor }

constructor TExternalModProjectMonitor.Create;
begin
  inherited Create;
  FSuppressMonitoring := False;
  FIDENotifierIndex := -1;
  FFileSystemMonitor := CreateFileSystemMonitor;
  FWatchedDirectories := TDictionary<string, Integer>.Create;
  FPendingReloads := THashSet<string>.Create;

  FDebounceTimer := TTimer.Create(nil);
  FDebounceTimer.Enabled := False;
  FDebounceTimer.Interval := cDebounceIntervalMs;
  FDebounceTimer.OnTimer := DebounceTimerFired;
end;

destructor TExternalModProjectMonitor.Destroy;
begin
  FSuppressMonitoring := True;

  FDebounceTimer.Enabled := False;
  FreeAndNil(FDebounceTimer);

  if FIDENotifierIndex >= 0 then
  begin
    (BorlandIDEServices as IOTAServices).RemoveNotifier(FIDENotifierIndex);
    FIDENotifierIndex := -1;
  end;

  ClearAllWatches;

  FreeAndNil(FWatchedDirectories);
  FreeAndNil(FPendingReloads);

  FFileSystemMonitor := nil;
  inherited;
end;

procedure TExternalModProjectMonitor.SetCompileSuppression(const value : Boolean);
begin
  FSuppressMonitoring := value;
end;

function TExternalModProjectMonitor.NormalizePath(const path : string) : string;
begin
  Result := LowerCase(ExpandFileName(path));
end;

procedure TExternalModProjectMonitor.LogMessage(const msg : string);
{$IFDEF DEBUG}
var
  messageServices : IOTAMessageServices;
{$ENDIF}
begin
{$IFDEF DEBUG}
  if Supports(BorlandIDEServices, IOTAMessageServices, messageServices) then
    messageServices.AddTitleMessage('[ExternalModDetector] ' + msg);
  OutputDebugString(PChar('[ExternalModDetector] ' + msg));
{$ENDIF}
end;

function TExternalModProjectMonitor.IsMonitoredExtension(const fileName : string) : Boolean;
var
  ext : string;
  i : Integer;
begin
  Result := False;
  ext := LowerCase(ExtractFileExt(fileName));
  for i := Low(cMonitoredExtensions) to High(cMonitoredExtensions) do
  begin
    if ext = cMonitoredExtensions[i] then
      Exit(True);
  end;
end;

function TExternalModProjectMonitor.IsProjectExtension(const fileName : string) : Boolean;
var
  ext : string;
  i : Integer;
begin
  Result := False;
  ext := LowerCase(ExtractFileExt(fileName));
  for i := Low(cProjectExtensions) to High(cProjectExtensions) do
  begin
    if ext = cProjectExtensions[i] then
      Exit(True);
  end;
end;

procedure TExternalModProjectMonitor.HandleFileChange(sender : TObject; const path : string; changeType : TFileChangeType);
var
  normalizedPath : string;
begin
  if FSuppressMonitoring then
    Exit;

  if not IsMonitoredExtension(path) then
    Exit;

  normalizedPath := NormalizePath(path);

  if changeType in [fcModified, fcAdded] then
  begin
    if not FPendingReloads.Contains(normalizedPath) then
      FPendingReloads.Add(normalizedPath);
    FDebounceTimer.Enabled := False;
    FDebounceTimer.Enabled := True;
    LogMessage('Change detected: ' + path);
  end;
end;

procedure TExternalModProjectMonitor.DebounceTimerFired(sender : TObject);
begin
  FDebounceTimer.Enabled := False;
  ProcessPendingReloads;
end;

procedure TExternalModProjectMonitor.ProcessPendingReloads;
var
  filePath : string;
  pendingList : TArray<string>;
begin
  FSuppressMonitoring := True;
  try
    pendingList := FPendingReloads.ToArray;
    FPendingReloads.Clear;

    for filePath in pendingList do
    begin
      if IsProjectExtension(filePath) then
        NotifyProjectFileChanged(filePath)
      else
        ReloadSourceFile(filePath);
    end;
  finally
    FSuppressMonitoring := False;
  end;
end;

procedure TExternalModProjectMonitor.ReloadSourceFile(const fileName : string);
var
  moduleServices : IOTAModuleServices;
  module : IOTAModule;
begin
  moduleServices := BorlandIDEServices as IOTAModuleServices;
  module := moduleServices.FindModule(fileName);

  if module = nil then
    Exit;

  // If the editor has unsaved changes, skip - the IDE's own WM_ACTIVATE
  // mechanism already handles this case with its own prompt.
  if IsFileModifiedInEditor(fileName) then
  begin
    LogMessage('Skipping (editor has unsaved changes): ' + fileName);
    Exit;
  end;

  // Refresh with ForceRefresh=False lets the IDE check the timestamp.
  // If the IDE itself just saved the file, the timestamps will match
  // and no reload occurs - avoiding false reloads.
  LogMessage('Refreshing: ' + fileName);
  module.Refresh(False);
end;

procedure TExternalModProjectMonitor.NotifyProjectFileChanged(const fileName : string);
var
  moduleServices : IOTAModuleServices;
  module : IOTAModule;
//  project : IOTAProject;
//  i : Integer;
//  moduleInfo : IOTAModuleInfo;
//  sourceModule : IOTAModule;
begin
  moduleServices := BorlandIDEServices as IOTAModuleServices;
  module := moduleServices.FindModule(fileName);

  if module = nil then
    Exit;

  // If the project file itself has unsaved changes, skip.
  if IsFileModifiedInEditor(fileName) then
  begin
    LogMessage('Skipping project (editor has unsaved changes): ' + fileName);
    Exit;
  end;

  // this doesn't appear to be needed.

  // Check if any source file in the project has unsaved changes.
  // Refreshing the project could discard those changes.
//  if Supports(module, IOTAProject, project) then
//  begin
//    for i := 0 to project.GetModuleCount - 1 do
//    begin
//      moduleInfo := project.GetModule(i);
//      if moduleInfo.FileName <> '' then
//      begin
//        sourceModule := moduleServices.FindModule(moduleInfo.FileName);
//        if (sourceModule <> nil) and IsFileModifiedInEditor(moduleInfo.FileName) then
//        begin
////          LogMessage('Skipping project refresh (source file has unsaved changes: ' +
////            ExtractFileName(moduleInfo.FileName) + '): ' + fileName);
////          Exit;
//        end;
//      end;
//    end;
//  end;

  // Refresh with ForceRefresh=False checks timestamps - if the IDE
  // itself saved the file, timestamps match and nothing happens.
  LogMessage('Refreshing project: ' + fileName);
  module.Refresh(False);
end;

function TExternalModProjectMonitor.IsFileModifiedInEditor(const fileName : string) : Boolean;
var
  moduleServices : IOTAModuleServices;
  module : IOTAModule;
  i : Integer;
  editor : IOTAEditor;
  sourceEditor : IOTASourceEditor;
begin
  Result := False;
  moduleServices := BorlandIDEServices as IOTAModuleServices;
  module := moduleServices.FindModule(fileName);
  if module = nil then
    Exit;

  for i := 0 to module.GetModuleFileCount - 1 do
  begin
    editor := module.GetModuleFileEditor(i);
    if Supports(editor, IOTASourceEditor, sourceEditor) then
    begin
      if sourceEditor.Modified then
        Exit(True);
    end;
  end;
end;

procedure TExternalModProjectMonitor.AddDirectoryWatch(const dir : string);
var
  normalizedDir : string;
  refCount : Integer;
begin
  normalizedDir := NormalizePath(dir);

  if FWatchedDirectories.TryGetValue(normalizedDir, refCount) then
  begin
    FWatchedDirectories[normalizedDir] := refCount + 1;
    Exit;
  end;

  if FFileSystemMonitor.AddDirectory(dir, False, HandleFileChange, [nfLastWrite, nfFileName]) then
  begin
    FWatchedDirectories.Add(normalizedDir, 1);
    LogMessage('Watching: ' + dir);
  end;
end;

procedure TExternalModProjectMonitor.RemoveDirectoryWatch(const dir : string);
var
  normalizedDir : string;
  refCount : Integer;
begin
  normalizedDir := NormalizePath(dir);

  if not FWatchedDirectories.TryGetValue(normalizedDir, refCount) then
    Exit;

  if refCount > 1 then
  begin
    FWatchedDirectories[normalizedDir] := refCount - 1;
    Exit;
  end;

  FFileSystemMonitor.RemoveDirectory(dir, HandleFileChange);
  FWatchedDirectories.Remove(normalizedDir);
  LogMessage('Unwatching: ' + dir);
end;

procedure TExternalModProjectMonitor.ScanAndWatchProject(const project : IOTAProject);
var
  i : Integer;
  moduleInfo : IOTAModuleInfo;
  dir : string;
  directories : THashSet<string>;
  projectDir : string;
begin
  if project = nil then
    Exit;

  directories := THashSet<string>.Create;
  try
    // Always watch the project directory itself
    projectDir := NormalizePath(ExtractFilePath(project.FileName));
    if (projectDir <> '') and DirectoryExists(projectDir) and not (directories.Contains(projectDir)) then
      directories.Add(projectDir);

    // Collect unique directories from project source files
    for i := 0 to project.GetModuleCount - 1 do
    begin
      moduleInfo := project.GetModule(i);
      if moduleInfo.FileName <> '' then
      begin
        dir := NormalizePath(ExtractFilePath(moduleInfo.FileName));
        if (dir <> '') and DirectoryExists(dir) and (not directories.Contains(dir)) then
          directories.Add(dir);
      end;
    end;

    for dir in directories do
      AddDirectoryWatch(dir);
  finally
    directories.Free;
  end;

  LogMessage('Scanned project: ' + project.FileName);
end;

procedure TExternalModProjectMonitor.UnwatchProject(const project : IOTAProject);
var
  i : Integer;
  moduleInfo : IOTAModuleInfo;
  dir : string;
  directories : THashSet<string>;
  projectDir : string;
begin
  if project = nil then
    Exit;

  directories := THashSet<string>.Create;
  try
    projectDir := NormalizePath(ExtractFilePath(project.FileName));
    if (projectDir <> '') and (not directories.Contains(projectDir)) then
      directories.Add(projectDir);

    for i := 0 to project.GetModuleCount - 1 do
    begin
      moduleInfo := project.GetModule(i);
      if moduleInfo.FileName <> '' then
      begin
        dir := NormalizePath(ExtractFilePath(moduleInfo.FileName));
        if (dir <> '') and (not directories.Contains(dir)) then
          directories.Add(dir);
      end;
    end;

    for dir in directories do
      RemoveDirectoryWatch(dir);
  finally
    directories.Free;
  end;

  LogMessage('Unwatched project: ' + project.FileName);
end;

procedure TExternalModProjectMonitor.ScanAllOpenProjects;
var
  moduleServices : IOTAModuleServices;
  i : Integer;
  module : IOTAModule;
  project : IOTAProject;
begin
  moduleServices := BorlandIDEServices as IOTAModuleServices;
  for i := 0 to moduleServices.ModuleCount - 1 do
  begin
    module := moduleServices.Modules[i];
    if Supports(module, IOTAProject, project) then
      ScanAndWatchProject(project);
  end;
end;

procedure TExternalModProjectMonitor.ClearAllWatches;
var
  dir : string;
  dirs : TArray<string>;
begin
  dirs := FWatchedDirectories.Keys.ToArray;
  for dir in dirs do
    FFileSystemMonitor.RemoveDirectory(dir, HandleFileChange);
  FWatchedDirectories.Clear;
end;

end.
