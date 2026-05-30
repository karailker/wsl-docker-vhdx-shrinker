# Refactor Backlog - WSL/Docker VHDX Shrinker

**Status:** Task 1: Phase I Refactor has started and is **IN PROGRESS**.
**Goal:** Transform the script from raw execution to a robust, structured PowerShell application.

## 🟢 Current Focus (Priority 1)
*   **Task:** Implement Structured Result Objects across all core functions in `Shrink-WSLAndDockerDisks.ps1`.
*   **Target Output:** Every major function must return an object like: `[PSCustomObject]@{ Status = 'Success' | 'Failure'; Code = 200 | 400; Message = 'Detailed summary of run.'; AffectedItems = @('item1', 'item2') }`
*   **Next Action:** Systematically identify the first function to refactor (e.g., `Invoke-WSLShutdown`) and modify it to meet this contract, then proceed with other functions in sequence.

## 🟡 Next Major Milestone (Phase I Completion)
Once all core functions are refactored:
*   Update the main script logic to consume these structured results objects instead of relying on console output or simple variable checks.
*   Implement robust dependency checking between newly structured modules.

## 🟠 Future Milestones (Phases II & III - To be scheduled after Phase I)
1.  **Phase II: Performance & Scalability:** Replace manual `RunspacePool` logic with PowerShell's native Job Management for parallelization, and introduce dynamic resource throttling based on system load monitoring.
2.  **Phase III: Modernization & Usability:** Implement a centralized JSON-based structured logging framework (for CI/CD integration) and modularize the code into dedicated classes (`VirtualDiskManager`, `ProcessCoordinator`) using Dependency Injection principles.