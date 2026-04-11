# dsc/tests/DTDS_ServiceConfig.Tests.ps1
#
# Pester 5 unit tests for the DTDS_ServiceConfig DSC resource.
#
# Coverage:
#   - Cross-platform: Test() returns $true on non-Windows
#   - Cross-platform: Set() is a no-op on non-Windows
#   - Enum values are correctly defined (Running/Stopped, Automatic/Manual/Disabled)
#   - Default property values
#   - Windows-only: full lifecycle (requires actual service)
#
# Run locally:
#   pwsh -Command "Invoke-Pester -Path dsc/tests/DTDS_ServiceConfig.Tests.ps1 -Output Detailed"

BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../resources'
    if ($env:PSModulePath -notlike "*$moduleDir*") {
        $env:PSModulePath = $moduleDir + [System.IO.Path]::PathSeparator + $env:PSModulePath
    }
    Import-Module DTDS_ServiceConfig -Force
}

Describe 'DTDS_ServiceConfig DSC resource' {

    Context 'Cross-platform compatibility' {

        It 'Test() returns $true on non-Windows' {
            InModuleScope DTDS_ServiceConfig {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows'
                    return
                }
                $resource             = [DTDS_ServiceConfig]::new()
                $resource.ServiceName = 'AnyServiceName'
                $resource.State       = [ServiceState]::Running
                $resource.StartupType = [ServiceStartupType]::Automatic

                $resource.Test() | Should -Be $true
            }
        }

        It 'Set() does not throw on non-Windows' {
            InModuleScope DTDS_ServiceConfig {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows'
                    return
                }
                $resource             = [DTDS_ServiceConfig]::new()
                $resource.ServiceName = 'AnyServiceName'
                $resource.State       = [ServiceState]::Stopped
                $resource.StartupType = [ServiceStartupType]::Disabled

                { $resource.Set() } | Should -Not -Throw
            }
        }

        It 'Get() returns defaults on non-Windows' {
            InModuleScope DTDS_ServiceConfig {
                if ($IsWindows) {
                    Set-ItResult -Skipped -Because 'Running on Windows'
                    return
                }
                $resource             = [DTDS_ServiceConfig]::new()
                $resource.ServiceName = 'AnyServiceName'
                $resource.State       = [ServiceState]::Running
                $resource.StartupType = [ServiceStartupType]::Automatic

                $state = $resource.Get()
                # On non-Windows the defaults are reflected back unchanged
                $state.ServiceName | Should -Be 'AnyServiceName'
                $state.State       | Should -Be ([ServiceState]::Running)
            }
        }
    }

    Context 'Enum definitions' {

        It 'ServiceState enum has Running and Stopped' {
            InModuleScope DTDS_ServiceConfig {
                [ServiceState]::Running | Should -Not -BeNullOrEmpty
                [ServiceState]::Stopped | Should -Not -BeNullOrEmpty
            }
        }

        It 'ServiceStartupType enum has all three values' {
            InModuleScope DTDS_ServiceConfig {
                [ServiceStartupType]::Automatic | Should -Not -BeNullOrEmpty
                [ServiceStartupType]::Manual    | Should -Not -BeNullOrEmpty
                [ServiceStartupType]::Disabled  | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Default property values' {

        It 'State defaults to Running' {
            InModuleScope DTDS_ServiceConfig {
                $resource = [DTDS_ServiceConfig]::new()
                $resource.State | Should -Be ([ServiceState]::Running)
            }
        }

        It 'StartupType defaults to Automatic' {
            InModuleScope DTDS_ServiceConfig {
                $resource = [DTDS_ServiceConfig]::new()
                $resource.StartupType | Should -Be ([ServiceStartupType]::Automatic)
            }
        }
    }

    Context 'Windows — existing service query' -Skip:(-not $IsWindows) {

        It 'Get() returns current state of a known service' {
            InModuleScope DTDS_ServiceConfig {
                # WinRM is always present on Windows
                $resource             = [DTDS_ServiceConfig]::new()
                $resource.ServiceName = 'WinRM'
                $resource.State       = [ServiceState]::Running
                $resource.StartupType = [ServiceStartupType]::Automatic

                $state = $resource.Get()
                $state.ServiceName | Should -Be 'WinRM'
                $state.State       | Should -BeIn @([ServiceState]::Running, [ServiceState]::Stopped)
            }
        }

        It 'Set() throws for a non-existent service' {
            InModuleScope DTDS_ServiceConfig {
                $resource             = [DTDS_ServiceConfig]::new()
                $resource.ServiceName = 'ThisServiceDoesNotExist_DTDS_Test'
                $resource.State       = [ServiceState]::Running
                $resource.StartupType = [ServiceStartupType]::Automatic

                { $resource.Set() } | Should -Throw
            }
        }
    }
}
