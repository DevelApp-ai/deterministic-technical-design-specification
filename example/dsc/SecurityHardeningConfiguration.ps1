# dsc/SecurityHardeningConfiguration.ps1
#
# DORA/NIS2 security hardening DSC configuration using the DTDS_AuditPolicy
# and DTDS_FirewallRule resources.
#
# This configuration implements the Windows-specific hardening controls
# required by:
#   - DORA (EU 2022/2554) Art.9/10 — ICT Risk / Audit logging
#   - NIS2 (EU 2022/2555) Art.21(2) — Security measures
#   - CIS Benchmark Level 1 — Section 17 (Audit Policy) + 9 (Windows Firewall)
#
# Usage — compile only (cross-platform):
#   pwsh -File SecurityHardeningConfiguration.ps1
#
# Usage — apply on Windows (requires LCM):
#   pwsh -File SecurityHardeningConfiguration.ps1
#   Start-DscConfiguration -Path ./SecurityHardening -Wait -Verbose -Force
#
# Related ADR:          docs/adrs/0004-use-dsc-for-windows-config.md
#                       docs/adrs/0011-dora-compliance.md
# Related requirements: DORA-001, DORA-002, NIS2-004, CYB-004, S-008

using module './resources/DTDS_AuditPolicy/DTDS_AuditPolicy.psm1'
using module './resources/DTDS_FirewallRule/DTDS_FirewallRule.psm1'
using module './resources/DTDS_FileContent/DTDS_FileContent.psm1'

[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path $PSScriptRoot '../docs/generated/dsc-output/security')
)

