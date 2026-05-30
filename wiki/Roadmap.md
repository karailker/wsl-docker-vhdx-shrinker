# Development Roadmap

This document tracks planned improvements in three phases. Status markers:
- **Done** -- shipped
- **In Progress** -- active work
- **Planned** -- scoped, not yet started
- **Backlog** -- idea, no timeline

---

## Phase I: Stability and Reliability (Priority: Highest)

Goal: eliminate silent failures, enforce structured return values.

| # | Item | Status | Notes |
|---|---|---|---|
| 1.1 | Fix confirmation loop break bug (Y/YES infinite loop) | **Done** | `switch` `break` only exits switch, not `while`. Fixed with `$confirmed` flag |
| 1.2 | Fix `$args` variable shadow in `Ensure-Admin` | **Done** | Renamed to `$relaunchArgs` |
| 1.3 | Remove dead `Invoke-DirSweep` function | **Done** | Never called; parallel sweep re-implements inline |
| 1.4 | `Invoke-WSLShutdown` structured result | **Done** | Returns `{Status; Message; Details}` |
| 1.5 | Injectable `ShutdownCommand` parameter | **Done** | Enables unit testing without WSL installed |
| 1.6 | Before/after size reporting | **Done** | Reports MB reclaimed per file and total |
| 1.7 | Pester 5 test suite | **Done** | 35 tests, all passing, no elevation required |
| 1.8 | `Invoke-OptimizeVHD` structured result | **Planned** | Same pattern as `Invoke-WSLShutdown`; injectable `-OptimizeCommand` for testing |
| 1.9 | Docker Desktop graceful shutdown | **Planned** | Detect if Docker Desktop is running; instruct user or attempt graceful stop |
| 1.10 | Dependency check function | **Planned** | Extract `Optimize-VHD` availability check into `Test-HyperVTools` returning structured result |
| 1.11 | WSL still-running check + warn | **Done** | `Test-WSLRunning` checks `wsl --list --running` after shutdown; prints `[WARN]` if any distro still active |
| 1.12 | Admin pre-flight warning | **Done** | `Ensure-Admin` prints `[WARN]` before relaunching elevated; `Write-Warn` helper added |
| 1.13 | Fix `Optimize-VHD` non-terminating error | **Done** | Added `-ErrorAction Stop`; failures now correctly counted in `$fail` instead of `$success` |

---

## Phase II: Performance and Scalability (Priority: Medium)

Goal: improve parallelism and add dynamic throttling.

| # | Item | Status | Notes |
|---|---|---|---|
| 2.1 | Replace `RunspacePool` with PS7 `ForEach-Object -Parallel` | **Planned** | Conditional: use `-Parallel` on PS7+, keep RunspacePool on PS5.1 |
| 2.2 | Dynamic throttling via system load | **Planned** | Use `Get-Counter '\Processor(_Total)\% Processor Time'` to scale down concurrency under load |
| 2.3 | Scan progress: per-drive estimated completion | **Backlog** | Show ETA per drive based on directory count from a fast pre-scan |
| 2.4 | Incremental scan (re-scan only changed drives) | **Backlog** | Cache last-scanned timestamp per drive root; skip drives unchanged since last run |

---

## Phase III: Modernisation and Usability (Priority: Lowest)

Goal: improve developer experience, logging, and code organisation.

| # | Item | Status | Notes |
|---|---|---|---|
| 3.1 | JSON structured logging (`-JsonLog` parameter) | **Planned** | Emit a JSON log alongside transcript; one object per VHDX with timestamps, sizes, result |
| 3.2 | `-OutputFormat JSON` parameter | **Planned** | Emit the summary as a JSON object for CI/pipeline consumption |
| 3.3 | Unique execution ID | **Planned** | Add `[guid]::NewGuid()` run ID to all log output for correlation |
| 3.4 | `VirtualDiskManager` class | **Backlog** | Encapsulate VHDX discovery + optimisation into a class; enables DI |
| 3.5 | `ProcessCoordinator` class | **Backlog** | Encapsulate WSL/Docker lifecycle into a class |
| 3.6 | Scheduled Task helper | **Backlog** | `-Schedule` parameter that registers a Windows Scheduled Task to run weekly |
| 3.7 | GitHub Actions CI | **Planned** | Run Pester tests on push via Windows runner; block merge on test failure |
| 3.8 | PSScriptAnalyzer enforcement | **Planned** | Add to CI; fix all existing warnings |

---

## Completed

| Item | Version / PR |
|---|---|
| Parallel drive scanning with RunspacePool | original |
| Progress bars for scan and optimization | original |
| `dir /s /b` native sweep for performance | original |
| Auto-elevation via `Start-Process -Verb RunAs` | original |
| Structured result objects (`Invoke-WSLShutdown`) | phase-I |
| Before/after size reporting | phase-I |
| Pester 5 test suite (35 tests) | phase-I |
| Bug fixes: break loop, $args shadow, dead code | phase-I |
| WSL still-running check (`Test-WSLRunning`) | phase-I |
| Admin pre-flight warning (`Write-Warn` in `Ensure-Admin`) | phase-I |
| Fix `Optimize-VHD` non-terminating error (`-ErrorAction Stop`) | phase-I |

---

## How to Contribute

1. Pick a **Planned** item
2. Open an issue to discuss scope
3. Create a branch, implement, add/update tests
4. Open a PR — CI must be green

See [Architecture](Architecture) for code structure and design patterns.
