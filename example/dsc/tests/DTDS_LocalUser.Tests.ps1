#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the DTDS_LocalUser DSC resource.

.DESCRIPTION
    Tests cover: Present/Absent lifecycle on Windows; description and status
    drift detection; no-op behaviour on Linux/macOS.  All tests run on both
    Windows and Linux CI runners.

.NOTES
    ADR:  docs/adrs/0004-use-dsc-for-windows-config.md
    Test pattern: InModuleScope so class types are accessible without
    full DSC discovery (required on Linux/macOS where LCM is absent).
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../resources/DTDS_LocalUser/DTDS_LocalUser.psm1'
    Import-Module $modulePath -Force
}

InModuleScope DTDS_LocalUser {

    Describe 'DTDS_LocalUser — non-Windows (cross-platform) behaviour' {

        BeforeEach {
            # Force non-Windows mode by patching the helper
            $resource = [DTDS_LocalUser]::new()
            $resource.UserName = 'test-svc'
        }

        Context 'Get() on non-Windows' {
            It 'Returns Absent because local users are not checked on Linux' {
                Mock _IsWindows { return $false } -ModuleName DTDS_LocalUser
                $result = $resource.Get()
                $result.Ensure | Should -Be 'Absent'
            }
        }

        Context 'Test() on non-Windows' {
            It 'Always returns $true on non-Windows (no-op)' {
                Mock _IsWindows { return $false } -ModuleName DTDS_LocalUser
                $resource.Ensure = [EnsureValue]::Present
                $resource.Test() | Should -BeTrue
            }
        }

        Context 'Set() on non-Windows' {
            It 'Completes without error (no-op)' {
                Mock _IsWindows { return $false } -ModuleName DTDS_LocalUser
                { $resource.Set() } | Should -Not -Throw
            }
        }
    }

    Describe 'DTDS_LocalUser — Windows lifecycle (mocked)' {

        BeforeEach {
            $resource = [DTDS_LocalUser]::new()
            $resource.UserName      = 'svc-dtds-app'
            $resource.Description   = 'DTDS application service account'
            $resource.AccountStatus = [AccountStatus]::Enabled
            $resource.Ensure        = [EnsureValue]::Present
        }

        Context 'Get() — user exists' {
            It 'Returns Present when user exists' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser {
                    return [PSCustomObject]@{
                        Name                  = 'svc-dtds-app'
                        Description           = 'DTDS application service account'
                        Enabled               = $true
                        PasswordNeverExpires  = $false
                        UserMustChangePassword = $false
                    }
                } -ModuleName DTDS_LocalUser

                $result = $resource.Get()
                $result.Ensure       | Should -Be 'Present'
                $result.Description  | Should -Be 'DTDS application service account'
                $result.AccountStatus | Should -Be 'Enabled'
            }
        }

        Context 'Get() — user does not exist' {
            It 'Returns Absent when user is missing' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser { return $null } -ModuleName DTDS_LocalUser
                $resource.Get().Ensure | Should -Be 'Absent'
            }
        }

        Context 'Test() — desired state matches' {
            It 'Returns $true when current state matches desired' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser {
                    return [PSCustomObject]@{
                        Name                  = 'svc-dtds-app'
                        Description           = 'DTDS application service account'
                        Enabled               = $true
                        PasswordNeverExpires  = $false
                        UserMustChangePassword = $false
                    }
                } -ModuleName DTDS_LocalUser
                $resource.Test() | Should -BeTrue
            }
        }

        Context 'Test() — description drift' {
            It 'Returns $false when description differs' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser {
                    return [PSCustomObject]@{
                        Name                  = 'svc-dtds-app'
                        Description           = 'Old description'
                        Enabled               = $true
                        PasswordNeverExpires  = $false
                        UserMustChangePassword = $false
                    }
                } -ModuleName DTDS_LocalUser
                $resource.Test() | Should -BeFalse
            }
        }

        Context 'Test() — account status drift' {
            It 'Returns $false when account is disabled but should be enabled' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser {
                    return [PSCustomObject]@{
                        Name                  = 'svc-dtds-app'
                        Description           = 'DTDS application service account'
                        Enabled               = $false   # disabled on host
                        PasswordNeverExpires  = $false
                        UserMustChangePassword = $false
                    }
                } -ModuleName DTDS_LocalUser
                $resource.Test() | Should -BeFalse
            }
        }

        Context 'Set() — user absent, should be Present' {
            It 'Calls New-LocalUser and Enable-LocalUser' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser { return $null } -ModuleName DTDS_LocalUser
                Mock New-LocalUser {} -ModuleName DTDS_LocalUser
                Mock Enable-LocalUser {} -ModuleName DTDS_LocalUser
                Mock Disable-LocalUser {} -ModuleName DTDS_LocalUser

                $resource.Set()

                Should -Invoke New-LocalUser -Times 1 -ModuleName DTDS_LocalUser
                Should -Invoke Enable-LocalUser -Times 1 -ModuleName DTDS_LocalUser
            }
        }

        Context 'Set() — Ensure = Absent' {
            It 'Removes an existing user' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser {
                    return [PSCustomObject]@{ Name = 'svc-dtds-app' }
                } -ModuleName DTDS_LocalUser
                Mock Remove-LocalUser {} -ModuleName DTDS_LocalUser

                $resource.Ensure = [EnsureValue]::Absent
                $resource.Set()

                Should -Invoke Remove-LocalUser -Times 1 -ModuleName DTDS_LocalUser
            }

            It 'Does nothing when user is already absent' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser { return $null } -ModuleName DTDS_LocalUser
                Mock Remove-LocalUser {} -ModuleName DTDS_LocalUser

                $resource.Ensure = [EnsureValue]::Absent
                $resource.Set()

                Should -Invoke Remove-LocalUser -Times 0 -ModuleName DTDS_LocalUser
            }
        }

        Context 'Set() — AccountStatus = Disabled' {
            It 'Calls Disable-LocalUser when status should be Disabled' {
                Mock _IsWindows { return $true } -ModuleName DTDS_LocalUser
                Mock _GetLocalUser { return $null } -ModuleName DTDS_LocalUser
                Mock New-LocalUser {} -ModuleName DTDS_LocalUser
                Mock Disable-LocalUser {} -ModuleName DTDS_LocalUser
                Mock Enable-LocalUser {} -ModuleName DTDS_LocalUser

                $resource.AccountStatus = [AccountStatus]::Disabled
                $resource.Set()

                Should -Invoke Disable-LocalUser -Times 1 -ModuleName DTDS_LocalUser
                Should -Invoke Enable-LocalUser -Times 0 -ModuleName DTDS_LocalUser
            }
        }
    }
}
