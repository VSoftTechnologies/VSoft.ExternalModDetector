unit VSoft.ExternalModDetector.Consts;
//
interface

const
  cDebounceIntervalMs = 200;
  cMonitoredExtensions : array[0..7] of string = ('.pas', '.inc', '.dpr', '.dproj', '.dpk', '.h', '.cpp', '.rc');
  cProjectExtensions : array[0..2] of string = ('.dproj', '.cbproj', '.dpk');

implementation

end.
