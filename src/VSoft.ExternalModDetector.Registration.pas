unit VSoft.ExternalModDetector.Registration;

interface

procedure Register;
// Test ssdfds
implementation

uses
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  VSoft.ExternalModDetector.ProjectMonitor,
  VSoft.ExternalModDetector.IDENotifier;

var
  GProjectMonitor : TExternalModProjectMonitor;

procedure Register;
var
  notifier : TExternalModIDENotifier;
  notifierIndex : Integer;
begin
  GProjectMonitor := TExternalModProjectMonitor.Create;

  notifier := TExternalModIDENotifier.Create(GProjectMonitor);
  notifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(notifier);
  GProjectMonitor.IDENotifierIndex := notifierIndex;

  GProjectMonitor.ScanAllOpenProjects;

  OutputDebugString('[ExternalModDetector] Plugin registered');
end;

initialization

finalization
  FreeAndNil(GProjectMonitor);
  OutputDebugString('[ExternalModDetector] Plugin finalized');

end.
