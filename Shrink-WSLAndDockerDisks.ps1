<#
.SYNOPSIS
  Scan (optionally selected) drives for VHDX files and shrink them (WSL + Docker aware).

.DESCRIPTION
  Generic, fast discovery using a parallel, throttled native `dir /s /b` sweep. Targets:
    - WSL:           ext4.vhdx
    - Docker WSL:    docker_data.vhdx
    - Docker variant:disk.vhdx
  Optionally include ALL *.vhdx via -IncludeAllVHDX.

  Extras:
    - Disk selection:      -Drives C,D,E (scan only those drives)
    - Scan progress bar:   shows per-drive completion
    - Optimization progress bar
    - Found-file confirmation: prompt list summary before Optimize-VHD (bypass with -Yes)

.PARAMETER Mode
  'Quick' | 'Full' (default: Full). Full reclaims more.

.PARAMETER Quick
  (Deprecated) alias of -Mode Quick.

.PARAMETER Drives
  One or more drive letters (e.g., 'C','D','E'). If omitted, scan ALL filesystem drives.

.PARAMETER IncludeAllVHDX
  Include ANY '*.vhdx' in addition to known names.

.PARAMETER MaxScanThreads
  Max parallel drive scans. Default: min(ProcessorCount, 6), floor 2.

.PARAMETER ListOnly
  Only list discovered files; do NOT optimize.

.PARAMETER Yes
  Skip the "found-file confirmation" prompt (assume Yes).

.PARAMETER NoRelaunch
  Skip auto-elevation (script requires Admin).

.PARAMETER LogPath
  Start-Transcript to this path.

.EXAMPLES
  .\Shrink-WSLAndDockerDisks.ps1 -Drives C,D -ListOnly -Verbose
  .\Shrink-WSLAndDockerDisks.ps1 -IncludeAllVHDX -Yes
  .\Shrink-WSLAndDockerDisks.ps1 -Mode Quick -MaxScanThreads 4
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  [ValidateSet('Quick','Full')]
  [string]$Mode = 'Full',

  [switch]$Quick,

  [string[]]$Drives,

  [switch]$IncludeAllVHDX,

  [int]$MaxScanThreads,

  [switch]$ListOnly,

  [switch]$Yes,

  [switch]$NoRelaunch,

  [string]$LogPath
)

