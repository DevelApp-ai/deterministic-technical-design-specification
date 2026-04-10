# dsc/tests/DTDS_FirewallRule.Tests.ps1
#
# Pester 5 unit tests for DTDS_FirewallRule DSC resource.
# Run with: pwsh -Command "Invoke-Pester ./dsc/tests/DTDS_FirewallRule.Tests.ps1 -Output Detailed"
#
# Tests use cross-platform stubs — netsh is not called on Linux/macOS.
# Related requirements: CYB-004, SEC-004, DORA-001

BeforeAll {
    $resourcePath = Join-Path $PSScriptRoot '../resources/DTDS_FirewallRule/DTDS_FirewallRule.psm1'
    Import-Module $resourcePath -Force
}

InModuleScope DTDS_FirewallRule {

    Describe 'DTDS_FirewallRule — Get()' {

        It 'Returns an instance with the correct RuleName' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Block-RDP-Inbound'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '3389'
            $resource.Action    = [FirewallAction]::Block
            $resource.Ensure    = [FirewallEnsure]::Present
            $result = $resource.Get()
            $result.RuleName | Should -Be 'Block-RDP-Inbound'
        }

        It 'Get() returns an DTDS_FirewallRule instance' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Allow-HTTPS-Out'
            $resource.Direction = [FirewallDirection]::Outbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '443'
            $resource.Action    = [FirewallAction]::Allow
            $result = $resource.Get()
            $result | Should -BeOfType ([DTDS_FirewallRule])
        }

        It 'Get() reflects the correct Direction' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Test-Outbound'
            $resource.Direction = [FirewallDirection]::Outbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '8080'
            $resource.Action    = [FirewallAction]::Allow
            $result = $resource.Get()
            $result.Direction | Should -Be ([FirewallDirection]::Outbound)
        }

        It 'Get() reflects the correct Action' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Test-Block'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '23'
            $resource.Action    = [FirewallAction]::Block
            $result = $resource.Get()
            $result.Action | Should -Be ([FirewallAction]::Block)
        }
    }

    Describe 'DTDS_FirewallRule — Test()' {

        It 'Test() returns $true on non-Windows (no-op platform)' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Block-RDP'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '3389'
            $resource.Action    = [FirewallAction]::Block
            $resource.Test() | Should -BeTrue
        }

        It 'Test() returns $true for Absent rule on non-Windows' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Old-Rule'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'Any'
            $resource.LocalPort = 'Any'
            $resource.Action    = [FirewallAction]::Allow
            $resource.Ensure    = [FirewallEnsure]::Absent
            $resource.Test() | Should -BeTrue
        }
    }

    Describe 'DTDS_FirewallRule — Set()' {

        It 'Set() does not throw on non-Windows for Present' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Block-Telnet'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '23'
            $resource.Action    = [FirewallAction]::Block
            $resource.Ensure    = [FirewallEnsure]::Present
            { $resource.Set() } | Should -Not -Throw
        }

        It 'Set() does not throw on non-Windows for Absent' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Old-Rule-Remove'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = 'Any'
            $resource.Action    = [FirewallAction]::Allow
            $resource.Ensure    = [FirewallEnsure]::Absent
            { $resource.Set() } | Should -Not -Throw
        }
    }

    Describe 'DTDS_FirewallRule — Description property' {

        It 'Defaults to empty string' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Test'
            $resource.Direction = [FirewallDirection]::Inbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '80'
            $resource.Action    = [FirewallAction]::Allow
            $resource.Description | Should -Be ''
        }

        It 'Accepts a non-empty description' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName    = 'Test-Desc'
            $resource.Direction   = [FirewallDirection]::Inbound
            $resource.Protocol    = 'TCP'
            $resource.LocalPort   = '80'
            $resource.Action      = [FirewallAction]::Allow
            $resource.Description = 'Block legacy port — CYB-004'
            $resource.Description | Should -Be 'Block legacy port — CYB-004'
        }
    }

    Describe 'DTDS_FirewallRule — idempotency' {

        It 'Multiple Test() calls return the same result' {
            $resource = [DTDS_FirewallRule]::new()
            $resource.RuleName  = 'Idempotent-Test'
            $resource.Direction = [FirewallDirection]::Outbound
            $resource.Protocol  = 'TCP'
            $resource.LocalPort = '443'
            $resource.Action    = [FirewallAction]::Allow
            $first  = $resource.Test()
            $second = $resource.Test()
            $first | Should -Be $second
        }
    }
}
