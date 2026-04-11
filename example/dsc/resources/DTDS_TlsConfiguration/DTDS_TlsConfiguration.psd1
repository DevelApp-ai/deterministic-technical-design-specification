@{
    RootModule           = 'DTDS_TlsConfiguration.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'f3b2d9a1-7c4e-4f8a-b2d1-9e6c3a5f0b1d'
    Author               = 'platform-team'
    Description          = 'Class-based DSC resource: manages Windows Schannel TLS/SSL protocol enablement (NIS2 Art.21(2)(h), SEC-006).'
    PowerShellVersion    = '7.2'
    DscResourcesToExport = @('DTDS_TlsConfiguration')
}
