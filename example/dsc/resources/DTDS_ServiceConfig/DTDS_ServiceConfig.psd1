@{
    RootModule        = 'DTDS_ServiceConfig.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c5f8d4e3-02b1-4a6f-9c7d-3e1f2b4d6a85'
    Author            = 'platform-team'
    Description       = 'DSC resource that manages the state and startup type of a Windows service.'
    PowerShellVersion = '7.2'
    DscResourcesToExport = @('DTDS_ServiceConfig')
    PrivateData = @{
        PSData = @{
            Tags = @('DSC', 'Service', 'Windows', 'Configuration', 'Documentation')
        }
    }
}
