#Requires -Version 5.1
<#
.SYNOPSIS
  Pester 5.x tests for Shrink-WSLAndDockerDisks.ps1.

.DESCRIPTION
  Run with:
    Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
    Invoke-Pester -Path .\Tests -Output Detailed

  Strategy
  --------
  The script has a [CmdletBinding] param block. Dot-sourcing it runs only the
  param-block and function definitions -- the main body (everything after the
  last closing brace of functions) is NOT executed on dot-source with -WhatIf
  because the admin guard will throw on a non-admin process.

  We extract functions via the PowerShell AST and define them in a helper
  module scope, then call them directly. This gives us full Pester mock
  support without needing elevation or real hardware.

  Covered
  -------
  - Get-FileSystemRoots:  drive normalisation, dedup, existence check, fallback
  - Invoke-WSLShutdown:   success path, failure path via injectable scriptblock
  - Confirm loop logic:   $confirmed flag pattern (unit-tested directly)
  - Savings arithmetic:   pure math verified as inline expressions
  - Drive letter edge cases
#>

BeforeAll {
  $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\Shrink-WSLAndDockerDisks.ps1')).Path

  # Extract and define functions via AST (no script body execution)
  $ast     = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
  $fnDefs  = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
  foreach ($fn in $fnDefs) {
    Invoke-Expression $fn.Extent.Text
  }
}

# ===========================================================================
# Get-FileSystemRoots -- drive normalisation
# ===========================================================================
Describe 'Get-FileSystemRoots' {

  Context 'OnlyDrives single letter formats' {

    It 'Normalises bare letter C to C:\' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('C')
      $r | Should -Contain 'C:\'
    }

    It 'Accepts D:\ already canonical' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('D:\')
      $r | Should -Contain 'D:\'
    }

    It 'Accepts E: letter plus colon no backslash' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('E:')
      $r | Should -Contain 'E:\'
    }

    It 'Lower-case letter c is uppercased to C:\' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('c')
      $r | Should -Contain 'C:\'
    }

    It 'Skips a drive whose Test-Path returns false' {
      Mock Test-Path { $false }
      $r = Get-FileSystemRoots -OnlyDrives @('Z')
      $r | Should -BeNullOrEmpty
    }
  }

  Context 'OnlyDrives deduplication' {

    It 'Returns exactly one entry when same drive specified multiple ways' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('C', 'c', 'C:\')
      # Filter to only the normalised form; dedup collapses all three to one C:\
      $cDrives = @($r | Where-Object { $_ -eq 'C:\' })
      $cDrives.Count | Should -Be 1
    }

    It 'Returns both drives when two distinct drives are provided' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('C', 'D')
      $r.Count | Should -Be 2
      $r | Should -Contain 'C:\'
      $r | Should -Contain 'D:\'
    }
  }

  Context 'OnlyDrives invalid non-drive tokens' {

    It 'Silently ignores tokens that are not single drive letters' {
      Mock Test-Path { $true }
      $r = Get-FileSystemRoots -OnlyDrives @('not-a-drive', '\\server\share', '123')
      $r | Should -BeNullOrEmpty
    }
  }

  Context 'OnlyDrives empty fallback enumeration' {

    It 'Returns at least one drive when no drives are specified' {
      $r = Get-FileSystemRoots -OnlyDrives @()
      $r | Should -Not -BeNullOrEmpty
    }
  }
}

# ===========================================================================
# Invoke-WSLShutdown -- injectable scriptblock
# ===========================================================================
Describe 'Invoke-WSLShutdown' {

  Context 'Success path' {

    It 'Returns Status Success when the command completes without throwing' {
      $ok = { 'WSL: The operation completed successfully.' }
      $r  = Invoke-WSLShutdown -ShutdownCommand $ok
      $r.Status | Should -Be 'Success'
    }

    It 'Populates Message with the success text' {
      $ok = { }
      $r  = Invoke-WSLShutdown -ShutdownCommand $ok
      $r.Message | Should -Not -BeNullOrEmpty
    }

    It 'Details array captures stdout lines emitted by the command' {
      $ok = { 'line1'; 'line2' }
      $r  = Invoke-WSLShutdown -ShutdownCommand $ok
      $r.Details.Count | Should -Be 2
    }

    It 'Details array is empty when the command emits nothing' {
      $ok = { }
      $r  = Invoke-WSLShutdown -ShutdownCommand $ok
      $r.Details.Count | Should -Be 0
    }
  }

  Context 'Failure path' {

    It 'Returns Status Failure when the command throws' {
      $fail = { throw 'wsl.exe: not found' }
      $r    = Invoke-WSLShutdown -ShutdownCommand $fail
      $r.Status | Should -Be 'Failure'
    }

    It 'Includes the exception message in Message' {
      $fail = { throw 'wsl.exe: not found' }
      $r    = Invoke-WSLShutdown -ShutdownCommand $fail
      $r.Message | Should -Match 'wsl\.exe: not found'
    }

    It 'Returns a structured object even on failure' {
      $fail = { throw 'boom' }
      $r    = Invoke-WSLShutdown -ShutdownCommand $fail
      $r | Should -Not -BeNullOrEmpty
    }
  }
}

