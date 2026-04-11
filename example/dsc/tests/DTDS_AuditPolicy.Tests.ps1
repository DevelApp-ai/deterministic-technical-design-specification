# dsc/tests/DTDS_AuditPolicy.Tests.ps1
#
# Pester 5 unit tests for DTDS_AuditPolicy DSC resource.
# Run with: pwsh -Command "Invoke-Pester ./dsc/tests/DTDS_AuditPolicy.Tests.ps1 -Output Detailed"
#
# Tests use cross-platform stubs — no Windows system call is made on Linux/macOS.
# Related requirements: DORA-002, NIS2-004, S-008

BeforeAll {
    $resourcePath = Join-Path $PSScriptRoot '../resources/DTDS_AuditPolicy/DTDS_AuditPolicy.psm1'
    Import-Module $resourcePath -Force
}

InModuleScope DTDS_AuditPolicy {

    Describe 'DTDS_AuditPolicy — Get()' {

        It 'Returns an instance with the correct Subcategory' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Logon'
            $resource.AuditFlag   = [AuditTracking]::SuccessAndFailure
            $result = $resource.Get()
            $result.Subcategory | Should -Be 'Logon'
        }

        It 'Get() returns the desired flag on non-Windows (cross-platform stub)' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Process Creation'
            $resource.AuditFlag   = [AuditTracking]::Success
            $result = $resource.Get()
            $result.AuditFlag | Should -Be ([AuditTracking]::Success)
        }

        It 'Get() returns an DTDS_AuditPolicy instance' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Account Lockout'
            $resource.AuditFlag   = [AuditTracking]::Failure
            $result = $resource.Get()
            $result | Should -BeOfType ([DTDS_AuditPolicy])
        }
    }

    Describe 'DTDS_AuditPolicy — Test()' {

        It 'Test() returns $true on non-Windows (no-op platform)' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Logon'
            $resource.AuditFlag   = [AuditTracking]::SuccessAndFailure
            $result = $resource.Test()
            $result | Should -BeTrue
        }

        It 'Test() returns $true for all AuditTracking values on non-Windows' {
            foreach ($flag in [AuditTracking].GetEnumValues()) {
                $resource = [DTDS_AuditPolicy]::new()
                $resource.Subcategory = 'Policy Change'
                $resource.AuditFlag   = $flag
                $resource.Test() | Should -BeTrue
            }
        }
    }

    Describe 'DTDS_AuditPolicy — Set()' {

        It 'Set() does not throw on non-Windows' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Logon'
            $resource.AuditFlag   = [AuditTracking]::SuccessAndFailure
            { $resource.Set() } | Should -Not -Throw
        }
    }

    Describe 'DTDS_AuditPolicy — AuditTracking enum' {

        It 'AuditTracking has NoAuditing value' {
            [AuditTracking]::NoAuditing | Should -BeOfType ([AuditTracking])
        }

        It 'AuditTracking has Success value' {
            [AuditTracking]::Success | Should -BeOfType ([AuditTracking])
        }

        It 'AuditTracking has Failure value' {
            [AuditTracking]::Failure | Should -BeOfType ([AuditTracking])
        }

        It 'AuditTracking has SuccessAndFailure value' {
            [AuditTracking]::SuccessAndFailure | Should -BeOfType ([AuditTracking])
        }
    }

    Describe 'DTDS_AuditPolicy — idempotency' {

        It 'Multiple Test() calls return the same result (idempotent)' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Logon'
            $resource.AuditFlag   = [AuditTracking]::Success
            $first  = $resource.Test()
            $second = $resource.Test()
            $first | Should -Be $second
        }

        It 'Set() followed by Test() does not throw (idempotent cycle)' {
            $resource = [DTDS_AuditPolicy]::new()
            $resource.Subcategory = 'Logon'
            $resource.AuditFlag   = [AuditTracking]::SuccessAndFailure
            { $resource.Set() } | Should -Not -Throw
            { $resource.Test() } | Should -Not -Throw
        }
    }
}
