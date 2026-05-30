# WSL and Docker VHDX Shrinker

A PowerShell utility that finds and compacts VHDX disk images used by WSL (Windows Subsystem for Linux) and Docker Desktop. Virtual hard disk files grow as you add data but never shrink automatically — this script reclaims that wasted space.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges (script auto-elevates if needed)
- Hyper-V Management Tools

**Install Hyper-V Management Tools if `Optimize-VHD` is missing:**

```powershell
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-Tools-All /All
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V /All
```

## Quick Start

```powershell
# See what files would be found, without making changes
.\Shrink-WSLAndDockerDisks.ps1 -ListOnly

# Run on all drives (asks for confirmation)
.\Shrink-WSLAndDockerDisks.ps1

# Run unattended, skip confirmation
.\Shrink-WSLAndDockerDisks.ps1 -Yes
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Mode` | `Quick` \| `Full` | `Full` | Full reclaims more space; Quick is faster |
| `-Drives` | `String[]` | all drives | Limit scan to specific drive letters, e.g. `C,D` |
| `-IncludeAllVHDX` | Switch | off | Scan for any `*.vhdx`, not just WSL/Docker files |
| `-MaxScanThreads` | Int | `min(CPU, 6)` | Parallel drive scan concurrency |
| `-ListOnly` | Switch | off | Print found files, skip optimization |
| `-Yes` | Switch | off | Skip confirmation prompt |
| `-NoRelaunch` | Switch | off | Disable auto-elevation (script will fail if not already admin) |
| `-LogPath` | String | — | Write a full transcript to this path |
| `-Quick` | Switch | — | Deprecated alias for `-Mode Quick` |

## Examples

```powershell
# Scan only C and D drives, quick mode, no prompt
.\Shrink-WSLAndDockerDisks.ps1 -Mode Quick -Drives C,D -Yes

# Include all VHDX files across all drives
.\Shrink-WSLAndDockerDisks.ps1 -IncludeAllVHDX -Verbose

# Automated run with timestamped log
.\Shrink-WSLAndDockerDisks.ps1 -Yes -LogPath "C:\Logs\vhdx-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Conservative scan: one drive, minimal threads
.\Shrink-WSLAndDockerDisks.ps1 -Drives C -Mode Quick -MaxScanThreads 2
```

## How It Works

1. **Elevation check** — warns if not running as Administrator and auto-relaunches if needed
2. **WSL shutdown** — runs `wsl --shutdown` to release VHDX file locks; warns if WSL is still running after shutdown
3. **Parallel drive scan** — uses native `dir /s /b` commands across drives concurrently
4. **Filtering** — keeps only `ext4.vhdx`, `docker_data.vhdx`, `disk.vhdx` (or all `*.vhdx` with `-IncludeAllVHDX`)
5. **Confirmation** — displays found files and prompts unless `-Yes` is set
6. **Optimization** — runs `Optimize-VHD -Mode <Full|Quick>` on each file
7. **Summary** — reports success/failure counts and total MB reclaimed

## Running Tests

The project ships a [Pester 5](https://pester.dev/) test suite.

```powershell
# Install Pester 5 if not already present
Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed
```

Tests run without Administrator rights and without WSL or Hyper-V installed. All system interactions are either unit-tested via injectable parameters or verified as pure arithmetic.

## Important Notes

- **Run as Administrator** — the script auto-elevates if needed, but you will see a `[WARN]` message and a UAC prompt. For a silent run (e.g. scheduled tasks), launch PowerShell as Administrator before running the script.
- **WSL must be stopped** — the script runs `wsl --shutdown` automatically. If WSL is still running afterwards (e.g. it restarted quickly), a `[WARN]` is printed and the script continues — but affected VHDX files may fail with a "file in use" error. Run `wsl --shutdown` manually and wait a moment before retrying.
- **Close Docker Desktop** from the system tray before running for best results. WSL is shut down automatically; Docker Desktop is not.
- **Disk space** — optimization may temporarily require additional free space on the target drive.
- **After completion** — restart WSL with `wsl` and launch Docker Desktop normally.

## Troubleshooting

**`Optimize-VHD not found`** — Install Hyper-V Management Tools (see Requirements above).

**Access denied or file locked** — ensure `wsl --shutdown` has completed and Docker Desktop is fully closed.

**Optimization fails for a specific file** — check for VHDX corruption, verify read/write permissions, and ensure adequate free disk space.

## License

MIT. See [LICENSE](LICENSE) for details.

## Contributing

Issues and pull requests are welcome. See the [project wiki](../../wiki) for architecture notes and the development roadmap.