Configuration SecurityHardening {

    Import-DscResource -ModuleName DTDS_AuditPolicy
    Import-DscResource -ModuleName DTDS_FirewallRule
    Import-DscResource -ModuleName DTDS_FileContent

    Node 'localhost' {

        # ==================================================================
        # DTDS_AuditPolicy — Windows Security Audit Policy
        # CIS Benchmark Section 17 / DORA Art.10 / NIS2 Art.21(2)(b)
        # ==================================================================

        # Logon events — Success AND Failure (CIS 17.5.1, DORA Art.10)
        DTDS_AuditPolicy AuditLogon {
            Subcategory = 'Logon'
            AuditFlag   = [AuditTracking]::SuccessAndFailure
        }

        # Account Lockout — Failure (CIS 17.5.2)
        DTDS_AuditPolicy AuditAccountLockout {
            Subcategory = 'Account Lockout'
            AuditFlag   = [AuditTracking]::Failure
        }

        # Process Creation — Success (CIS 17.2.1 — detects malware execution)
        DTDS_AuditPolicy AuditProcessCreation {
            Subcategory = 'Process Creation'
            AuditFlag   = [AuditTracking]::Success
        }

        # Privilege Use — Failure (CIS 17.8.1)
        DTDS_AuditPolicy AuditPrivilegeUse {
            Subcategory = 'Sensitive Privilege Use'
            AuditFlag   = [AuditTracking]::Failure
        }

        # Policy Change — Success AND Failure (CIS 17.7.1 — detect policy tampering)
        DTDS_AuditPolicy AuditPolicyChange {
            Subcategory = 'Audit Policy Change'
            AuditFlag   = [AuditTracking]::SuccessAndFailure
        }

        # System Integrity — Success AND Failure (DORA Art.10 — integrity events)
        DTDS_AuditPolicy AuditSystemIntegrity {
            Subcategory = 'Security System Extension'
            AuditFlag   = [AuditTracking]::SuccessAndFailure
        }

        # ==================================================================
        # DTDS_FirewallRule — Windows Defender Firewall
        # CIS Benchmark Section 9 / DORA Art.9 / SEC-004
        # ==================================================================

        # Block RDP from internet — only allow from management VLAN
        DTDS_FirewallRule BlockRdpInbound {
            RuleName    = 'DTDS-Block-RDP-External'
            Direction   = [FirewallDirection]::Inbound
            Protocol    = 'TCP'
            LocalPort   = '3389'
            Action      = [FirewallAction]::Block
            Ensure      = [FirewallEnsure]::Present
            Description = 'Block RDP from internet — CYB-004, DORA Art.9'
        }

        # Block Telnet — legacy protocol, should not be used
        DTDS_FirewallRule BlockTelnetInbound {
            RuleName    = 'DTDS-Block-Telnet-Inbound'
            Direction   = [FirewallDirection]::Inbound
            Protocol    = 'TCP'
            LocalPort   = '23'
            Action      = [FirewallAction]::Block
            Ensure      = [FirewallEnsure]::Present
            Description = 'Block Telnet — CIS 9.1.1, unencrypted protocol'
        }

        # Block FTP — legacy unencrypted protocol
        DTDS_FirewallRule BlockFtpInbound {
            RuleName    = 'DTDS-Block-FTP-Inbound'
            Direction   = [FirewallDirection]::Inbound
            Protocol    = 'TCP'
            LocalPort   = '21'
            Action      = [FirewallAction]::Block
            Ensure      = [FirewallEnsure]::Present
            Description = 'Block FTP — CIS 9.1.1, use SFTP instead'
        }

        # Allow HTTPS inbound — application traffic
        DTDS_FirewallRule AllowHttpsInbound {
            RuleName    = 'DTDS-Allow-HTTPS-Inbound'
            Direction   = [FirewallDirection]::Inbound
            Protocol    = 'TCP'
            LocalPort   = '443'
            Action      = [FirewallAction]::Allow
            Ensure      = [FirewallEnsure]::Present
            Description = 'Allow HTTPS application traffic'
        }

        # Allow HTTPS outbound — required for updates and APIs
        DTDS_FirewallRule AllowHttpsOutbound {
            RuleName    = 'DTDS-Allow-HTTPS-Outbound'
            Direction   = [FirewallDirection]::Outbound
            Protocol    = 'TCP'
            LocalPort   = '443'
            Action      = [FirewallAction]::Allow
            Ensure      = [FirewallEnsure]::Present
            Description = 'Allow HTTPS outbound — package managers, external APIs'
        }

        # Block SMB externally — prevent ransomware lateral movement
        DTDS_FirewallRule BlockSmbInbound {
            RuleName    = 'DTDS-Block-SMB-External'
            Direction   = [FirewallDirection]::Inbound
            Protocol    = 'TCP'
            LocalPort   = '445'
            Action      = [FirewallAction]::Block
            Ensure      = [FirewallEnsure]::Present
            Description = 'Block SMB from external — prevent ransomware lateral movement'
        }

        # ==================================================================
        # DTDS_FileContent — Security policy documentation markers
        # ==================================================================

        # Compliance marker — records when hardening was applied
        DTDS_FileContent HardeningAppliedMarker {
            Path    = 'C:\ProgramData\DTDS\security-hardening-applied.txt'
            Content = "hardened=true`ncis_level=1`ndora_art9=compliant`nexpiration=none"
            Ensure  = 'Present'
        }

        # Audit policy documentation
        DTDS_FileContent AuditPolicyReadme {
            Path    = 'C:\ProgramData\DTDS\audit-policy-README.txt'
            Content = @"
Windows Security Audit Policy — managed by DSC DTDS_AuditPolicy resource.
Do not modify manually.

Configured subcategories:
  Logon                    = Success AND Failure  (CIS 17.5.1, DORA Art.10)
  Account Lockout          = Failure              (CIS 17.5.2)
  Process Creation         = Success              (CIS 17.2.1)
  Sensitive Privilege Use  = Failure              (CIS 17.8.1)
  Audit Policy Change      = Success AND Failure  (CIS 17.7.1)
  Security System Extension= Success AND Failure  (DORA Art.10)

Related ADR: docs/adrs/0011-dora-compliance.md
"@
            Ensure  = 'Present'
        }
    }
}

# Compile the configuration into a MOF document.
$null = New-Item -ItemType Directory -Path $OutputDir -Force
SecurityHardening -OutputPath $OutputDir
Write-Host "Security Hardening MOF compiled to: $OutputDir/localhost.mof" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host "Configuration includes:" -ForegroundColor Cyan
Write-Host "  6 x DTDS_AuditPolicy  (CIS Section 17, DORA Art.10)" -ForegroundColor Cyan
Write-Host "  6 x DTDS_FirewallRule (CIS Section 9, DORA Art.9, SEC-004)" -ForegroundColor Cyan
Write-Host "  2 x DTDS_FileContent  (compliance markers)" -ForegroundColor Cyan
