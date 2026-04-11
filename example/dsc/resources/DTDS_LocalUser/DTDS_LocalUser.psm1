#Requires -Version 7.2

<#
.SYNOPSIS
    DSC resource that manages local Windows user accounts.

.DESCRIPTION
    DTDS_LocalUser is a class-based DSC resource that creates, modifies, or
    removes local Windows user accounts.  It satisfies CIS Windows Benchmark
    Section 2.3.1 (Account Management) and DORA Art.9 §9.2 (access control),
    ensuring default built-in accounts are disabled or renamed and that only
    approved service accounts exist.

    On Linux and macOS the resource runs in "no-op" mode so that cross-platform
    Pester tests can exercise the Get/Test/Set logic without Windows-specific APIs.

.NOTES
    Author:      platform-team
    Version:     1.0.0
    ADR:         docs/adrs/0004-use-dsc-for-windows-config.md
    Requirements: S-008, S-009, DORA-003
    Frameworks:  CIS 2.3.1, DORA Art.9, NIS2 Art.21(2)(i)
#>

enum EnsureValue {
    Present
    Absent
}

enum AccountStatus {
    Enabled
    Disabled
}

[DscResource()]
class DTDS_LocalUser {

    # ── Key property ────────────────────────────────────────────────────────
    <#
    .DESCRIPTION
        The username of the local account to manage.  This is the DSC key
        property — it uniquely identifies the resource instance.
    #>
    [DscProperty(Key)]
    [string] $UserName

    # ── Desired state ────────────────────────────────────────────────────────
    <#
    .DESCRIPTION
        Whether the user account should exist.
        Present  — creates the account if it does not exist.
        Absent   — removes the account if it exists.
        Default: Present.
    #>
    [DscProperty()]
    [EnsureValue] $Ensure = [EnsureValue]::Present

    <#
    .DESCRIPTION
        Human-readable description stored on the account object.
        Useful for audit trails (DORA Art.10) and CIS 2.3.1.3 (account naming).
    #>
    [DscProperty()]
    [string] $Description = ""

    <#
    .DESCRIPTION
        Whether the account should be enabled or disabled.
        CIS 2.3.1 requires default built-in accounts (e.g., Administrator,
        Guest) to be Disabled.
        Default: Enabled.
    #>
    [DscProperty()]
    [AccountStatus] $AccountStatus = [AccountStatus]::Enabled

    <#
    .DESCRIPTION
        Password for the account (SecureString as a plain string).
        This value is stored in configuration only for test accounts;
        production accounts should use an SSM SecureString parameter.
        Leave empty ("") to skip password operations.
    #>
    [DscProperty()]
    [string] $Password = ""

    <#
    .DESCRIPTION
        When true, the user must change the password on the next logon.
        Default: false.
    #>
    [DscProperty()]
    [bool] $PasswordChangeRequired = $false

    <#
    .DESCRIPTION
        When true, the password never expires.
        Default: false (password expires per domain/local policy).
    #>
    [DscProperty()]
    [bool] $PasswordNeverExpires = $false

    # ── DSC lifecycle methods ────────────────────────────────────────────────

    [DTDS_LocalUser] Get() {
        $result = [DTDS_LocalUser]::new()
        $result.UserName              = $this.UserName
        $result.Description           = $this.Description
        $result.AccountStatus         = $this.AccountStatus
        $result.PasswordChangeRequired = $this.PasswordChangeRequired
        $result.PasswordNeverExpires  = $this.PasswordNeverExpires

        if (-not $this._IsWindows()) {
            # Non-Windows: report as absent for testing
            $result.Ensure = [EnsureValue]::Absent
            return $result
        }

        $user = $this._GetLocalUser()
        if ($null -eq $user) {
            $result.Ensure = [EnsureValue]::Absent
        }
        else {
            $result.Ensure        = [EnsureValue]::Present
            $result.Description   = $user.Description
            $result.AccountStatus = $user.Enabled ? [AccountStatus]::Enabled : [AccountStatus]::Disabled
            $result.PasswordNeverExpires  = $user.PasswordNeverExpires
            $result.PasswordChangeRequired = $user.UserMustChangePassword
        }
        return $result
    }

    [bool] Test() {
        if (-not $this._IsWindows()) { return $true }   # no-op on non-Windows

        $current = $this.Get()

        if ($this.Ensure -eq [EnsureValue]::Absent) {
            return $current.Ensure -eq [EnsureValue]::Absent
        }

        if ($current.Ensure -eq [EnsureValue]::Absent) { return $false }

        $inDesiredState = $true

        if ($this.Description -ne "" -and $current.Description -ne $this.Description) {
            $inDesiredState = $false
        }
        if ($current.AccountStatus -ne $this.AccountStatus) {
            $inDesiredState = $false
        }
        if ($current.PasswordNeverExpires -ne $this.PasswordNeverExpires) {
            $inDesiredState = $false
        }
        if ($current.PasswordChangeRequired -ne $this.PasswordChangeRequired) {
            $inDesiredState = $false
        }

        return $inDesiredState
    }

    [void] Set() {
        if (-not $this._IsWindows()) { return }   # no-op on non-Windows

        $user = $this._GetLocalUser()

        if ($this.Ensure -eq [EnsureValue]::Absent) {
            if ($null -ne $user) {
                Remove-LocalUser -Name $this.UserName
            }
            return
        }

        # Build parameter hashtable for New-LocalUser / Set-LocalUser
        $params = @{
            Name        = $this.UserName
            Description = $this.Description
        }
        if ($this.Password -ne "") {
            $params['Password'] = ConvertTo-SecureString -String $this.Password -AsPlainText -Force
        }
        if ($this.PasswordNeverExpires) {
            $params['PasswordNeverExpires'] = $true
        }
        if ($this.PasswordChangeRequired) {
            $params['UserMustChangePassword'] = $true
        }
        if ($null -eq $user) {
            New-LocalUser @params
        }
        else {
            Set-LocalUser @params
        }

        # Enable / disable separately from creation
        if ($this.AccountStatus -eq [AccountStatus]::Enabled) {
            Enable-LocalUser -Name $this.UserName
        }
        else {
            Disable-LocalUser -Name $this.UserName
        }
    }

    # ── Private helpers ───────────────────────────────────────────────────────

    hidden [object] _GetLocalUser() {
        try {
            return Get-LocalUser -Name $this.UserName -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            return $null
        }
    }

    hidden [bool] _IsWindows() {
        if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
        return $IsWindows
    }
}
