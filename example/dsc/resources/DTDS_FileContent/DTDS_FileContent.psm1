# resources/DTDS_FileContent/DTDS_FileContent.psm1
#
# Class-based DSC resource: DTDS_FileContent
#
# Ensures that a text file exists at a given path with the required content,
# or is absent.  Works cross-platform with PowerShell Core 7+.
#
# Documentation for this resource is generated automatically during the CI/CD
# pipeline by DscResource.DocGenerator + PlatyPS:
#
#   pwsh -File dsc/build.ps1
#
# Related ADR:          docs/adrs/0004-use-dsc-for-windows-config.md
# Related requirements: S-008, S-009

<#
.SYNOPSIS
    Whether the file should be Present (default) or Absent.

.DESCRIPTION
    The Ensure enum is used by the DTDS_FileContent DSC resource to express
    whether the managed file should exist (Present) or be removed (Absent).
#>
enum Ensure {
    Present
    Absent
}

<#
.SYNOPSIS
    Manages the text content of a file in a deterministic way.

.DESCRIPTION
    The DTDS_FileContent resource ensures that a UTF-8 text file at the given
    Path either:
      * Exists with exactly the specified Content (Ensure = Present), or
      * Does not exist (Ensure = Absent).

    It is a class-based DSC resource designed to demonstrate the deterministic
    documentation pattern described in the technical design specification.
    Documentation is auto-generated from these comment blocks by
    DscResource.DocGenerator during the CI/CD pipeline.

.NOTES
    Tags:   File, Content, CrossPlatform, Documentation
    Author: platform-team
#>
[DscResource()]
class DTDS_FileContent {

    <#
    .PARAMETER Path
        The full path to the file to manage.
        Acts as the unique DSC key property — two DTDS_FileContent declarations
        in the same configuration must target different paths.

    .EXAMPLE
        Path = '/var/config/app.conf'

    .EXAMPLE
        Path = 'C:\ProgramData\MyApp\config.txt'
    #>
    [DscProperty(Key)]
    [string] $Path

    <#
    .PARAMETER Content
        The exact text content the file must contain.
        When Ensure = Present the resource writes this string verbatim (no
        trailing newline is added).  When Ensure = Absent this property is
        ignored.

    .EXAMPLE
        Content = '# managed by DSC — do not edit manually'
    #>
    [DscProperty(Mandatory)]
    [string] $Content

    <#
    .PARAMETER Ensure
        Whether the file should be Present (default) or Absent.

        * Present — the file must exist with the required Content.
        * Absent  — the file must not exist; it is removed if found.

    .EXAMPLE
        Ensure = 'Present'
    #>
    [DscProperty()]
    [Ensure] $Ensure = [Ensure]::Present

    # -----------------------------------------------------------------------
    # Get() — reads the current state of the file from disk.
    # -----------------------------------------------------------------------
    [DTDS_FileContent] Get() {
        $current         = [DTDS_FileContent]::new()
        $current.Path    = $this.Path
        $current.Content = $this.Content
        $current.Ensure  = [Ensure]::Absent

        if (Test-Path -LiteralPath $this.Path -PathType Leaf) {
            $current.Ensure  = [Ensure]::Present
            $current.Content = Get-Content -LiteralPath $this.Path -Raw -Encoding UTF8
        }

        return $current
    }

    # -----------------------------------------------------------------------
    # Test() — returns $true when the resource is already in the desired state.
    # -----------------------------------------------------------------------
    [bool] Test() {
        $state = $this.Get()

        if ($this.Ensure -eq [Ensure]::Absent) {
            return $state.Ensure -eq [Ensure]::Absent
        }

        return ($state.Ensure -eq [Ensure]::Present) -and
               ($state.Content -eq $this.Content)
    }

    # -----------------------------------------------------------------------
    # Set() — applies the desired state to the file system.
    # -----------------------------------------------------------------------
    [void] Set() {
        if ($this.Ensure -eq [Ensure]::Present) {
            # Create parent directories if they do not exist
            $parentDir = [System.IO.Path]::GetDirectoryName($this.Path)
            if ($parentDir -and (-not (Test-Path -LiteralPath $parentDir))) {
                $null = New-Item -ItemType Directory -Path $parentDir -Force
            }
            Set-Content -LiteralPath $this.Path -Value $this.Content -Encoding UTF8 -NoNewline
        }
        else {
            if (Test-Path -LiteralPath $this.Path) {
                Remove-Item -LiteralPath $this.Path -Force
            }
        }
    }
}
