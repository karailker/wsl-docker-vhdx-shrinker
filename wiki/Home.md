# Home

Welcome to the **WSL and Docker VHDX Shrinker** wiki.

WSL and Docker Desktop store their filesystems in dynamically expanding VHDX files that grow as you add data but never shrink automatically. This tool finds and compacts them using Windows' built-in `Optimize-VHD` cmdlet.

## Navigation

| Page | What it covers |
|---|---|
| [Architecture](Architecture) | Code structure, function map, design decisions |
| [Development Roadmap](Roadmap) | Planned features, phases, backlog |
| [Testing Guide](Testing) | How to run and extend the Pester test suite |
| [Troubleshooting](Troubleshooting) | Common errors and fixes |

## Quick links

- [README](../blob/main/README.md) — usage and parameter reference
- [Source](../blob/main/Shrink-WSLAndDockerDisks.ps1) — single-file PowerShell script
- [Tests](../blob/main/Tests/Shrink-WSLAndDockerDisks.Tests.ps1) — Pester 5 test suite
