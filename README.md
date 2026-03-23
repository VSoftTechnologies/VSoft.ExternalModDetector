# VSoft.ExternalModDetector

A Delphi IDE plugin that detects external file modifications in real-time and automatically reloads them in the IDE.

## The Problem

The Delphi IDE only checks for externally modified files when it receives focus (`WM_ACTIVATE`). If you are working with external tools (such as AI code assistants, version control operations, or external editors) that modify project files while the IDE already has focus, those changes go undetected until you switch away and back (at which point the IDE prompts).

## The Solution

This plugin uses Windows `ReadDirectoryChangesW` via I/O Completion Ports to monitor the directories of your open projects in real-time. When a monitored file is modified externally, the plugin calls `IOTAModule.Refresh` to reload it automatically — no focus change required.

### Behaviour

- **Source files (.pas, .inc)** — silently reloaded if the editor buffer has no unsaved changes.
- **Project files (.dproj, .dpk)** — silently refreshed if no unsaved changes exist.
- **Files with unsaved editor changes** — skipped entirely. The IDE's built-in `WM_ACTIVATE` mechanism handles these with its own prompt when you next switch focus.
- **Files saved by the IDE itself** — ignored. `Refresh(False)` checks timestamps internally, so IDE-initiated saves do not trigger a redundant reload.

## Prerequisites

- Delphi 12.x or later

- Git (for cloning with submodules)

## Building

1. Clone the repository with submodules:

   ```
   git clone --recurse-submodules https://github.com/VSoftTechnologies/VSoft.ExternalModDetector.git
   ```

   If you already cloned without submodules:

   ```
   git submodule update --init --recursive
   ```

2. Open `src\VSoft.ExternalModDetector.dproj` in the Delphi IDE.

3. Right-click the project in the Project Manager and select **Build**.

## Installing

1. After building, right-click the `VSoft.ExternalModDetector.bpl` project in the Project Manager and select **Install**.

2. You should see a confirmation message that the package was installed.

3. The plugin is now active. Open any project and it will automatically begin monitoring the project's source directories for external changes.

## Uninstalling

1. Go to **Component > Install Packages...** in the Delphi IDE.

2. Select **VSoft.ExternalModDetector** from the list and click **Remove**.

## Debugging

The plugin logs activity to the IDE's **Messages** window with the prefix `[ExternalModDetector]`. You will see messages for:

- Directories being watched/unwatched
- Projects being scanned
- Files being refreshed or skipped

## How It Works

- On project open, the plugin scans all source files in the project and begins watching their directories using `IFileSystemMonitor` (a wrapper around `ReadDirectoryChangesW` with I/O Completion Ports).
- File change notifications are debounced (200ms) to coalesce multiple rapid notifications from a single save operation.
- On project close, the directory watches are removed. Directories shared across multiple projects are reference-counted and only unwatched when the last project using them is closed.
- During compilation, monitoring is temporarily suppressed to avoid interfering with the build process.

## Dependencies

- [FileSystemMonitor](https://github.com/pyscripter/FileSystemMonitor) — included as a Git submodule under `FileSystemMonitor/`.

## License

See [LICENSE](LICENSE) for details.
