# resources/DTDS_RegistryEntry/DTDS_RegistryEntry.psm1
#
# Class-based DSC resource: DTDS_RegistryEntry
#
# Ensures that a Windows Registry value exists with the correct data and type,
# or is absent.  Works with PowerShell Core 7+ on Windows; the resource
# gracefully skips on non-Windows platforms (for CI compatibility).
#
# Documentation is generated automatically during the CI/CD pipeline by
# DscResource.DocGenerator + PlatyPS:
#
#   pwsh -File dsc/build.ps1
#
# Related ADR:          docs/adrs/0004-use-dsc-for-windows-config.md
# Related requirements: S-008, S-009, S-010

<#
.SYNOPSIS
    Whether the registry value should be Present (default) or Absent.

.DESCRIPTION
    The Ensure enum is used by the DTDS_RegistryEntry DSC resource to express
    whether the managed registry value should exist (Present) or be removed
    (Absent).
#>
enum Ensure {
    Present
    Absent
}

<#
.SYNOPSIS
    Registry value type (maps to .NET RegistryValueKind).

.DESCRIPTION
    Specifies the data type of the registry value.  Supported types mirror
    the Windows Registry value kinds exposed by Microsoft.Win32.RegistryValueKind.
#>
enum RegistryValueType {
    String        # REG_SZ
    ExpandString  # REG_EXPAND_SZ
    MultiString   # REG_MULTI_SZ
    Binary        # REG_BINARY (value stored as hex string)
    DWord         # REG_DWORD
    QWord         # REG_QWORD
}

<#
.SYNOPSIS
    Manages a single Windows Registry value in a deterministic, idempotent way.

.DESCRIPTION
    The DTDS_RegistryEntry resource ensures that a registry value under the
    given Key either:
      * Exists with the specified ValueName, ValueData, and ValueType (Ensure = Present), or
      * Does not exist (Ensure = Absent).

    On non-Windows platforms (Linux, macOS) the resource treats every operation as
    compliant (Test() returns $true) to allow cross-platform CI pipelines to
    include Windows-specific DSC configurations without failures.

.NOTES
    Tags:   Registry, Windows, Configuration, Documentation
    Author: platform-team
#>
[DscResource()]
class DTDS_RegistryEntry {

    <#
    .PARAMETER Key
        The full registry key path (hive included).

    .EXAMPLE
        Key = 'HKLM:\SOFTWARE\MyApp'

    .EXAMPLE
        Key = 'HKCU:\Software\Policies\MyOrg'
    #>
    [DscProperty(Key)]
    [string] $Key

    <#
    .PARAMETER ValueName
        The name of the registry value within the key.
        Acts as the second key property — two DTDS_RegistryEntry declarations
        with the same Key must target different ValueNames.

    .EXAMPLE
        ValueName = 'LogLevel'
    #>
    [DscProperty(Key)]
    [string] $ValueName

    <#
    .PARAMETER ValueData
        The desired data for the registry value.
        For Binary type, supply a hex string (e.g. 'DEADBEEF').
        For MultiString type, supply newline-separated values.

    .EXAMPLE
        ValueData = 'INFO'

    .EXAMPLE
        ValueData = '1'
    #>
    [DscProperty(Mandatory)]
    [string] $ValueData

    <#
    .PARAMETER ValueType
        The data type of the registry value.  Defaults to String (REG_SZ).

    .EXAMPLE
        ValueType = 'DWord'
    #>
    [DscProperty()]
    [RegistryValueType] $ValueType = [RegistryValueType]::String

    <#
    .PARAMETER Ensure
        Whether the registry value should be Present (default) or Absent.

    .EXAMPLE
        Ensure = 'Present'
    #>
    [DscProperty()]
    [Ensure] $Ensure = [Ensure]::Present

    # -----------------------------------------------------------------------
    # Get() — reads the current state of the registry value.
    # -----------------------------------------------------------------------
    [DTDS_RegistryEntry] Get() {
        $current            = [DTDS_RegistryEntry]::new()
        $current.Key        = $this.Key
        $current.ValueName  = $this.ValueName
        $current.ValueData  = $this.ValueData
        $current.ValueType  = $this.ValueType
        $current.Ensure     = [Ensure]::Absent

        if (-not $this._IsWindows()) { return $current }

        try {
            $rawValue = Get-ItemPropertyValue -Path $this.Key -Name $this.ValueName -ErrorAction Stop
            $current.Ensure    = [Ensure]::Present
            $current.ValueData = [string]$rawValue
        }
        catch { }   # Key or value does not exist — Ensure remains Absent

        return $current
    }

    # -----------------------------------------------------------------------
    # Test() — returns $true when the resource is already in the desired state.
    # -----------------------------------------------------------------------
    [bool] Test() {
        # On non-Windows platforms skip enforcement (for CI compatibility)
        if (-not $this._IsWindows()) { return $true }

        $state = $this.Get()
        if ($this.Ensure -eq [Ensure]::Absent) {
            return $state.Ensure -eq [Ensure]::Absent
        }
        return ($state.Ensure -eq [Ensure]::Present) -and
               ($state.ValueData -eq $this.ValueData)
    }

    # -----------------------------------------------------------------------
    # Set() — applies the desired state.
    # -----------------------------------------------------------------------
    [void] Set() {
        if (-not $this._IsWindows()) { return }

        if ($this.Ensure -eq [Ensure]::Present) {
            # Create the key path if it does not exist
            if (-not (Test-Path -LiteralPath $this.Key)) {
                $null = New-Item -Path $this.Key -Force
            }
            $kind = [Microsoft.Win32.RegistryValueKind]$this.ValueType.ToString()
            Set-ItemProperty -Path $this.Key -Name $this.ValueName `
                             -Value $this.ValueData -Type $kind
        }
        else {
            if (Test-Path -LiteralPath $this.Key) {
                Remove-ItemProperty -Path $this.Key -Name $this.ValueName -ErrorAction SilentlyContinue
            }
        }
    }

    # -----------------------------------------------------------------------
    # Helper — returns $true when running on Windows
    # -----------------------------------------------------------------------
    hidden [bool] _IsWindows() {
        return $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')
    }
}
