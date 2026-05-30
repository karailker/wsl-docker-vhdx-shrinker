# Troubleshooting

## "[WARN] PowerShell is NOT running as Administrator"

**Cause:** The script was launched without Administrator privileges.

The script will automatically relaunch itself elevated via a UAC prompt. If UAC is disabled or you are running in a non-interactive context (scheduled task, CI), launch PowerShell as Administrator before running the script to avoid the prompt.

To suppress auto-elevation and fail explicitly instead, use `-NoRelaunch`:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -NoRelaunch
```

---

## "Optimize-VHD not found"

**Cause:** Hyper-V Management Tools are not installed.

**Fix:**
```powershell
# Run as Administrator
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-Tools-All /All
DISM /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V /All
```

Restart if prompted. You do not need full Hyper-V virtualisation -- only the management tools.

---

## "Access Denied" or file locked

**Cause:** WSL or Docker Desktop still has the VHDX file open.

The script runs `wsl --shutdown` automatically and then verifies WSL has stopped. If you see:

```
[WARN] WSL is still running! VHDX files may still be locked.
[WARN] Attempt 'wsl --shutdown' again and continue? [Y]es/[N]o (default: N)
```

you will be offered a chance to retry the shutdown in-place. Type `Y` to let the script retry and wait 3 seconds before proceeding. If you answer `N` (or are running with `-Yes`), the script continues and affected files may fail with a "file in use" error.

**Fix:**
1. Run `wsl --shutdown` in a terminal and wait a few seconds
2. Confirm with `wsl --list --running` (should output only the header, no distro names)
3. Quit Docker Desktop completely from the system tray (right-click the whale icon, Exit)
4. Check Task Manager for any remaining `vmmem`, `wsl`, or Docker processes
5. Re-run the script

---

## Optimization fails for a specific file

**Possible causes and fixes:**

| Symptom | Likely cause | Fix |
|---|---|---|
| "The file cannot be accessed" | File still locked | See "Access Denied" above |
| "Not enough disk space" | Optimization needs temp space | Free up space on the drive containing the VHDX |
| "The virtual disk is corrupted" | VHDX integrity issue | Run `Repair-VHD -Path <file> -All` as admin |
| Silent failure, file unchanged | `WhatIf` mode active | Do not pass `-WhatIf` to the script |

---

## No VHDX files found

**Cause:** The script only searches for `ext4.vhdx`, `docker_data.vhdx`, and `disk.vhdx` by default.

**Fix:**
- If your WSL or Docker installation uses a non-standard path or filename, use `-IncludeAllVHDX`
- If you know the drive, use `-Drives C,D` to narrow the scan and see verbose output with `-Verbose`

---

## Script hangs during scan

**Cause:** A network drive or removable drive is unresponsive.

**Fix:** Use `-Drives` to restrict the scan to specific local drives:
```powershell
.\Shrink-WSLAndDockerDisks.ps1 -Drives C,D
```

---

## Pester tests fail to install/run

**Symptom:** `Install-Module` fails with NuGet provider error.

**Fix:**
```powershell
# Install NuGet provider first (requires internet access)
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser

# Then install Pester
Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

**Symptom:** Tests fail with "Discovery failed" or parse errors.

**Cause:** Non-ASCII characters in test file string literals (em dash, arrow, etc.).

**Fix:** The test file must be pure ASCII. Check with:
```powershell
Select-String -Path .\Tests\*.ps1 -Pattern '[^\x00-\x7F]'
```

---

## After optimization: WSL won't start

This is not caused by the script. Common causes:
- WSL version mismatch after a Windows update -- run `wsl --update`
- Corrupted VHDX -- unlikely if optimization succeeded; if suspected, run `Repair-VHD`

Restart WSL with:
```powershell
wsl --shutdown
wsl
```