#region UI helpers
function Write-Title { param([string]$Text)
  Write-Host ""
  Write-Host "===============================" -ForegroundColor DarkCyan
  Write-Host " $Text" -ForegroundColor Cyan
  Write-Host "===============================" -ForegroundColor DarkCyan
  Write-Host ""
}
function Write-Info { param([string]$Text) Write-Host "[*] $Text" -ForegroundColor Gray }
function Write-Ok   { param([string]$Text) Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Err  { param([string]$Text) Write-Host "[!!] $Text" -ForegroundColor Red }
function Write-Step { param([string]$Text) Write-Host ">> $Text" -ForegroundColor Yellow }
function Write-Warn { param([string]$Text) Write-Host "[WARN] $Text" -ForegroundColor Yellow }
#endregion

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ensure-Admin {
  param([switch]$NoRelaunch)
  if (Test-IsAdmin) { return }
  if ($NoRelaunch) { throw "This script must be run as Administrator (or omit -NoRelaunch)." }

  Write-Warn "PowerShell is NOT running as Administrator."
  Write-Warn "Optimize-VHD requires elevated privileges. Relaunching as Administrator..."
  $scriptPath = $MyInvocation.MyCommand.Definition
  $relaunchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"")
  if ($PSBoundParameters.ContainsKey('Mode')) { $relaunchArgs += @('-Mode', $Mode) }
  if ($Quick)           { $relaunchArgs += '-Quick' }
  if ($IncludeAllVHDX)  { $relaunchArgs += '-IncludeAllVHDX' }
  if ($MaxScanThreads)  { $relaunchArgs += @('-MaxScanThreads', $MaxScanThreads) }
  if ($ListOnly)        { $relaunchArgs += '-ListOnly' }
  if ($Yes)             { $relaunchArgs += '-Yes' }
  if ($Drives)          { $relaunchArgs += @('-Drives'); $relaunchArgs += ($Drives | ForEach-Object { $_ }) }
  if ($NoRelaunch)      { $relaunchArgs += '-NoRelaunch' }
  if ($LogPath)         { $relaunchArgs += @('-LogPath', "`"$LogPath`"") }
  if ($VerbosePreference -eq 'Continue') { $relaunchArgs += '-Verbose' }
  if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }
  Start-Process powershell -Verb RunAs -ArgumentList ($relaunchArgs -join ' ')
  exit
}

function Test-WSLRunning {
  # wsl --list --running exits with output if any distro is running, silent if none
  $out = & wsl.exe --list --running 2>&1
  # Output is always present (header line at minimum); check for actual distro entries
  $lines = @($out | Where-Object { $_ -and ($_ -notmatch '^\s*$') })
  # First line is a header ("Windows Subsystem for Linux Distributions:" or similar)
  return $lines.Count -gt 1
}

function Invoke-WSLShutdown {
  [CmdletBinding()]
  param(
    # Injectable for testing: default invokes wsl.exe --shutdown.
    [scriptblock]$ShutdownCommand = { & wsl.exe --shutdown 2>&1 }
  )
  $result = [PSCustomObject]@{ Status = 'Success'; Message = ''; Details = @() }
  try {
    $wslOutput = & $ShutdownCommand
    $result.Message = 'WSL shut down successfully.'
    $result.Details = @($wslOutput | Where-Object { $_ })
  } catch {
    $result.Status  = 'Failure'
    $result.Message = "WSL shutdown failed: $($_.Exception.Message)"
  }
  return $result
}

function Get-FileSystemRoots {
  param([string[]]$OnlyDrives)
  if ($OnlyDrives -and $OnlyDrives.Count -gt 0) {
    $norm = $OnlyDrives | ForEach-Object {
      if ($_ -match '^[A-Za-z]$') { "{0}:\" -f $_.ToUpper() }
      elseif ($_ -match '^[A-Za-z]:\\?$') { $_.ToUpper().TrimEnd('\') + '\' }
    } | Where-Object { $_ }
    return $norm | Where-Object { Test-Path $_ } | Sort-Object -Unique
  }

  $roots = @()
  try { $roots += (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }) } catch {}
  try {
    [System.IO.DriveInfo]::GetDrives() | ForEach-Object {
      try { if ($_.IsReady) { $roots += $_.RootDirectory.FullName } } catch {}
    }
  } catch {}
  $roots | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
}

# ---- Parallelize per-drive sweeps w/ progress ----
function Invoke-ParallelDirSweeps {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$Roots,
    [Parameter(Mandatory)][string[]]$Patterns,
    [int]$Throttle
  )

  $roots = $Roots | Where-Object { Test-Path $_ } | Sort-Object -Unique
  if (-not $roots) { return @() }

  if (-not $Throttle -or $Throttle -lt 1) {
    $Throttle = [Math]::Max(2, [Math]::Min([Environment]::ProcessorCount, 6))
  }

  $iss  = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Throttle, $iss, $Host)
  $pool.Open()

  $jobs = New-Object System.Collections.Generic.List[object]

  # Child code: build and run native DIR per-drive (no external function calls)
  $childCode = @'
param($root, $patterns)

# Build CMD command: one /s /b sweep per pattern
$patternCmds = foreach ($p in $patterns) { 'dir /s /b /a:-d "' + (Join-Path $root $p) + '" 2>nul' }
$cmd = 'cmd.exe /d /c ' + ($patternCmds -join ' & ')

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = $cmd.Substring(10)  # strip leading 'cmd.exe '
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$null = $p.Start()
$p.WaitForExit()
$out = $p.StandardOutput.ReadToEnd()
$p.Dispose()

$lines = if ($out) { $out -split "(`r`n|`n|`r)" | Where-Object { $_ } } else { @() }

# First emit a small diag object for parent verbose logs, then file paths
[PSCustomObject]@{ Root = $root; Matches = @($lines).Count }
$lines
'@

  $total = $roots.Count
  $done  = 0
  Write-Progress -Activity "Scanning drives" -Status "Starting..." -PercentComplete 0

  foreach ($r in $roots) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $pool
    $null = $ps.AddScript($childCode).AddArgument($r).AddArgument($Patterns)
    $handle = $ps.BeginInvoke()
    $jobs.Add([pscustomobject]@{ PS=$ps; Handle=$handle; Root=$r })
  }

  $linesAll = New-Object System.Collections.Generic.List[string]
  foreach ($j in $jobs) {
    try {
      $out = $j.PS.EndInvoke($j.Handle)
      $done++
      $pct = [math]::Floor(($done / $total) * 100)
      Write-Progress -Activity "Scanning drives" -Status "Completed $done of $total (last: $($j.Root))" -PercentComplete $pct

      if ($out) {
        $diag = $out[0]
        if ($diag -is [psobject] -and $diag.PSObject.Properties['Root']) {
          Write-Verbose ("[dir] Root={0} Matches={1}" -f $diag.Root, $diag.Matches)
          if ($out.Count -gt 1) {
            $rest = $out | Select-Object -Skip 1
            foreach ($line in $rest) {
              if ($null -ne $line -and $line -ne '') { [void]$linesAll.Add([string]$line) }
            }
          }
        } else {
          foreach ($line in $out) {
            if ($null -ne $line -and $line -ne '') { [void]$linesAll.Add([string]$line) }
          }
        }
      }
    } catch {
      Write-Verbose ("[dir] Root={0} failed: {1}" -f $j.Root, $_.Exception.Message)
    } finally {
      $j.PS.Dispose()
    }
  }

  Write-Progress -Activity "Scanning drives" -Completed -Status "Done"
  $pool.Close(); $pool.Dispose()

  # Sanitize and validate paths before materializing
    $invalidChars = [System.String]::Join('', [System.IO.Path]::GetInvalidPathChars())
    $invalidRe    = '[{0}]' -f ([Regex]::Escape($invalidChars))

    $cleanLines = foreach ($line in $linesAll) {
    $s = ($line -as [string]).Trim('"',' ',"`t","`r","`n","`0")
    if ([string]::IsNullOrWhiteSpace($s)) { continue }
    if ($s -match $invalidRe)            { continue }  # skip any path with invalid chars
    if ($s -notmatch '\.vhdx$')          { continue }  # keep only *.vhdx lines
    $s
    }

    $cleanLines |
    Sort-Object -Unique |
    ForEach-Object {
        try {
        if (Test-Path -LiteralPath $_) { Get-Item -LiteralPath $_ }
        } catch {
        # ignore lines that still fail Test-Path due to provider quirks, permissions, etc.
        }
    }
}

# ------------------------ main ------------------------

if ($PSBoundParameters.ContainsKey('Quick') -and -not $PSBoundParameters.ContainsKey('Mode')) {
  Write-Info "The -Quick switch is deprecated. Prefer: -Mode Quick"
  $Mode = 'Quick'
}

if ($LogPath) {
  try { Start-Transcript -Path $LogPath -Append -UseMinimalHeader -ErrorAction Stop | Out-Null; Write-Info "Transcript: $LogPath" } catch { Write-Err "Transcript error: $($_.Exception.Message)" }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Title "Generic VHDX Shrinker for WSL & Docker (All Drives)"
Write-Info  "Mode: $Mode (Optimize-VHD -Mode $Mode)"
Write-Verbose "PowerShell: $($PSVersionTable.PSVersion)"
Write-Verbose "Elevated : $(Test-IsAdmin)"

Ensure-Admin -NoRelaunch:$NoRelaunch

Write-Step "Stopping WSL (releases VHDX locks)..."
$wslResult = Invoke-WSLShutdown
if ($wslResult.Status -eq 'Success') { Write-Ok $wslResult.Message } else { Write-Err $wslResult.Message }

if (Test-WSLRunning) {
  Write-Warn "WSL is still running! VHDX files may still be locked."

  # Offer to retry shutdown interactively (skip when -Yes or non-interactive)
  $retried = $false
  if (-not $Yes -and [Environment]::UserInteractive) {
    $resp = Read-Host "[WARN] Attempt 'wsl --shutdown' again and continue? [Y]es/[N]o (default: N)"
    if ($resp -match '^[Yy]') {
      Write-Step "Retrying WSL shutdown..."
      $wslResult2 = Invoke-WSLShutdown
      if ($wslResult2.Status -eq 'Success') { Write-Ok $wslResult2.Message } else { Write-Err $wslResult2.Message }
      Start-Sleep -Seconds 3
      if (Test-WSLRunning) {
        Write-Warn "WSL is STILL running after retry. Some files may fail to optimize."
      } else {
        Write-Ok "WSL is now stopped."
        $retried = $true
      }
    }
  }

  if (-not $retried -and Test-WSLRunning) {
    Write-Warn "Continuing anyway — some files may fail to optimize."
    Write-Warn "To fix: run 'wsl --shutdown', wait a moment, then re-run this script."
  }
} else {
  Write-Ok "WSL is stopped. VHDX locks released."
}

Write-Info "Quit Docker Desktop from the tray for best results."

if (-not (Get-Command Optimize-VHD -ErrorAction SilentlyContinue)) {
  Write-Err "Optimize-VHD not found. Enable Hyper-V Management Tools."
  Write-Host "  DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-Tools-All /All" -ForegroundColor DarkGray
  Write-Host "  DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V /All"          -ForegroundColor DarkGray
  if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }
  return
}

Write-Step "Scanning filesystem drives..."
$roots = Get-FileSystemRoots -OnlyDrives:$Drives
if (-not $roots) {
  Write-Err "No filesystem drives detected (or invalid -Drives selection)."
  if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }
  return
}

[string[]]$scanPatterns = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
if ($IncludeAllVHDX) { $scanPatterns = @('*.vhdx') }

$throttle = if ($PSBoundParameters.ContainsKey('MaxScanThreads')) { [Math]::Max(1, $MaxScanThreads) } else { 0 }

$items = Invoke-ParallelDirSweeps -Roots $roots -Patterns $scanPatterns -Throttle $throttle

if (-not $items -or $items.Count -eq 0) {
  Write-Err "No target VHDX files found."
  Write-Info ("Searched drives {0} with patterns: {1}" -f ($roots -join ', '), ($scanPatterns -join ', '))
  if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }
  return
}

# If not IncludeAllVHDX, keep only known names (case-insensitive)
if (-not $IncludeAllVHDX) {
  $nameSet = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
  $items = $items | Where-Object { $nameSet -contains $_.Name.ToLowerInvariant() }
}

$targets = $items | Group-Object FullName | ForEach-Object { $_.Group[0] }

Write-Host ""
Write-Host "Found VHDX files:" -ForegroundColor Green
$targets | ForEach-Object { Write-Host "  - $($_.FullName)" -ForegroundColor DarkGreen }
Write-Host ""

if ($ListOnly) {
  Write-Step "ListOnly: no optimization will be performed."
  if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }
  return
}

# ------- Found-file confirmation (unless -Yes) -------
if (-not $Yes) {
  $count = $targets.Count
  $prompt = "Proceed to optimize $count file(s)? [Y]es/[N]o/[S]how details"
  $confirmed = $false
  while (-not $confirmed) {
    $resp = Read-Host $prompt
    switch ($resp.ToUpperInvariant()) {
      'Y'    { $confirmed = $true }
      'YES'  { $confirmed = $true }
      'S'    { Write-Host ""; $targets | ForEach-Object { Write-Host "  - $($_.FullName)" }; Write-Host "" }
      'SHOW' { Write-Host ""; $targets | ForEach-Object { Write-Host "  - $($_.FullName)" }; Write-Host "" }
      'N'    { Write-Info "Operation cancelled by user."; if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }; return }
      'NO'   { Write-Info "Operation cancelled by user."; if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }; return }
      default { Write-Info "Please type Y, N, or S." }
    }
  }
}

Write-Step "Optimizing $($targets.Count) file(s) with Mode = $Mode ..."
Write-Info "This may take a while depending on size/fragmentation."

$success = 0; $fail = 0; $failed = @()
$total = $targets.Count; $i = 0
$totalBytesBefore = 0L; $totalBytesAfter = 0L

foreach ($vhd in $targets) {
  $i++; $pct = [int](($i / $total) * 100)
  $status = "[$i/$total] $($vhd.Name)"
  Write-Progress -Activity "Optimize-VHD" -Status $status -PercentComplete $pct
  Write-Host ""
  Write-Host ">>> $status" -ForegroundColor Cyan
  Write-Host "    Path: $($vhd.FullName)" -ForegroundColor DarkGray

  try {
    $sizeBefore = (Get-Item -LiteralPath $vhd.FullName -ErrorAction SilentlyContinue).Length
    if ($PSCmdlet.ShouldProcess($vhd.FullName, "Optimize-VHD -Mode $Mode")) {
      Optimize-VHD -Path $vhd.FullName -Mode $Mode -ErrorAction Stop
    }
    $sizeAfter = (Get-Item -LiteralPath $vhd.FullName -ErrorAction SilentlyContinue).Length
    if ($null -ne $sizeBefore -and $null -ne $sizeAfter) {
      $totalBytesBefore += $sizeBefore
      $totalBytesAfter  += $sizeAfter
      $saved = $sizeBefore - $sizeAfter
      $savedMB = [math]::Round($saved / 1MB, 1)
      Write-Ok ("Optimized. Saved {0:N1} MB ({1:N0} -> {2:N0} bytes)" -f $savedMB, $sizeBefore, $sizeAfter)
    } else {
      Write-Ok "Optimized."
    }
    $success++
  } catch {
    Write-Err "Failed."
    Write-Info "Reason: $($_.Exception.Message)"
    $fail++; $failed += $vhd.FullName
  }
}

Write-Progress -Activity "Optimize-VHD" -Completed -Status "Done"

$sw.Stop()
Write-Host ""
Write-Title "Summary"
Write-Ok "Optimized : $success"
if ($success -gt 0 -and $totalBytesBefore -gt 0) {
  $totalSavedMB = [math]::Round(($totalBytesBefore - $totalBytesAfter) / 1MB, 1)
  $totalBeforeGB = [math]::Round($totalBytesBefore / 1GB, 2)
  $totalAfterGB  = [math]::Round($totalBytesAfter  / 1GB, 2)
  Write-Ok ("Reclaimed : {0:N1} MB  ({1:N2} GB -> {2:N2} GB)" -f $totalSavedMB, $totalBeforeGB, $totalAfterGB)
}
if ($fail -gt 0) {
  Write-Err "Failed    : $fail"
  Write-Host "Failed items:" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkRed }
} else {
  Write-Ok "All optimizations succeeded."
}
Write-Info ("Elapsed   : {0:N1} seconds" -f $sw.Elapsed.TotalSeconds)

Write-Host ""
Write-Step "Next"
Write-Info "Start WSL again with:  wsl"
Write-Info "Start Docker Desktop from the Start menu/tray as usual."
Write-Host ""

if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }
