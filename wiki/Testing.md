# Testing Guide

## Setup

```powershell
# Install Pester 5 (one-time)
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

## Run

```powershell
# From the repo root
Invoke-Pester -Path .\Tests -Output Detailed
```

Expected output:
```
Tests Passed: 35, Failed: 0, Skipped: 0
```

## What is covered

| Describe block | What is tested |
|---|---|
| `Get-FileSystemRoots` | Drive letter normalisation (bare letter, `X:`, `X:\`), lowercase uppercasing, deduplication, non-existent drives skipped, invalid tokens ignored, fallback to `Get-PSDrive` |
| `Invoke-WSLShutdown` | Success with output, success with no output, failure via thrown exception, result object shape (Status/Message/Details always present) |
| `Confirmation loop` | `Y` and `yes` set `$confirmed`, `S` does not, unknown input does not |
| `Size savings arithmetic` | 10GB to 8GB = 2048 MB, equal sizes = 0 MB, sub-MB savings, negative (file grew), GB display rounding |
| `Scan pattern selection` | Default 3 patterns present and count, wildcard pattern, case-insensitive name filter |
| `Result object shape` | Status/Message/Details properties always present; Status is always `Success` or `Failure` |

## Design principles

**No elevation required.** Every test runs without Administrator privileges. Functions that call system tools (`wsl.exe`, `Optimize-VHD`) use injectable parameters, so tests pass real scriptblocks as substitutes.

**No real hardware required.** Tests mock `Test-Path` where needed and use fake scriptblocks for WSL shutdown. They never touch real VHDX files.

**AST function extraction.** `BeforeAll` uses `[System.Management.Automation.Language.Parser]::ParseFile()` to extract function definitions from the script without executing the main body. This avoids the admin guard throwing during test discovery.

**Pester mock scope awareness.** Mocks on `Test-Path` inside `It` blocks are scoped to that block. To avoid ordering issues, assertions on sorted output use `-Contain` (set membership) rather than index-based assertions like `$r[0]`.

## Adding tests

1. Add a new `Describe` block (or `Context` inside an existing one) in `Tests/Shrink-WSLAndDockerDisks.Tests.ps1`
2. Functions extracted in `BeforeAll` are available directly — no import needed
3. For functions that call system tools, add a `-<Something>Command [scriptblock]` parameter to the function and pass test scriptblocks in the `It` block
4. Run `Invoke-Pester -Path .\Tests -Output Detailed` to verify

## Encoding note

The test file must be plain ASCII (no Unicode characters in string literals or comments). The Windows PowerShell 5.1 parser will fail on non-ASCII characters inside string literals. Use only ASCII in `Describe`, `Context`, and `It` name strings.
