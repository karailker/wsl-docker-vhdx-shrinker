# WSL and Docker VHDX Shrinker

A PowerShell script that automatically finds and compacts VHDX disk images used by WSL (Windows Subsystem for Linux) and Docker Desktop. Over time, these virtual hard disk files can grow significantly and fail to reclaim space even after deleting data inside the virtual machine. This script helps recover that wasted disk space.

## Overview

WSL and Docker Desktop store their file systems in dynamically expanding VHDX files. These files grow as you add data, but don't automatically shrink when you delete files. This script:

- Searches for VHDX files across all drives (or selected drives)
- Uses fast, parallel scanning with native Windows commands
- Optimizes VHDX files using Windows Hyper-V tools
- Provides progress tracking and detailed reporting

## Requirements

- Windows 10/11 with WSL and/or Docker Desktop installed
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges (script will auto-elevate if needed)
- Hyper-V Management Tools installed

### Installing Hyper-V Management Tools

If you see an error about `Optimize-VHD` not being available, enable Hyper-V Management Tools:

```powershell
# Run as Administrator
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-Tools-All /All
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V /All
```

## Quick Start

```powershell
# Basic usage - scan all drives and shrink VHDX files
.\Shrink-WSLAndDockerDisks.ps1

# Preview what would be found without making changes
.\Shrink-WSLAndDockerDisks.ps1 -ListOnly

# Scan specific drives only
.\Shrink-WSLAndDockerDisks.ps1 -Drives C,D

# Skip confirmation prompt
.\Shrink-WSLAndDockerDisks.ps1 -Yes
```

## Parameters

### `-Mode <String>`
Optimization mode for the VHDX compaction process.

- **Values:** `Quick` or `Full`
- **Default:** `Full`
- **Description:** Full mode reclaims more space but takes longer. Quick mode is faster but may reclaim less space.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Mode Quick
```

### `-Quick`
Deprecated shorthand for `-Mode Quick`. Use `-Mode Quick` instead.

### `-Drives <String[]>`
Specify which drive letters to scan.

- **Default:** All available filesystem drives
- **Description:** Provide one or more drive letters (e.g., `C`, `D`, `E`). If omitted, the script scans all drives.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Drives C,D,E
```

### `-IncludeAllVHDX`
Include all VHDX files, not just known WSL and Docker files.

- **Default:** Off (only targets `ext4.vhdx`, `docker_data.vhdx`, `disk.vhdx`)
- **Description:** When enabled, the script will find and optimize any `*.vhdx` file on the system.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -IncludeAllVHDX
```

### `-MaxScanThreads <Int>`
Control parallel scanning performance.

- **Default:** `min(ProcessorCount, 6)` with a floor of 2
- **Description:** Number of drives to scan simultaneously. Increase for faster scanning on systems with many drives, or decrease to reduce system load.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -MaxScanThreads 4
```

### `-ListOnly`
Preview mode - list discovered files without optimizing.

- **Description:** Shows what VHDX files would be found and optimized without making any changes.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -ListOnly
```

### `-Yes`
Skip the confirmation prompt before optimization.

- **Description:** Automatically proceed with optimization without asking for confirmation. Useful for automation or when you're certain about the operation.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Yes
```

### `-NoRelaunch`
Prevent automatic elevation to Administrator.

- **Description:** By default, the script will relaunch itself with Administrator privileges if needed. Use this flag to prevent that behavior (script will fail if not already elevated).

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -NoRelaunch
```

### `-LogPath <String>`
Save script output to a transcript file.

- **Description:** Specify a file path to save a complete transcript of the script execution.

**Example:**
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -LogPath "C:\Logs\vhdx-shrink.log"
```

## Usage Examples

### Example 1: Basic shrinking with preview
First, see what files would be affected:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -ListOnly
```

Then run the actual optimization:
```powershell
.\Shrink-WSLAndDockerDisks.ps1
```

### Example 2: Quick optimization on specific drives
Quickly optimize VHDX files on C and D drives only:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Mode Quick -Drives C,D -Yes
```

### Example 3: Comprehensive scan with all VHDX files
Find and optimize all VHDX files across all drives with verbose output:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -IncludeAllVHDX -Verbose
```

### Example 4: Automated execution with logging
Run unattended with logging for scheduled tasks:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Yes -LogPath "C:\Logs\vhdx-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

### Example 5: Conservative optimization
Scan only C drive with reduced parallelism for minimal system impact:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Drives C -Mode Quick -MaxScanThreads 2
```

## How It Works

1. **Administrator Check:** The script verifies it's running with Administrator privileges and auto-elevates if needed.

2. **WSL Shutdown:** Stops all WSL instances to release VHDX file locks (`wsl --shutdown`).

3. **Drive Scanning:** Uses parallel, native `dir /s /b` commands to quickly search for VHDX files across selected drives.

4. **File Filtering:** Identifies known WSL and Docker VHDX files (`ext4.vhdx`, `docker_data.vhdx`, `disk.vhdx`) unless `-IncludeAllVHDX` is specified.

5. **Confirmation:** Displays found files and prompts for confirmation (unless `-Yes` is used).

6. **Optimization:** Runs `Optimize-VHD` on each file with progress tracking.

7. **Summary:** Reports success/failure counts and elapsed time.

## Important Notes

- **Close Docker Desktop:** For best results, quit Docker Desktop from the system tray before running the script. The script will shut down WSL automatically.

- **Time Required:** Full optimization can take several minutes to hours depending on VHDX file sizes and fragmentation. Quick mode is faster but may reclaim less space.

- **Disk Space:** The optimization process may temporarily require additional disk space. Ensure you have adequate free space on the drive containing the VHDX files.

- **Running Services:** The script stops WSL automatically, but you should manually stop Docker Desktop to avoid file locking issues.

- **Restart After Optimization:** After the script completes, restart WSL with `wsl` command and launch Docker Desktop normally.

## Troubleshooting

### "Optimize-VHD not found"
Install Hyper-V Management Tools as shown in the Requirements section.

### "Access Denied" or File Locking Errors
- Ensure all WSL instances are closed (`wsl --shutdown`)
- Quit Docker Desktop completely from the system tray
- Close any applications that might be accessing WSL or Docker files

### Optimization Fails for Specific Files
- Check if the VHDX file is corrupted
- Verify you have read/write permissions
- Ensure adequate free disk space

## License

This project is released under the MIT License. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

This script uses Windows native tools and Hyper-V management cmdlets to safely optimize VHDX files without requiring third-party utilities
