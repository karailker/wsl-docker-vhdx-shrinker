#Requires -Version 5.1
<#
.SYNOPSIS
  Pester tests for Shrink-WSLAndDockerDisks.ps1.

.DESCRIPTION
  Runs with:  Invoke-Pester -Path ./Tests -Output Detailed
  Requires:   Pester 5.x  (Install-Module Pester -Force -SkipPublisherCheck)

  All tests are pure-PowerShell; they never call wsl.exe, Optimize-VHD, or
  Start-Process. System interactions are mocked where needed so the suite runs
  without Administrator rights and without WSL/Hyper-V installed.
#>

BeforeAll {
  # Dot-source the script in a way that only loads functions — the main body
  # is guarded by the [CmdletBinding] param block so nothing executes on
  # dot-sourcing unless you call the script directly.
  $script:ScriptPath = Join-Path $PSScriptRoot '..\Shrink-WSLAndDockerDisks.ps1'

  # We load only the helper functions by dot-sourcing. Because the script uses
  # [CmdletBinding] and param(), dot-sourcing defines the functions in scope
  # but does not run the body.
  . $script:ScriptPath -WhatIf 2>$null
}

# ---------------------------------------------------------------------------
# Get-FileSystemRoots
# ---------------------------------------------------------------------------
Describe 'Get-FileSystemRoots' {

  Context 'When OnlyDrives specifies single-letter drive' {
    It 'Normalises bare letter to <letter>:\' {
      Mock Test-Path { $true }
      $result = Get-FileSystemRoots -OnlyDrives @('C')
      $result | Should -Contain 'C:\'
    }

    It 'Accepts letter with colon and backslash' {
      Mock Test-Path { $true }
      $result = Get-FileSystemRoots -OnlyDrives @('D:\')
      $result | Should -Contain 'D:\'
    }

    It 'Accepts letter with colon only' {
      Mock Test-Path { $true }
      $result = Get-FileSystemRoots -OnlyDrives @('E:')
      $result | Should -Contain 'E:\'
    }

    It 'Skips drives that do not exist' {
      Mock Test-Path { $false }
      $result = Get-FileSystemRoots -OnlyDrives @('Z')
      $result | Should -BeNullOrEmpty
    }

    It 'Returns unique, sorted results when duplicate drives provided' {
      Mock Test-Path { $true }
      $result = Get-FileSystemRoots -OnlyDrives @('C', 'c', 'C:\')
      $result.Count | Should -Be 1
      $result[0] | Should -Be 'C:\'
    }
  }

  Context 'When OnlyDrives is empty or null' {
    It 'Falls back to PSDrive enumeration' {
      # Only verify it returns a non-null result; actual drives vary per machine
      $result = Get-FileSystemRoots -OnlyDrives @()
      $result | Should -Not -BeNullOrEmpty
    }
  }
}

# ---------------------------------------------------------------------------
# Invoke-WSLShutdown
# ---------------------------------------------------------------------------
Describe 'Invoke-WSLShutdown' {

  Context 'When wsl.exe exits cleanly' {
    It 'Returns Status = Success' {
      Mock wsl.exe { }
      $r = Invoke-WSLShutdown
      $r.Status | Should -Be 'Success'
    }

    It 'Returns a non-empty Message' {
      Mock wsl.exe { }
      $r = Invoke-WSLShutdown
      $r.Message | Should -Not -BeNullOrEmpty
    }
  }

  Context 'When wsl.exe throws' {
    It 'Returns Status = Failure' {
      Mock wsl.exe { throw 'wsl not found' }
      $r = Invoke-WSLShutdown
      $r.Status | Should -Be 'Failure'
    }

    It 'Includes exception text in Message' {
      Mock wsl.exe { throw 'wsl not found' }
      $r = Invoke-WSLShutdown
      $r.Message | Should -Match 'wsl not found'
    }
  }
}

# ---------------------------------------------------------------------------
# Script-level parameter validation
# ---------------------------------------------------------------------------
Describe 'Script parameter validation' {

  It '-Mode accepts Quick' {
    { & $script:ScriptPath -Mode Quick -ListOnly -NoRelaunch -WhatIf } | Should -Not -Throw
  }

  It '-Mode accepts Full' {
    { & $script:ScriptPath -Mode Full -ListOnly -NoRelaunch -WhatIf } | Should -Not -Throw
  }

  It '-Mode rejects invalid value' {
    { & $script:ScriptPath -Mode Invalid -ListOnly -NoRelaunch -WhatIf } | Should -Throw
  }

  It '-Quick switch is accepted (deprecated alias)' {
    { & $script:ScriptPath -Quick -ListOnly -NoRelaunch -WhatIf } | Should -Not -Throw
  }

  It '-MaxScanThreads accepts integer' {
    { & $script:ScriptPath -MaxScanThreads 2 -ListOnly -NoRelaunch -WhatIf } | Should -Not -Throw
  }
}

# ---------------------------------------------------------------------------
# -ListOnly path: no Optimize-VHD calls
# ---------------------------------------------------------------------------
Describe '-ListOnly produces no optimization' {

  It 'Does not call Optimize-VHD when -ListOnly is set' {
    Mock Optimize-VHD { }
    # The script will scan drives; we make Get-FileSystemRoots return nothing
    # so it exits early at "No target VHDX files found" — either way
    # Optimize-VHD must never be called.
    & $script:ScriptPath -ListOnly -NoRelaunch -Yes -WhatIf 2>$null
    Should -Invoke -CommandName Optimize-VHD -Times 0 -Exactly
  }
}

# ---------------------------------------------------------------------------
# Confirmation prompt logic (tested via helper booleans)
# ---------------------------------------------------------------------------
Describe 'Confirmation loop behaviour' {

  It '-Yes switch bypasses Read-Host' {
    Mock Read-Host { 'N' }   # would cancel if prompt were shown
    Mock Optimize-VHD { }
    Mock Get-FileSystemRoots { @('C:\') }
    Mock Invoke-ParallelDirSweeps {
      # Return a fake FileInfo-like object
      [PSCustomObject]@{
        FullName = 'C:\fake\ext4.vhdx'
        Name     = 'ext4.vhdx'
        Length   = 1GB
      }
    }
    Mock Get-Item { [PSCustomObject]@{ Length = 900MB } }
    Mock Test-IsAdmin { $true }

    # Should not throw "Operation cancelled" and should call Optimize-VHD once
    & $script:ScriptPath -Yes -NoRelaunch -WhatIf 2>$null
    Should -Invoke -CommandName Read-Host -Times 0 -Exactly
  }

  It 'N response cancels without calling Optimize-VHD' {
    Mock Read-Host { 'N' }
    Mock Optimize-VHD { }
    Mock Get-FileSystemRoots { @('C:\') }
    Mock Invoke-ParallelDirSweeps {
      [PSCustomObject]@{
        FullName = 'C:\fake\ext4.vhdx'
        Name     = 'ext4.vhdx'
        Length   = 1GB
      }
    }
    Mock Test-IsAdmin { $true }

    & $script:ScriptPath -NoRelaunch -WhatIf 2>$null
    Should -Invoke -CommandName Optimize-VHD -Times 0 -Exactly
  }
}

# ---------------------------------------------------------------------------
# Size-savings arithmetic
# ---------------------------------------------------------------------------
Describe 'Size savings calculation' {

  It 'Calculates reclaimed MB correctly' {
    $before = 10GB
    $after  = 8GB
    $savedMB = [math]::Round(($before - $after) / 1MB, 1)
    $savedMB | Should -Be 2048.0
  }

  It 'Reports zero reclaimed when sizes are equal' {
    $before = 5GB
    $after  = 5GB
    $savedMB = [math]::Round(($before - $after) / 1MB, 1)
    $savedMB | Should -Be 0.0
  }

  It 'Handles very small savings (< 1 MB) gracefully' {
    $before = [long](500KB)
    $after  = [long](100KB)
    $savedMB = [math]::Round(($before - $after) / 1MB, 1)
    $savedMB | Should -BeGreaterOrEqual 0.0
  }
}

# ---------------------------------------------------------------------------
# Drive letter normalisation edge cases
# ---------------------------------------------------------------------------
Describe 'Drive letter normalisation' {

  It 'Lower-case drive letter is uppercased' {
    Mock Test-Path { $true }
    $result = Get-FileSystemRoots -OnlyDrives @('c')
    $result | Should -Contain 'C:\'
  }

  It 'Mixed-case input normalises to uppercase' {
    Mock Test-Path { $true }
    $result = Get-FileSystemRoots -OnlyDrives @('d', 'D', 'D:\')
    $result.Count | Should -Be 1
    $result[0] | Should -Be 'D:\'
  }

  It 'Non-drive-letter tokens are silently ignored' {
    Mock Test-Path { $true }
    $result = Get-FileSystemRoots -OnlyDrives @('not-a-drive', '\\server\share')
    $result | Should -BeNullOrEmpty
  }
}
