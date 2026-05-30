# Troubleshooting

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

**Fix:**
1. Run `wsl --shutdown` in a terminal and wait a few seconds
2. Quit Docker Desktop completely from the system tray (right-click the whale icon, Exit)
3. Check Task Manager for any remaining `vmmem`, `wsl`, or Docker processes
4. Re-run the script

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
