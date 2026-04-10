# resources/DTDS_FileContent/DTDS_FileContent.psd1
#
# PowerShell module manifest for the DTDS_FileContent DSC resource.
# This manifest is read by DscResource.DocGenerator when generating
# Markdown documentation for the resource.

@{
    RootModule           = 'DTDS_FileContent.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author               = 'platform-team'
    CompanyName          = 'DevelApp-ai'
    Description          = 'DSC resource that manages text file content — part of the deterministic documentation example.'
    PowerShellVersion    = '7.2'
    DscResourcesToExport = @('DTDS_FileContent')

    PrivateData = @{
        PSData = @{
            Tags         = @('DSC', 'File', 'CrossPlatform', 'Documentation', 'DeterministicDocs')
            ProjectUri   = 'https://github.com/DevelApp-ai/deterministic-technical-design-specification'
            LicenseUri   = 'https://github.com/DevelApp-ai/deterministic-technical-design-specification/blob/main/LICENSE'
            ReleaseNotes = 'Initial release — demonstrates class-based DSC resource with auto-generated documentation.'
        }
    }
}