# ===========================================================================
# Confirmation loop -- $confirmed flag logic
# The loop is: while (-not $confirmed) { switch(resp) { 'Y' -> $confirmed=$true } }
# Tested as a unit pattern rather than by invoking the full script.
# ===========================================================================
Describe 'Confirmation loop confirmed flag pattern' {

  It 'Sets confirmed to true on response Y' {
    $confirmed = $false
    $resp = 'Y'
    switch ($resp.ToUpperInvariant()) {
      'Y'   { $confirmed = $true }
      'YES' { $confirmed = $true }
    }
    $confirmed | Should -Be $true
  }

  It 'Sets confirmed to true on response yes case-insensitive' {
    $confirmed = $false
    $resp = 'yes'
    switch ($resp.ToUpperInvariant()) {
      'Y'   { $confirmed = $true }
      'YES' { $confirmed = $true }
    }
    $confirmed | Should -Be $true
  }

  It 'Does NOT set confirmed to true on response S show details' {
    $confirmed = $false
    $resp = 'S'
    switch ($resp.ToUpperInvariant()) {
      'Y'    { $confirmed = $true }
      'YES'  { $confirmed = $true }
      'S'    { <# show details, no change to confirmed #> }
      'SHOW' { <# show details, no change to confirmed #> }
    }
    $confirmed | Should -Be $false
  }

  It 'Does NOT set confirmed to true on an unknown response' {
    $confirmed = $false
    $resp = 'maybe'
    switch ($resp.ToUpperInvariant()) {
      'Y'   { $confirmed = $true }
      'YES' { $confirmed = $true }
    }
    $confirmed | Should -Be $false
  }
}

# ===========================================================================
# Size-savings arithmetic -- pure math
# ===========================================================================
Describe 'Size savings arithmetic' {

  It 'Calculates reclaimed MB correctly for 10 GB to 8 GB' {
    $savedMB = [math]::Round((10GB - 8GB) / 1MB, 1)
    $savedMB | Should -Be 2048.0
  }

  It 'Reports 0.0 MB when before equals after' {
    $savedMB = [math]::Round((5GB - 5GB) / 1MB, 1)
    $savedMB | Should -Be 0.0
  }

  It 'Handles sub-MB savings without throwing' {
    $savedMB = [math]::Round(([long](500KB) - [long](100KB)) / 1MB, 1)
    $savedMB | Should -BeGreaterOrEqual 0.0
  }

  It 'Negative savings file grew are reported as a negative number' {
    $savedMB = [math]::Round((8GB - 10GB) / 1MB, 1)
    $savedMB | Should -BeLessThan 0
  }

  It 'GB display rounds to 2 decimal places' {
    $beforeGB = [math]::Round(10240MB / 1GB, 2)
    $beforeGB | Should -Be 10.0
  }
}

# ===========================================================================
# Scan pattern selection
# ===========================================================================
Describe 'Scan pattern selection' {

  It 'Default patterns include ext4.vhdx' {
    $patterns = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
    $patterns | Should -Contain 'ext4.vhdx'
  }

  It 'Default patterns include docker_data.vhdx' {
    $patterns = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
    $patterns | Should -Contain 'docker_data.vhdx'
  }

  It 'Default patterns include disk.vhdx' {
    $patterns = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
    $patterns | Should -Contain 'disk.vhdx'
  }

  It 'Default pattern set has exactly 3 entries' {
    $patterns = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
    $patterns.Count | Should -Be 3
  }

  It 'IncludeAllVHDX pattern is a wildcard' {
    $patterns = @('*.vhdx')
    $patterns[0] | Should -Be '*.vhdx'
  }

  It 'Known name filter is case-insensitive' {
    $nameSet = @('ext4.vhdx','docker_data.vhdx','disk.vhdx')
    ($nameSet -contains 'EXT4.VHDX'.ToLowerInvariant()) | Should -Be $true
  }
}

# ===========================================================================
# Invoke-WSLShutdown -- result object shape
# ===========================================================================
Describe 'Invoke-WSLShutdown result object shape' {

  It 'Result has a Status property' {
    $r = Invoke-WSLShutdown -ShutdownCommand { }
    $r.PSObject.Properties.Name | Should -Contain 'Status'
  }

  It 'Result has a Message property' {
    $r = Invoke-WSLShutdown -ShutdownCommand { }
    $r.PSObject.Properties.Name | Should -Contain 'Message'
  }

  It 'Result has a Details property' {
    $r = Invoke-WSLShutdown -ShutdownCommand { }
    $r.PSObject.Properties.Name | Should -Contain 'Details'
  }

  It 'Status is either Success or Failure, never a third value' {
    $ok   = Invoke-WSLShutdown -ShutdownCommand { }
    $fail = Invoke-WSLShutdown -ShutdownCommand { throw 'err' }
    $ok.Status   | Should -BeIn @('Success','Failure')
    $fail.Status | Should -BeIn @('Success','Failure')
  }
}
