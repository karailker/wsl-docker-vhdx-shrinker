# Architecture

## Overview

The script is a single PowerShell file (`Shrink-WSLAndDockerDisks.ps1`) with a clear separation between helper functions and the main execution body. All functions are defined before the `# --- main ---` region so they can be extracted and unit-tested via PowerShell's AST parser without executing the script body.

## Function Map

```
Shrink-WSLAndDockerDisks.ps1
|
+-- UI helpers (Write-Title, Write-Info, Write-Ok, Write-Err, Write-Step)
|     Pure output wrappers. No logic, no side effects.
|
+-- Test-IsAdmin
|     Returns [bool]. Checks WindowsPrincipal for Administrator role.
|
+-- Ensure-Admin
|     Calls Test-IsAdmin. If not elevated and -NoRelaunch not set,
|     relaunches the script via Start-Process -Verb RunAs and exits.
|     Uses $relaunchArgs (not $args) to avoid clobbering PowerShell's
|     automatic $args variable.
|
+-- Invoke-WSLShutdown
|     Accepts an injectable -ShutdownCommand [scriptblock] parameter.
|     Default: { & wsl.exe --shutdown 2>&1 }
|     Returns: [PSCustomObject]@{ Status; Message; Details }
|     Status is always 'Success' or 'Failure' -- never null.
|
+-- Get-FileSystemRoots
|     Accepts -OnlyDrives [string[]].
|     If drives specified: normalises drive letters to "X:\" format,
|     removes duplicates, checks Test-Path for each.
|     If no drives: falls back to Get-PSDrive + DriveInfo.GetDrives().
|     Returns: [string[]] of existing drive roots, sorted unique.
|
+-- Invoke-ParallelDirSweeps
|     Accepts -Roots, -Patterns, -Throttle.
|     Creates a RunspacePool (size = Throttle, default = min(CPU,6)).
|     Each runspace runs a native "dir /s /b" CMD sweep per drive.
|     Aggregates results, sanitises paths (strips invalid chars, enforces
|     .vhdx extension), then materialises via Get-Item -LiteralPath.
|     Returns: [System.IO.FileInfo[]]
|
+-- main body
      Runs after all functions are defined.
      Flow:
        1. Handle deprecated -Quick switch
        2. Start transcript if -LogPath set
        3. Start stopwatch
        4. Call Ensure-Admin
        5. Call Invoke-WSLShutdown
        6. Check Optimize-VHD availability
        7. Call Get-FileSystemRoots
        8. Call Invoke-ParallelDirSweeps
        9. Apply name filter (unless -IncludeAllVHDX)
       10. Dedup by FullName
       11. Display found files
       12. Exit if -ListOnly
       13. Confirmation prompt (unless -Yes)
       14. Optimization loop with before/after size capture
       15. Summary with MB reclaimed
       16. Stop transcript
```

## Design Decisions

### Structured result objects (Phase I)

`Invoke-WSLShutdown` returns a `PSCustomObject` with `Status`, `Message`, and `Details` properties rather than writing to stdout and relying on `$?`. This makes the main body code readable and makes the function independently unit-testable.

All future functions extracted during refactoring (see [Roadmap](Roadmap)) will follow this pattern.

### Injectable dependencies

`Invoke-WSLShutdown` accepts a `-ShutdownCommand [scriptblock]` parameter whose default value invokes `wsl.exe --shutdown`. In tests, any scriptblock can be passed — allowing success/failure scenarios without requiring WSL to be installed. This pattern will be extended to `Optimize-VHD` interaction in Phase II.

### Native `dir /s /b` sweep

`Invoke-ParallelDirSweeps` uses `cmd.exe /c dir /s /b` rather than `Get-ChildItem -Recurse`. Reason: `dir /s /b` is significantly faster on deep directory trees with many subdirectories because it bypasses .NET's `FileSystemEnumerator` overhead. On a system with hundreds of directories, the difference is 5-10x.

### RunspacePool for parallelism

Drives are scanned concurrently using a `RunspacePool` rather than `ForEach-Object -Parallel` (PS7+) to maintain compatibility with PowerShell 5.1. The child runspace script block is self-contained (no function calls) because runspaces do not inherit the parent session's functions.

## File Structure

```
wsl-docker-vhdx-shrinker/
  Shrink-WSLAndDockerDisks.ps1   # main script
  Tests/
    Shrink-WSLAndDockerDisks.Tests.ps1  # Pester 5 tests
  wiki/                          # wiki source files
  ARCHITECTURE_PLAN.md           # architectural roadmap document
  BACKLOG_PLAN.md                # phased backlog
  README.md
  LICENSE
  .gitignore
```
