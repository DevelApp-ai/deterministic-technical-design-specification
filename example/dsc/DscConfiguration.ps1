# dsc/DscConfiguration.ps1
#
# Example DSC configuration using all three DTDS DSC resources:
#   - DTDS_FileContent    — manages text file content
#   - DTDS_RegistryEntry  — manages Windows registry values
#   - DTDS_ServiceConfig  — manages Windows service state and startup type
#
# This configuration demonstrates how desired state is expressed declaratively
# as code and compiled into a Managed Object Format (MOF) document that the
# Local Configuration Manager (LCM) can apply.
#
# Related ADR:          docs/adrs/0004-use-dsc-for-windows-config.md
# Related requirements: S-008, S-009, S-010
#
# Usage — compile only (no LCM required):
#   pwsh -File DscConfiguration.ps1
#
# Usage — compile and apply (requires LCM on Windows):
#   pwsh -File DscConfiguration.ps1
#   Start-DscConfiguration -Path ./WorkspaceSetup -Wait -Verbose
#
# Usage — test current state (requires LCM on Windows):
#   Test-DscConfiguration -Path ./WorkspaceSetup

using module './resources/DTDS_FileContent/DTDS_FileContent.psm1'
using module './resources/DTDS_RegistryEntry/DTDS_RegistryEntry.psm1'
using module './resources/DTDS_ServiceConfig/DTDS_ServiceConfig.psm1'

[CmdletBinding()]
param(
    # Target directory in which the managed files will be created.
    [string] $OutputDir = (Join-Path $PSScriptRoot '../docs/generated/dsc-output')
)

Configuration WorkspaceSetup {
    param(
        [string] $TargetDir
    )

    Import-DscResource -ModuleName DTDS_FileContent
    Import-DscResource -ModuleName DTDS_RegistryEntry
    Import-DscResource -ModuleName DTDS_ServiceConfig

    Node 'localhost' {

        # ------------------------------------------------------------------
        # DTDS_FileContent — managed file resources
        # ------------------------------------------------------------------

        # Ensure a platform README exists in the target directory.
        DTDS_FileContent PlatformReadme {
            Path    = "$TargetDir/README.md"
            Content = "# Platform Workspace`nManaged by DSC — do not edit manually."
            Ensure  = 'Present'
        }

        # Ensure a configuration marker file is present.
        DTDS_FileContent ConfigMarker {
            Path    = "$TargetDir/.dsc-configured"
            Content = "configured=true"
            Ensure  = 'Present'
        }

        # Ensure the application config skeleton exists.
        DTDS_FileContent AppConfigSkeleton {
            Path    = "$TargetDir/config/app.conf"
            Content = @"
# Application configuration — managed by DSC.
# All values are documented in docs/dsc/index.md
[general]
log_level = INFO
max_connections = 100

[security]
tls_min_version = 1.2
require_https = true
"@
            Ensure  = 'Present'
        }

        # Remove any legacy lock file that should no longer exist.
        DTDS_FileContent LegacyLock {
            Path    = "$TargetDir/.legacy-lock"
            Content = ''   # Content is ignored when Ensure = Absent
            Ensure  = 'Absent'
        }

        # ------------------------------------------------------------------
        # DTDS_RegistryEntry — Windows Registry resources
        # (no-op on Linux/macOS; applied by LCM on Windows)
        # ------------------------------------------------------------------

        # Enable TLS 1.2 in .NET Framework (required for modern HTTPS)
        DTDS_RegistryEntry EnableDotNetTls12Client {
            Key        = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
            ValueName  = 'SchUseStrongCrypto'
            ValueData  = '1'
            ValueType  = 'DWord'
            Ensure     = 'Present'
        }

        DTDS_RegistryEntry EnableDotNetTls12Server {
            Key        = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
            ValueName  = 'SchUseStrongCrypto'
            ValueData  = '1'
            ValueType  = 'DWord'
            Ensure     = 'Present'
        }

        # Disable deprecated TLS 1.0 client
        DTDS_RegistryEntry DisableTls10Client {
            Key        = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'
            ValueName  = 'Enabled'
            ValueData  = '0'
            ValueType  = 'DWord'
            Ensure     = 'Present'
        }

        # Disable deprecated TLS 1.1 client
        DTDS_RegistryEntry DisableTls11Client {
            Key        = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'
            ValueName  = 'Enabled'
            ValueData  = '0'
            ValueType  = 'DWord'
            Ensure     = 'Present'
        }

        # Set application log level via registry
        DTDS_RegistryEntry AppLogLevel {
            Key        = 'HKLM:\SOFTWARE\Platform\MyApp'
            ValueName  = 'LogLevel'
            ValueData  = 'INFO'
            ValueType  = 'String'
            Ensure     = 'Present'
        }

        # ------------------------------------------------------------------
        # DTDS_ServiceConfig — Windows Service resources
        # (no-op on Linux/macOS; applied by LCM on Windows)
        # ------------------------------------------------------------------

        # Ensure Windows Update service is manual (not automatic) on servers
        DTDS_ServiceConfig WindowsUpdate {
            ServiceName = 'wuauserv'
            State       = 'Stopped'
            StartupType = 'Manual'
        }

        # Ensure Windows Firewall is running and set to automatic
        DTDS_ServiceConfig WindowsFirewall {
            ServiceName = 'MpsSvc'
            State       = 'Running'
            StartupType = 'Automatic'
        }

        # Ensure Remote Registry is disabled (security hardening)
        DTDS_ServiceConfig RemoteRegistry {
            ServiceName = 'RemoteRegistry'
            State       = 'Stopped'
            StartupType = 'Disabled'
        }
    }
}

# Compile the configuration into a MOF document.
$null = New-Item -ItemType Directory -Path $OutputDir -Force
WorkspaceSetup -TargetDir $OutputDir -OutputPath $OutputDir
Write-Host "MOF compiled to: $OutputDir/localhost.mof" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host "Configuration includes:" -ForegroundColor Cyan
Write-Host "  4 x DTDS_FileContent  (file content management)" -ForegroundColor Cyan
Write-Host "  5 x DTDS_RegistryEntry (registry hardening: TLS, app settings)" -ForegroundColor Cyan
Write-Host "  3 x DTDS_ServiceConfig (service state: WU=Manual, FW=Auto, RR=Disabled)" -ForegroundColor Cyan

