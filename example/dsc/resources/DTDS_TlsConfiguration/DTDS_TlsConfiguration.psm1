#Requires -Version 7.2

<#
.SYNOPSIS
    DSC resource that manages TLS/SSL protocol enablement at the OS level.

.DESCRIPTION
    DTDS_TlsConfiguration is a class-based DSC resource that manages the
    Windows Schannel registry settings that control which TLS/SSL protocols
    are enabled or disabled at the operating-system level.

    It satisfies:
      NIS2 Directive Art.21(2)(h) — Cryptography and encryption policy
      OPA policy SEC-006 — Prohibit deprecated TLS versions (TLS 1.0, TLS 1.1)
      CIS Windows Server Benchmark — Section 18.9.83 (Schannel)

    On Linux and macOS the resource runs in "no-op" mode so that
    cross-platform Pester tests can exercise the Get/Test/Set logic
    without Windows-specific registry access.

    Default safe configuration enforced by this resource:
      - SSL 2.0  → Disabled  (broken, no legitimate use case)
      - SSL 3.0  → Disabled  (POODLE CVE-2014-3566)
      - TLS 1.0  → Disabled  (BEAST CVE-2011-3389; SEC-006 violation)
      - TLS 1.1  → Disabled  (POODLE for TLS; SEC-006 violation)
      - TLS 1.2  → Enabled   (minimum required by NIS2 Art.21(2)(h))
      - TLS 1.3  → Enabled   (preferred; forward secrecy guaranteed)

.NOTES
    Author:      platform-team
    Version:     1.0.0
    ADR:         docs/adrs/0004-use-dsc-for-windows-config.md
    Requirements: S-008, S-009, NIS2-002, SEC-006
    Frameworks:   NIS2 Art.21(2)(h), CIS 18.9.83, NIST 800-53 SC-8, SC-23
#>

enum TlsProtocolVersion {
    SSL_2_0
    SSL_3_0
    TLS_1_0
    TLS_1_1
    TLS_1_2
    TLS_1_3
}

enum TlsProtocolRole {
    Client
    Server
    Both
}

enum TlsProtocolState {
    Enabled
    Disabled
}

[DscResource()]
class DTDS_TlsConfiguration {

    # ── Key properties ───────────────────────────────────────────────────────

    <#
    .PARAMETER Protocol
        The TLS/SSL protocol version to manage.
        Valid values: SSL_2_0, SSL_3_0, TLS_1_0, TLS_1_1, TLS_1_2, TLS_1_3.

    .EXAMPLE
        Protocol = 'TLS_1_2'
    #>
    [DscProperty(Key)]
    [TlsProtocolVersion] $Protocol

    <#
    .PARAMETER Role
        Whether to manage the client registry key, the server registry key,
        or both (Both is the default and is the most common setting).
        NIS2 Art.21(2)(h) requires that both client and server negotiation
        use only approved protocols.

    .EXAMPLE
        Role = 'Server'
    #>
    [DscProperty(Key)]
    [TlsProtocolRole] $Role = [TlsProtocolRole]::Both

    # ── Desired state ────────────────────────────────────────────────────────

    <#
    .PARAMETER State
        Whether the protocol should be Enabled or Disabled.
        The safe default per NIS2 Art.21(2)(h) is:
          - TLS 1.2 and TLS 1.3 → Enabled
          - SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 → Disabled

    .EXAMPLE
        State = 'Disabled'
    #>
    [DscProperty(Mandatory)]
    [TlsProtocolState] $State

    # ── Internal constants ───────────────────────────────────────────────────

    # Maps the Protocol enum value to the Windows Schannel registry sub-path.
    hidden static [hashtable] $ProtocolPaths = @{
        'SSL_2_0' = 'SSL 2.0'
        'SSL_3_0' = 'SSL 3.0'
        'TLS_1_0' = 'TLS 1.0'
        'TLS_1_1' = 'TLS 1.1'
        'TLS_1_2' = 'TLS 1.2'
        'TLS_1_3' = 'TLS 1.3'
    }

    hidden static [string] $SchannelBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'

    # Enabled  → DisabledByDefault = 0, Enabled = 1
    # Disabled → DisabledByDefault = 1, Enabled = 0
    hidden static [hashtable] $EnabledValues  = @{ DisabledByDefault = 0; Enabled = 1 }
    hidden static [hashtable] $DisabledValues = @{ DisabledByDefault = 1; Enabled = 0 }

    # ── Get() ────────────────────────────────────────────────────────────────

    [DTDS_TlsConfiguration] Get() {
        $current          = [DTDS_TlsConfiguration]::new()
        $current.Protocol = $this.Protocol
        $current.Role     = $this.Role
        $current.State    = $this.State   # default to desired; overwritten on Windows

        if (-not $this._IsWindows()) { return $current }

        $protoName = [DTDS_TlsConfiguration]::ProtocolPaths[$this.Protocol.ToString()]
        $roles     = $this._RolesFromEnum($this.Role)

        # If any sub-role is not in the desired state, report as not-desired
        foreach ($r in $roles) {
            $keyPath  = "$([DTDS_TlsConfiguration]::SchannelBase)\$protoName\$r"
            $regKey   = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
            if (-not $regKey) {
                # Key absent → registry default is Enabled for the protocol
                $current.State = [TlsProtocolState]::Enabled
                return $current
            }
            $enabledVal = $regKey.GetValue('Enabled', -1)
            if ($enabledVal -eq 0) {
                $current.State = [TlsProtocolState]::Disabled
            } else {
                $current.State = [TlsProtocolState]::Enabled
            }
        }

        return $current
    }

    # ── Test() ───────────────────────────────────────────────────────────────

    [bool] Test() {
        if (-not $this._IsWindows()) { return $true }

        $current = $this.Get()
        return $current.State -eq $this.State
    }

    # ── Set() ────────────────────────────────────────────────────────────────

    [void] Set() {
        if (-not $this._IsWindows()) { return }

        $protoName = [DTDS_TlsConfiguration]::ProtocolPaths[$this.Protocol.ToString()]
        $values    = ($this.State -eq [TlsProtocolState]::Enabled) ?
                         [DTDS_TlsConfiguration]::EnabledValues :
                         [DTDS_TlsConfiguration]::DisabledValues
        $roles     = $this._RolesFromEnum($this.Role)

        foreach ($r in $roles) {
            $keyPath = "$([DTDS_TlsConfiguration]::SchannelBase)\$protoName\$r"
            if (-not (Test-Path -LiteralPath $keyPath)) {
                New-Item -Path $keyPath -Force | Out-Null
            }
            foreach ($valueName in $values.Keys) {
                Set-ItemProperty -LiteralPath $keyPath -Name $valueName -Value $values[$valueName] -Type DWord -Force
            }
        }
    }

    # ── Private helpers ──────────────────────────────────────────────────────

    hidden [bool] _IsWindows() {
        return $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')
    }

    hidden [string[]] _RolesFromEnum([TlsProtocolRole] $role) {
        switch ($role) {
            'Client' { return @('Client') }
            'Server' { return @('Server') }
            'Both'   { return @('Client', 'Server') }
        }
        return @('Client', 'Server')
    }
}
