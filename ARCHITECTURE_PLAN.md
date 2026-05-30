# Architecture Refactoring Plan: WSL/Docker VHDX Shrinker

**Goal:** To evolve `wsl-docker-vhdx-shrinker` from a functional script to a robust, modular, and resilient enterprise automation tool. This effort targets technical debt in process reliability, dependency management, and overall code structure, ensuring stability across changing OS versions and complex system states.

---

## 🗺️ Discovery Phase: Mapping Implicit Assumptions & Failure Modes
The first step is comprehensive analysis before any change to prevent introducing new bugs (the "Read-Only" phase).

1.  **Process Dependency Graph:** Deeply map the execution sequence of `wsl --shutdown` and Hyper-V/Docker cmdlets. We must know all side effects, especially concerning resource locking mechanisms on VHDX files across consumer processes.
2.  **Concurrency & Throttling Analysis:** Profile the `Invoke-ParallelDirSweeps` function to identify potential bottlenecks (I/O contention, thread starvation) that manifest only under heavy load (many drives scanned simultaneously).
3.  **Failure Mode Mapping:** Catalog all ways the script can fail *silently*—situations where an error is not thrown but the intended operation did not complete (e.g., permission changes, partial disk corruption detected late in a scan).

## 🛠️ Phasing Plan: Incremental Rollout Strategy
To minimize risk and ensure continuous stability, refactoring will occur in three distinct, sequential phases.

### Phase I: Stability & Reliability (Priority: Highest)
*   **Focus:** Eliminating silent failures and enforcing reliable state management.
*   **Key Action:** **Implementing the Structured Result Object Pattern.** All major functions must transition from returning raw output streams to returning a standardized PowerShell object containing `Status: [Success/Failure]`, `ErrorCode: [Code]`, and `Details: [String[]]` arrays. This makes logic flow programmatically reliable.
*   **Deliverable:** A set of core functions that guarantee structured, predictable output regardless of runtime success or failure.

### Phase II: Performance & Scalability (Priority: Medium)
*   **Focus:** Optimizing resource utilization and scanning speed for large environments.
*   **Key Action 1 (Concurrency):** Replace manual `RunspacePool` management with PowerShell's native, robust Job Management features to handle parallelization safely.
*   **Key Action 2 (I/O Optimization):** Introduce dynamic throttling logic that gauges current system load (`Get-Counter`) and adjusts the number of concurrent threads dynamically, rather than using a fixed maximum.

### Phase III: Modernization & Usability (Priority: Lowest)
*   **Focus:** Improving developer experience (DX), maintainability, and adherence to modern best practices.
*   **Key Action 1 (Logging):** Implement a standardized, structured logging framework (JSON format). This allows for easy ingestion into professional log aggregation tools (Splunk/ELK Stack) and provides audit trails with unique execution IDs.
*   **Key Action 2 (Modularity):** Modularize the script by creating dedicated classes or modules for core responsibilities: `VirtualDiskManager` (handles all VHDX interaction), `ProcessCoordinator` (handles WSL/Docker lifecycle), etc. This achieves Dependency Injection principles.

## ✨ Key Technical Decisions & Design Patterns
These patterns will govern the refactoring process and prevent architectural drift.

1.  **Structured Result Object Pattern:** *Mandatory*. Every function that performs a major operation must return this object structure. (See Phase I).
2.  **Dependency Abstraction/DI:** Critical system interactions (e.g., talking to WSL) must be abstracted into interfaces/classes (`IVirtualDiskProvider`) so that if we switch from PowerShell scripting to Python or Go, only the implementation of that interface needs updating, leaving core business logic untouched.
3.  **Structured Logging:** Adopting JSON format for all logging ensures machine readability and facilitates automated auditing.

---
***Plan Approval Required:*** *This plan requires approval before proceeding with any code modifications.*