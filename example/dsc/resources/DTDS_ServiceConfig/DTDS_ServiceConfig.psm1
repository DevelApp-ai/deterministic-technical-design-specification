# resources/DTDS_ServiceConfig/DTDS_ServiceConfig.psm1
#
# Class-based DSC resource: DTDS_ServiceConfig
#
# Ensures that a Windows service is in the desired state — running or stopped —
# with a specific startup type (Automatic, Manual, Disabled).
# Works on Windows PowerShell and PowerShell Core 7+ on Windows.
# On non-Windows platforms all operations are treated as compliant (no-op).
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
    Whether the service should be Running (default) or Stopped.

.DESCRIPTION
    The ServiceState enum expresses the desired run-time state of the managed
    Windows service.
#>
enum ServiceState {
    Running
    Stopped
}

<#
.SYNOPSIS
    The startup type of the managed service.

.DESCRIPTION
    Controls how the service is started at boot time.
    Mirrors the values accepted by Set-Service -StartupType.
#>
enum ServiceStartupType {
    Automatic
    Manual
    Disabled
}

<#
.SYNOPSIS
    Manages the state and startup type of a Windows service in a deterministic way.

.DESCRIPTION
    The DTDS_ServiceConfig resource ensures that the named Windows service is:
      * In the specified State (Running or Stopped), and
      * Configured with the specified StartupType (Automatic, Manual, or Disabled).

    On non-Windows platforms the resource returns compliant for all operations
    so that CI pipelines including Windows-only DSC configs can run on Linux.

.NOTES
    Tags:   Service, Windows, Configuration, Documentation
    Author: platform-team
#>
[DscResource()]
class DTDS_ServiceConfig {

    <#
    .PARAMETER ServiceName
        The short service name (not the display name) of the Windows service.

    .EXAMPLE
        ServiceName = 'wuauserv'

    .EXAMPLE
        ServiceName = 'Spooler'
    #>
    [DscProperty(Key)]
    [string] $ServiceName

    <#
    .PARAMETER State
        The desired run-time state of the service.
        Defaults to Running.

    .EXAMPLE
        State = 'Stopped'
    #>
    [DscProperty()]
    [ServiceState] $State = [ServiceState]::Running

    <#
    .PARAMETER StartupType
        The startup type of the service.
        Defaults to Automatic.

    .EXAMPLE
        StartupType = 'Disabled'
    #>
    [DscProperty()]
    [ServiceStartupType] $StartupType = [ServiceStartupType]::Automatic

    # -----------------------------------------------------------------------
    # Get() — reads the current state of the service.
    # -----------------------------------------------------------------------
    [DTDS_ServiceConfig] Get() {
        $current             = [DTDS_ServiceConfig]::new()
        $current.ServiceName = $this.ServiceName
        $current.State       = $this.State
        $current.StartupType = $this.StartupType

        if (-not $this._IsWindows()) { return $current }

        try {
            $svc = Get-Service -Name $this.ServiceName -ErrorAction Stop
            $current.State       = $svc.Status -eq 'Running' ? [ServiceState]::Running : [ServiceState]::Stopped
            $current.StartupType = [ServiceStartupType]$svc.StartType.ToString()
        }
        catch { }   # Service not found — return defaults

        return $current
    }

    # -----------------------------------------------------------------------
    # Test() — returns $true when the resource is already in the desired state.
    # -----------------------------------------------------------------------
    [bool] Test() {
        if (-not $this._IsWindows()) { return $true }

        $state = $this.Get()
        return ($state.State -eq $this.State) -and
               ($state.StartupType -eq $this.StartupType)
    }

    # -----------------------------------------------------------------------
    # Set() — applies the desired state to the service.
    # -----------------------------------------------------------------------
    [void] Set() {
        if (-not $this._IsWindows()) { return }

        $svc = Get-Service -Name $this.ServiceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            throw "Service '$($this.ServiceName)' does not exist on this system."
        }

        # Apply startup type first (affects whether Start-Service is possible)
        Set-Service -Name $this.ServiceName -StartupType $this.StartupType.ToString()

        if ($this.State -eq [ServiceState]::Running -and $svc.Status -ne 'Running') {
            Start-Service -Name $this.ServiceName
        }
        elseif ($this.State -eq [ServiceState]::Stopped -and $svc.Status -ne 'Stopped') {
            Stop-Service -Name $this.ServiceName -Force
        }
    }

    # -----------------------------------------------------------------------
    # Helper — returns $true when running on Windows
    # -----------------------------------------------------------------------
    hidden [bool] _IsWindows() {
        return $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')
    }
}
