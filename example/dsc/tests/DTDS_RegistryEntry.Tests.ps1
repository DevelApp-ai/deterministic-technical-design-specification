# dsc/tests/DTDS_RegistryEntry.Tests.ps1
#
# Pester 5 unit tests for the DTDS_RegistryEntry DSC resource.
#
# Coverage:
#   - Test() returns $true on non-Windows (cross-platform CI compatibility)
#   - Get() returns Absent when key/value does not exist
#   - On non-Windows: Set() is a no-op, Test() is always $true
#   - Enum values are correctly defined (String, DWord, etc.)
#   - Ensure = Present / Absent enum values exist
#
# Note: Registry operations require Windows.  All registry-dependent tests
# use conditional execution so that the CI pipeline passes on Linux.
#
# Run locally:
#   pwsh -Command "Invoke-Pester -Path dsc/tests/DTDS_RegistryEntry.Tests.ps1 -Output Detailed"

BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../resources'
    if ($env:PSModulePath -notlike "*$moduleDir*") {
        $env:PSModulePath = $moduleDir + [System.IO.Path]::PathSeparator + $env:PSModulePath
    }
    Import-Module DTDS_RegistryEntry -Force
}

Describe 'DTDS_RegistryEntry DSC resource' {

    Context 'Cross-platform compatibility' {

        It 'Test() returns $true on non-Windows (cross-platform CI)' {
            InModuleScope DTDS_RegistryEntry {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows — skipping Linux-only assertion'
                    return
                }
                $resource             = [DTDS_RegistryEntry]::new()
                $resource.Key         = 'HKLM:\SOFTWARE\DoesNotMatter'
                $resource.ValueName   = 'TestValue'
                $resource.ValueData   = '42'
                $resource.ValueType   = [RegistryValueType]::DWord
                $resource.Ensure      = [Ensure]::Present

                $resource.Test() | Should -Be $true
            }
        }

        It 'Set() does not throw on non-Windows' {
            InModuleScope DTDS_RegistryEntry {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows'
                    return
                }
                $resource             = [DTDS_RegistryEntry]::new()
                $resource.Key         = 'HKLM:\SOFTWARE\DoesNotMatter'
                $resource.ValueName   = 'TestValue'
                $resource.ValueData   = 'hello'
                $resource.Ensure      = [Ensure]::Present

                { $resource.Set() } | Should -Not -Throw
            }
        }

        It 'Get() returns Absent on non-Windows' {
            InModuleScope DTDS_RegistryEntry {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows'
                    return
                }
                $resource             = [DTDS_RegistryEntry]::new()
                $resource.Key         = 'HKLM:\SOFTWARE\DoesNotMatter'
                $resource.ValueName   = 'TestValue'
                $resource.ValueData   = 'hello'
                $resource.Ensure      = [Ensure]::Present

                $state = $resource.Get()
                $state.Ensure | Should -Be ([Ensure]::Absent)
            }
        }
    }

    Context 'Enum definitions' {

        It 'Ensure enum has Present and Absent values' {
            InModuleScope DTDS_RegistryEntry {
                [Ensure]::Present | Should -Not -BeNullOrEmpty
                [Ensure]::Absent  | Should -Not -BeNullOrEmpty
            }
        }

        It 'RegistryValueType enum has all expected types' {
            InModuleScope DTDS_RegistryEntry {
                [RegistryValueType]::String       | Should -Not -BeNullOrEmpty
                [RegistryValueType]::ExpandString | Should -Not -BeNullOrEmpty
                [RegistryValueType]::DWord        | Should -Not -BeNullOrEmpty
                [RegistryValueType]::QWord        | Should -Not -BeNullOrEmpty
                [RegistryValueType]::Binary       | Should -Not -BeNullOrEmpty
                [RegistryValueType]::MultiString  | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Default property values' {

        It 'Ensure defaults to Present' {
            InModuleScope DTDS_RegistryEntry {
                $resource = [DTDS_RegistryEntry]::new()
                $resource.Ensure | Should -Be ([Ensure]::Present)
            }
        }

        It 'ValueType defaults to String' {
            InModuleScope DTDS_RegistryEntry {
                $resource = [DTDS_RegistryEntry]::new()
                $resource.ValueType | Should -Be ([RegistryValueType]::String)
            }
        }
    }

    Context 'Windows — full lifecycle' -Skip:(-not $IsWindows) {

        BeforeAll {
            $script:testKey   = "HKCU:\SOFTWARE\DTDS_RegistryEntry_Tests_$(Get-Random)"
            $script:testValue = 'TestSetting'
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:testKey) {
                Remove-Item -LiteralPath $script:testKey -Recurse -Force
            }
        }

        It 'Test() returns $false when value is absent and Ensure = Present' {
            InModuleScope DTDS_RegistryEntry -Parameters @{ Key = $script:testKey; ValueName = $script:testValue } {
                param($Key, $ValueName)
                $resource           = [DTDS_RegistryEntry]::new()
                $resource.Key       = $Key
                $resource.ValueName = $ValueName
                $resource.ValueData = 'hello'
                $resource.Ensure    = [Ensure]::Present

                $resource.Test() | Should -Be $false
            }
        }

        It 'Set() creates the registry key and value' {
            InModuleScope DTDS_RegistryEntry -Parameters @{ Key = $script:testKey; ValueName = $script:testValue } {
                param($Key, $ValueName)
                $resource           = [DTDS_RegistryEntry]::new()
                $resource.Key       = $Key
                $resource.ValueName = $ValueName
                $resource.ValueData = 'configured'
                $resource.ValueType = [RegistryValueType]::String
                $resource.Ensure    = [Ensure]::Present

                { $resource.Set() } | Should -Not -Throw
                Test-Path -LiteralPath $Key | Should -Be $true
                (Get-ItemPropertyValue -Path $Key -Name $ValueName) | Should -Be 'configured'
            }
        }

        It 'Test() returns $true after Set()' {
            InModuleScope DTDS_RegistryEntry -Parameters @{ Key = $script:testKey; ValueName = $script:testValue } {
                param($Key, $ValueName)
                $resource           = [DTDS_RegistryEntry]::new()
                $resource.Key       = $Key
                $resource.ValueName = $ValueName
                $resource.ValueData = 'configured'
                $resource.Ensure    = [Ensure]::Present

                $resource.Test() | Should -Be $true
            }
        }

        It 'Set(Absent) removes the value' {
            InModuleScope DTDS_RegistryEntry -Parameters @{ Key = $script:testKey; ValueName = $script:testValue } {
                param($Key, $ValueName)
                $resource           = [DTDS_RegistryEntry]::new()
                $resource.Key       = $Key
                $resource.ValueName = $ValueName
                $resource.ValueData = ''
                $resource.Ensure    = [Ensure]::Absent

                { $resource.Set() } | Should -Not -Throw
                { Get-ItemPropertyValue -Path $Key -Name $ValueName -ErrorAction Stop } | Should -Throw
            }
        }
    }
}
