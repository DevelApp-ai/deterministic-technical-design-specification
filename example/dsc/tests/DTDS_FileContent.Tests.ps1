# dsc/tests/DTDS_FileContent.Tests.ps1
#
# Pester 5 unit tests for the DTDS_FileContent DSC resource.
#
# Coverage:
#   - Test() returns $false when file is absent and Ensure = Present
#   - Full lifecycle: Set() creates file → Test() → Get() → Set() removes file
#   - Ensure = Absent removes existing file
#   - Get() reflects disk state accurately
#   - Set() creates intermediate parent directories
#   - Idempotency: two sequential Set() calls leave Test() returning $true
#
# Run locally:
#   pwsh -Command "Invoke-Pester -Path dsc/tests/ -Output Detailed"
#
# CI (GitHub Actions):
#   The dsc-tests job runs these automatically.

BeforeAll {
    # Add the resource module directory to PSModulePath so that
    # Import-Module resolves it by name, enabling InModuleScope access.
    $moduleDir = Join-Path $PSScriptRoot '../resources'
    if ($env:PSModulePath -notlike "*$moduleDir*") {
        $env:PSModulePath = $moduleDir + [System.IO.Path]::PathSeparator + $env:PSModulePath
    }
    Import-Module DTDS_FileContent -Force
}

Describe 'DTDS_FileContent DSC resource' {

    Context 'Test() — file absent, Ensure = Present' {

        It 'returns $false when the managed file does not exist' {
            InModuleScope DTDS_FileContent {
                $resource         = [DTDS_FileContent]::new()
                $resource.Path    = [System.IO.Path]::Combine(
                    [System.IO.Path]::GetTempPath(),
                    [System.IO.Path]::GetRandomFileName()
                )
                $resource.Content = 'hello'
                $resource.Ensure  = [Ensure]::Present

                $resource.Test() | Should -Be $false
            }
        }
    }

    Context 'Test() — file present, Ensure = Absent' {

        BeforeAll {
            $script:existingFile = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                [System.IO.Path]::GetRandomFileName()
            )
            Set-Content -Path $script:existingFile -Value 'existing' -Encoding UTF8
        }

        AfterAll {
            if (Test-Path $script:existingFile) { Remove-Item $script:existingFile -Force }
        }

        It 'returns $false when file exists but should be Absent' {
            $filePath = $script:existingFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $resource         = [DTDS_FileContent]::new()
                $resource.Path    = $FilePath
                $resource.Content = ''
                $resource.Ensure  = [Ensure]::Absent

                $resource.Test() | Should -Be $false
            }
        }
    }

    Context 'Full lifecycle — Set / Test / Get' {

        BeforeAll {
            $script:tmpFile = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                [System.IO.Path]::GetRandomFileName()
            )
        }

        AfterAll {
            if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
        }

        It 'Test() returns $false before Set() is called' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deterministic'
                $r.Ensure  = [Ensure]::Present

                $r.Test() | Should -Be $false
            }
        }

        It 'Set() creates the file with the correct content' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deterministic'
                $r.Ensure  = [Ensure]::Present

                { $r.Set() } | Should -Not -Throw

                Test-Path $FilePath | Should -Be $true
                Get-Content $FilePath -Raw | Should -Be 'deterministic'
            }
        }

        It 'Test() returns $true after Set()' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deterministic'
                $r.Ensure  = [Ensure]::Present

                $r.Test() | Should -Be $true
            }
        }

        It 'Get() reflects Present state with correct content' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deterministic'
                $r.Ensure  = [Ensure]::Present

                $state = $r.Get()

                $state.Ensure  | Should -Be ([Ensure]::Present)
                $state.Content | Should -Be 'deterministic'
            }
        }

        It 'Test() returns $false when content differs from desired' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'different-content'
                $r.Ensure  = [Ensure]::Present

                $r.Test() | Should -Be $false
            }
        }

        It 'Set() removes the file when Ensure = Absent' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = ''
                $r.Ensure  = [Ensure]::Absent

                { $r.Set() } | Should -Not -Throw

                Test-Path $FilePath | Should -Be $false
            }
        }

        It 'Get() reflects Absent state after removal' {
            $filePath = $script:tmpFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deterministic'
                $r.Ensure  = [Ensure]::Present

                $state = $r.Get()

                $state.Ensure | Should -Be ([Ensure]::Absent)
            }
        }
    }

    Context 'Set() — creates intermediate parent directories' {

        BeforeAll {
            $randomSegment    = [System.IO.Path]::GetRandomFileName()
            $script:deepFile  = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(), $randomSegment, 'nested', 'path', 'output.txt'
            )
        }

        AfterAll {
            $topDir = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                ([System.IO.Path]::GetDirectoryName($script:deepFile) -split [System.IO.Path]::DirectorySeparatorChar)[
                    ([System.IO.Path]::GetDirectoryName($script:deepFile) -split [System.IO.Path]::DirectorySeparatorChar).Length - 3
                ]
            )
            # Clean up from temp root
            $parts = $script:deepFile -split [System.IO.Path]::DirectorySeparatorChar
            $cleanDir = $parts[0..($parts.Length - 4)] -join [System.IO.Path]::DirectorySeparatorChar
            if ($cleanDir -and (Test-Path $cleanDir)) { Remove-Item $cleanDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'creates the file even when parent directories do not exist' {
            $filePath = $script:deepFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'deep file'
                $r.Ensure  = [Ensure]::Present

                { $r.Set() } | Should -Not -Throw

                Test-Path $FilePath | Should -Be $true
                Get-Content $FilePath -Raw | Should -Be 'deep file'
            }
        }
    }

    Context 'Test() — idempotency' {

        BeforeAll {
            $script:idempFile = [System.IO.Path]::Combine(
                [System.IO.Path]::GetTempPath(),
                [System.IO.Path]::GetRandomFileName()
            )
            Set-Content -Path $script:idempFile -Value 'stable' -Encoding UTF8 -NoNewline
        }

        AfterAll {
            if (Test-Path $script:idempFile) { Remove-Item $script:idempFile -Force }
        }

        It 'calling Set() twice does not change the result of Test()' {
            $filePath = $script:idempFile
            InModuleScope DTDS_FileContent -Parameters @{ FilePath = $filePath } {
                param($FilePath)
                $r         = [DTDS_FileContent]::new()
                $r.Path    = $FilePath
                $r.Content = 'stable'
                $r.Ensure  = [Ensure]::Present

                $r.Set()
                $r.Test() | Should -Be $true

                $r.Set()
                $r.Test() | Should -Be $true
            }
        }
    }
}
