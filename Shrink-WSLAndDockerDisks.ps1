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

  Write-Step "Restarting script as Administrator..."
  $scriptPath = $MyInvocation.MyCommand.Definition
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"")
  if ($PSBoundParameters.ContainsKey('Mode')) { $args += @('-Mode', $Mode) }
  if ($Quick)           { $args += '-Quick' }
  if ($IncludeAllVHDX)  { $args += '-IncludeAllVHDX' }
  if ($MaxScanThreads)  { $args += @('-MaxScanThreads', $MaxScanThreads) }
  if ($ListOnly)        { $args += '-ListOnly' }
  if ($Yes)             { $args += '-Yes' }
  if ($Drives)          { $args += @('-Drives'); $args += ($Drives | ForEach-Object { $_ }) }
  if ($NoRelaunch)      { $args += '-NoRelaunch' }
  if ($LogPath)         { $args += @('-LogPath', "`"$LogPath`"") }
  if ($VerbosePreference -eq 'Continue') { $args += '-Verbose' }
  if ($WhatIfPreference) { $args += '-WhatIf' }
  Start-Process powershell -Verb RunAs -ArgumentList ($args -join ' ')
  exit
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

# ---- Native per-drive DIR sweep (fast & robust) ----
function Invoke-DirSweep {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Root,        # e.g. "C:\"
    [Parameter(Mandatory)][string[]]$Patterns   # e.g. '*.vhdx' or specific names
  )
  $patternCmds = $Patterns | ForEach-Object { 'dir /s /b /a:-d "' + (Join-Path $Root $_) + '" 2>nul' }
  $cmd = 'cmd.exe /d /c ' + ($patternCmds -join ' & ')
  Write-Verbose "[dir] $cmd"

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'cmd.exe'
  $psi.Arguments = $cmd.Substring(10)
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

  if (-not $out) { return @() }
  ($out -split "(`r`n|`n|`r)") | Where-Object { $_ } | Sort-Object -Unique
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
try { wsl.exe --shutdown | Out-Null; Write-Ok "WSL shut down." } catch { Write-Err "WSL shutdown failed: $($_.Exception.Message)" }
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
  while ($true) {
    $resp = Read-Host $prompt
    switch ($resp.ToUpperInvariant()) {
      'Y' { break }
      'YES' { break }
      'S' { Write-Host ""; $targets | ForEach-Object { Write-Host "  - $($_.FullName)"; }; Write-Host ""; continue }
      'SHOW' { Write-Host ""; $targets | ForEach-Object { Write-Host "  - $($_.FullName)"; }; Write-Host ""; continue }
      'N' { Write-Info "Operation cancelled by user."; if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }; return }
      'NO' { Write-Info "Operation cancelled by user."; if ($LogPath) { try { Stop-Transcript | Out-Null } catch {} }; return }
      default { Write-Info "Please type Y, N, or S."; continue }
    }
  }
}

Write-Step "Optimizing $($targets.Count) file(s) with Mode = $Mode ..."
Write-Info "This may take a while depending on size/fragmentation."

$success = 0; $fail = 0; $failed = @()
$total = $targets.Count; $i = 0

foreach ($vhd in $targets) {
  $i++; $pct = [int](($i / $total) * 100)
  $status = "[$i/$total] $($vhd.Name)"
  Write-Progress -Activity "Optimize-VHD" -Status $status -PercentComplete $pct
  Write-Host ""
  Write-Host ">>> $status" -ForegroundColor Cyan
  Write-Host "    Path: $($vhd.FullName)" -ForegroundColor DarkGray

  try {
    if ($PSCmdlet.ShouldProcess($vhd.FullName, "Optimize-VHD -Mode $Mode")) {
      Optimize-VHD -Path $vhd.FullName -Mode $Mode
    }
    Write-Ok "Optimized."
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
