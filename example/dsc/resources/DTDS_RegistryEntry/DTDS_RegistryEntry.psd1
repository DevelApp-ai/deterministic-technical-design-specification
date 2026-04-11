@{
    RootModule        = 'DTDS_RegistryEntry.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b4e7c3d2-91a0-4f5e-8b6c-2d0f1a3e5794'
    Author            = 'platform-team'
    Description       = 'DSC resource that manages a Windows Registry value deterministically.'
    PowerShellVersion = '7.2'
    DscResourcesToExport = @('DTDS_RegistryEntry')
    PrivateData = @{
        PSData = @{
            Tags = @('DSC', 'Registry', 'Windows', 'Configuration', 'Documentation')
        }
    }
}
