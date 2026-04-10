@{
    RootModule           = 'DTDS_AuditPolicy.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a2f3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d'
    Author               = 'platform-team'
    Description          = 'DSC resource for managing Windows Security Audit Policy subcategories (DORA Art.10, NIS2 Art.21).'
    PowerShellVersion    = '7.2'
    DscResourcesToExport = @('DTDS_AuditPolicy')
}
