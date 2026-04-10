# dsc/DscConfiguration.ps1
#
# Example DSC configuration using the DTDS_FileContent resource.
#
# This configuration demonstrates how desired state is expressed declaratively
# as code and compiled into a Managed Object Format (MOF) document that the
# Local Configuration Manager (LCM) can apply.
#
# Related ADR:          docs/adrs/0004-use-dsc-for-windows-config.md
# Related requirements: S-008
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

    Node 'localhost' {

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

        # Remove any legacy lock file that should no longer exist.
        DTDS_FileContent LegacyLock {
            Path    = "$TargetDir/.legacy-lock"
            Content = ''   # Content is ignored when Ensure = Absent
            Ensure  = 'Absent'
        }
    }
}

# Compile the configuration into a MOF document.
$null = New-Item -ItemType Directory -Path $OutputDir -Force
WorkspaceSetup -TargetDir $OutputDir -OutputPath $OutputDir
Write-Host "MOF compiled to: $OutputDir/localhost.mof" -ForegroundColor Green
