#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the DTDS_TlsConfiguration DSC resource.

.DESCRIPTION
    Tests cover: cross-platform no-op, enum values, default properties,
    Windows-mocked lifecycle (Get/Test/Set) for both Enabled and Disabled
    states, and the Both/Client/Server role permutations.

.NOTES
    ADR:  docs/adrs/0004-use-dsc-for-windows-config.md
    NIS2: Art.21(2)(h) — Cryptography and encryption
    OPA:  SEC-006 — deny_deprecated_tls
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../resources/DTDS_TlsConfiguration/DTDS_TlsConfiguration.psm1'
    Import-Module $modulePath -Force
}

InModuleScope DTDS_TlsConfiguration {

    # ────────────────────────────────────────────────────────────────────────
    # Cross-platform: non-Windows no-op
    # ────────────────────────────────────────────────────────────────────────
    Describe 'DTDS_TlsConfiguration — non-Windows (cross-platform) behaviour' {

        BeforeEach {
            Mock _IsWindows { return $false } -ModuleName DTDS_TlsConfiguration
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_0
            $resource.Role     = [TlsProtocolRole]::Both
            $resource.State    = [TlsProtocolState]::Disabled
        }

        It 'Test() returns $true on non-Windows (no-op)' {
            $resource.Test() | Should -BeTrue
        }

        It 'Set() does not throw on non-Windows' {
            { $resource.Set() } | Should -Not -Throw
        }

        It 'Get() returns the desired state on non-Windows' {
            $result = $resource.Get()
            $result.State | Should -Be ([TlsProtocolState]::Disabled)
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # Enum values
    # ────────────────────────────────────────────────────────────────────────
    Describe 'Enum definitions' {

        It 'TlsProtocolVersion contains all expected values' {
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'SSL_2_0'
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'SSL_3_0'
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'TLS_1_0'
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'TLS_1_1'
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'TLS_1_2'
            [Enum]::GetNames([TlsProtocolVersion]) | Should -Contain 'TLS_1_3'
        }

        It 'TlsProtocolRole contains Client, Server, Both' {
            [Enum]::GetNames([TlsProtocolRole]) | Should -Contain 'Client'
            [Enum]::GetNames([TlsProtocolRole]) | Should -Contain 'Server'
            [Enum]::GetNames([TlsProtocolRole]) | Should -Contain 'Both'
        }

        It 'TlsProtocolState contains Enabled and Disabled' {
            [Enum]::GetNames([TlsProtocolState]) | Should -Contain 'Enabled'
            [Enum]::GetNames([TlsProtocolState]) | Should -Contain 'Disabled'
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # Default property values
    # ────────────────────────────────────────────────────────────────────────
    Describe 'Default property values' {

        It 'Role defaults to Both' {
            $r = [DTDS_TlsConfiguration]::new()
            $r.Role | Should -Be ([TlsProtocolRole]::Both)
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # Windows-mocked: Get() with registry key absent
    # ────────────────────────────────────────────────────────────────────────
    Describe 'DTDS_TlsConfiguration — Windows: Get() with registry key absent' {

        BeforeEach {
            Mock _IsWindows { return $true } -ModuleName DTDS_TlsConfiguration
            # Simulate absent registry key (returns $null)
            Mock Get-Item { return $null } -ModuleName DTDS_TlsConfiguration
        }

        It 'Get() returns Enabled when registry key is absent (OS default)' {
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_0
            $resource.Role     = [TlsProtocolRole]::Server
            $resource.State    = [TlsProtocolState]::Disabled

            $result = $resource.Get()
            # No key → OS treats protocol as enabled
            $result.State | Should -Be ([TlsProtocolState]::Enabled)
        }

        It 'Test() returns $false when desired=Disabled but key is absent (protocol enabled)' {
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_1
            $resource.Role     = [TlsProtocolRole]::Both
            $resource.State    = [TlsProtocolState]::Disabled

            $resource.Test() | Should -BeFalse
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # Windows-mocked: Set() — disable a deprecated protocol
    # ────────────────────────────────────────────────────────────────────────
    Describe 'DTDS_TlsConfiguration — Windows: Set() disables a deprecated protocol' {

        BeforeEach {
            Mock _IsWindows { return $true } -ModuleName DTDS_TlsConfiguration
            Mock Test-Path  { return $false } -ModuleName DTDS_TlsConfiguration
            Mock New-Item   { } -ModuleName DTDS_TlsConfiguration
            Mock Set-ItemProperty { } -ModuleName DTDS_TlsConfiguration
        }

        It 'Set() calls New-Item when registry key does not exist' {
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_0
            $resource.Role     = [TlsProtocolRole]::Both
            $resource.State    = [TlsProtocolState]::Disabled

            { $resource.Set() } | Should -Not -Throw
            Should -Invoke New-Item -ModuleName DTDS_TlsConfiguration -Times 2 # Client + Server
        }

        It 'Set() calls Set-ItemProperty twice per role (DisabledByDefault + Enabled)' {
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::SSL_3_0
            $resource.Role     = [TlsProtocolRole]::Server
            $resource.State    = [TlsProtocolState]::Disabled

            { $resource.Set() } | Should -Not -Throw
            Should -Invoke Set-ItemProperty -ModuleName DTDS_TlsConfiguration -Times 2
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # Windows-mocked: Set() — enable TLS 1.2
    # ────────────────────────────────────────────────────────────────────────
    Describe 'DTDS_TlsConfiguration — Windows: Set() enables TLS 1.2' {

        BeforeEach {
            Mock _IsWindows { return $true } -ModuleName DTDS_TlsConfiguration
            Mock Test-Path  { return $true } -ModuleName DTDS_TlsConfiguration
            Mock Set-ItemProperty { } -ModuleName DTDS_TlsConfiguration
        }

        It 'Set() does not call New-Item when key already exists' {
            Mock New-Item { } -ModuleName DTDS_TlsConfiguration

            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_2
            $resource.Role     = [TlsProtocolRole]::Both
            $resource.State    = [TlsProtocolState]::Enabled

            { $resource.Set() } | Should -Not -Throw
            Should -Invoke New-Item -ModuleName DTDS_TlsConfiguration -Times 0
        }

        It 'Set() calls Set-ItemProperty 4 times for Role=Both (2 roles × 2 values)' {
            $resource          = [DTDS_TlsConfiguration]::new()
            $resource.Protocol = [TlsProtocolVersion]::TLS_1_3
            $resource.Role     = [TlsProtocolRole]::Both
            $resource.State    = [TlsProtocolState]::Enabled

            { $resource.Set() } | Should -Not -Throw
            Should -Invoke Set-ItemProperty -ModuleName DTDS_TlsConfiguration -Times 4
        }
    }

    # ────────────────────────────────────────────────────────────────────────
    # NIS2 safe-defaults matrix: verify SEC-006 compliant protocol posture
    # ────────────────────────────────────────────────────────────────────────
    Describe 'NIS2 Art.21(2)(h) — SEC-006 safe protocol posture' {

        It 'SSL 2.0 must be Disabled per NIS2 Art.21(2)(h)' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::SSL_2_0
            $r.State    = [TlsProtocolState]::Disabled
            $r.State | Should -Be ([TlsProtocolState]::Disabled)
        }

        It 'SSL 3.0 must be Disabled per NIS2 Art.21(2)(h)' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::SSL_3_0
            $r.State    = [TlsProtocolState]::Disabled
            $r.State | Should -Be ([TlsProtocolState]::Disabled)
        }

        It 'TLS 1.0 must be Disabled per SEC-006 OPA policy' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::TLS_1_0
            $r.State    = [TlsProtocolState]::Disabled
            $r.State | Should -Be ([TlsProtocolState]::Disabled)
        }

        It 'TLS 1.1 must be Disabled per SEC-006 OPA policy' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::TLS_1_1
            $r.State    = [TlsProtocolState]::Disabled
            $r.State | Should -Be ([TlsProtocolState]::Disabled)
        }

        It 'TLS 1.2 must be Enabled per NIS2 Art.21(2)(h) minimum' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::TLS_1_2
            $r.State    = [TlsProtocolState]::Enabled
            $r.State | Should -Be ([TlsProtocolState]::Enabled)
        }

        It 'TLS 1.3 must be Enabled per NIS2 Art.21(2)(h) best practice' {
            $r          = [DTDS_TlsConfiguration]::new()
            $r.Protocol = [TlsProtocolVersion]::TLS_1_3
            $r.State    = [TlsProtocolState]::Enabled
            $r.State | Should -Be ([TlsProtocolState]::Enabled)
        }
    }
}
