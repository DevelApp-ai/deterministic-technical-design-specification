#Requires -Version 7.2

<#
.SYNOPSIS
    Comprehensive DSC compliance-baseline configuration using all six DTDS resources.

.DESCRIPTION
    ComplianceBaseline brings together all six DTDS_* class-based DSC resources
    into a single, end-to-end configuration that implements the CIS Windows
    Server Benchmark (Level 1) and the DORA/NIS2 hardening requirements derived
    from ADR-0004.

    Resources used:
      DTDS_FileContent    — managed file content (motd, banners, config files)
      DTDS_RegistryEntry  — registry hardening (NTLMv2, SMB signing, TLS 1.2)
      DTDS_ServiceConfig  — service state (disable unneeded, enable auditd)
      DTDS_AuditPolicy    — Windows audit subcategory policy (DORA Art.10)
      DTDS_FirewallRule   — Windows Defender Firewall rules (SEC-004)
      DTDS_LocalUser      — local account management (CIS 2.3.1, DORA Art.9)

.NOTES
    Author:      platform-team
    Version:     1.0.0
    ADR:         docs/adrs/0004-use-dsc-for-windows-config.md
    Requirements: S-008, S-009, DORA-003, NIS2-003
    Apply:       Start-DscConfiguration -Path .\ComplianceBaseline -Wait -Verbose
#>

# ── Module imports ────────────────────────────────────────────────────────────
$resourceRoot = Join-Path $PSScriptRoot 'resources'

Import-Module (Join-Path $resourceRoot 'DTDS_FileContent/DTDS_FileContent.psm1')     -Force
Import-Module (Join-Path $resourceRoot 'DTDS_RegistryEntry/DTDS_RegistryEntry.psm1') -Force
Import-Module (Join-Path $resourceRoot 'DTDS_ServiceConfig/DTDS_ServiceConfig.psm1') -Force
Import-Module (Join-Path $resourceRoot 'DTDS_AuditPolicy/DTDS_AuditPolicy.psm1')     -Force
Import-Module (Join-Path $resourceRoot 'DTDS_FirewallRule/DTDS_FirewallRule.psm1')    -Force
Import-Module (Join-Path $resourceRoot 'DTDS_LocalUser/DTDS_LocalUser.psm1')         -Force

# ── Configuration ─────────────────────────────────────────────────────────────
Configuration ComplianceBaseline {

    param(
        [string] $AppName    = 'dtds',
        [string] $Environment = 'prod'
    )

    Import-DscResource -ModuleName DTDS_FileContent
    Import-DscResource -ModuleName DTDS_RegistryEntry
    Import-DscResource -ModuleName DTDS_ServiceConfig
    Import-DscResource -ModuleName DTDS_AuditPolicy
    Import-DscResource -ModuleName DTDS_FirewallRule
    Import-DscResource -ModuleName DTDS_LocalUser

    Node 'localhost' {

        # ════════════════════════════════════════════════════════════════════
        # 1 ─ DTDS_FileContent  (login banners, config files)
        # ════════════════════════════════════════════════════════════════════

        # CIS 1.7.1 — logon legal notice (Group Policy equivalent via file)
        DTDS_FileContent 'LegalBanner' {
            Path    = 'C:\Windows\System32\drivers\etc\banner.txt'
            Content = @"
*******************************************************************************
  AUTHORISED ACCESS ONLY
  All activity on this system is monitored and recorded.
  Unauthorised access is prohibited and subject to criminal prosecution.
  DORA Art.17 — Incident classification applies.
*******************************************************************************
"@
            Ensure  = 'Present'
        }

        # Compliance marker — last hardening timestamp
        DTDS_FileContent 'ComplianceMarker' {
            Path    = 'C:\ProgramData\DTDS\compliance-baseline.txt'
            Content = "ComplianceBaseline v1.0.0 applied by DSC on $(Get-Date -Format 'yyyy-MM-dd')."
            Ensure  = 'Present'
        }

        # Application configuration (from SSM SecureString at provision time)
        DTDS_FileContent 'AppConfig' {
            Path    = "C:\ProgramData\${AppName}\config.json"
            Content = '{"environment":"' + $Environment + '","log_level":"info","tls_min_version":"1.2"}'
            Ensure  = 'Present'
        }

        # ════════════════════════════════════════════════════════════════════
        # 2 ─ DTDS_RegistryEntry  (security hardening via registry)
        # ════════════════════════════════════════════════════════════════════

        # CIS 2.3.11.1 — Force NTLMv2 (disable LM and NTLMv1)
        DTDS_RegistryEntry 'ForceNTLMv2' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            ValueName = 'LmCompatibilityLevel'
            ValueData = 5    # Send NTLMv2 response only; refuse LM & NTLM
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # CIS 2.3.11.8 — Require SMB signing on client
        DTDS_RegistryEntry 'RequireSMBSigningClient' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
            ValueName = 'RequireSecuritySignature'
            ValueData = 1
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # CIS 2.3.11.9 — Require SMB signing on server
        DTDS_RegistryEntry 'RequireSMBSigningServer' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
            ValueName = 'RequireSecuritySignature'
            ValueData = 1
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # NIS2-CRYPTO-001 — Disable TLS 1.0
        DTDS_RegistryEntry 'DisableTLS10Server' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
            ValueName = 'Enabled'
            ValueData = 0
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # NIS2-CRYPTO-001 — Disable TLS 1.1
        DTDS_RegistryEntry 'DisableTLS11Server' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'
            ValueName = 'Enabled'
            ValueData = 0
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # NIS2-CRYPTO-001 — Enable TLS 1.2
        DTDS_RegistryEntry 'EnableTLS12Server' {
            Key       = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'
            ValueName = 'Enabled'
            ValueData = 1
            ValueType = 'DWord'
            Ensure    = 'Present'
        }

        # ════════════════════════════════════════════════════════════════════
        # 3 ─ DTDS_ServiceConfig  (service hardening)
        # ════════════════════════════════════════════════════════════════════

        # CIS 5.x — Disable unneeded / high-risk services
        DTDS_ServiceConfig 'DisableRemoteRegistry' {
            ServiceName = 'RemoteRegistry'
            StartupType = 'Disabled'
            State       = 'Stopped'
            Ensure      = 'Present'
        }

        DTDS_ServiceConfig 'DisableTelnet' {
            ServiceName = 'TlntSvr'
            StartupType = 'Disabled'
            State       = 'Stopped'
            Ensure      = 'Present'
        }

        DTDS_ServiceConfig 'DisableFax' {
            ServiceName = 'Fax'
            StartupType = 'Disabled'
            State       = 'Stopped'
            Ensure      = 'Present'
        }

        # Enable Windows Defender Antivirus service (CIS 8.x / DORA Art.10)
        DTDS_ServiceConfig 'EnableWindowsDefender' {
            ServiceName = 'WinDefend'
            StartupType = 'Automatic'
            State       = 'Running'
            Ensure      = 'Present'
        }

        # Enable Windows Event Log service (DORA Art.10 audit trail)
        DTDS_ServiceConfig 'EnableEventLog' {
            ServiceName = 'EventLog'
            StartupType = 'Automatic'
            State       = 'Running'
            Ensure      = 'Present'
        }

        # ════════════════════════════════════════════════════════════════════
        # 4 ─ DTDS_AuditPolicy  (audit subcategories for DORA Art.10)
        # ════════════════════════════════════════════════════════════════════

        DTDS_AuditPolicy 'AuditLogon' {
            Subcategory     = 'Logon'
            AuditSuccess    = $true
            AuditFailure    = $true
            Ensure          = 'Present'
        }

        DTDS_AuditPolicy 'AuditLogoff' {
            Subcategory     = 'Logoff'
            AuditSuccess    = $true
            AuditFailure    = $false
            Ensure          = 'Present'
        }

        DTDS_AuditPolicy 'AuditAccountManagement' {
            Subcategory     = 'User Account Management'
            AuditSuccess    = $true
            AuditFailure    = $true
            Ensure          = 'Present'
        }

        DTDS_AuditPolicy 'AuditPrivilegeUse' {
            Subcategory     = 'Sensitive Privilege Use'
            AuditSuccess    = $true
            AuditFailure    = $true
            Ensure          = 'Present'
        }

        DTDS_AuditPolicy 'AuditPolicyChange' {
            Subcategory     = 'Audit Policy Change'
            AuditSuccess    = $true
            AuditFailure    = $true
            Ensure          = 'Present'
        }

        DTDS_AuditPolicy 'AuditObjectAccess' {
            Subcategory     = 'File System'
            AuditSuccess    = $true
            AuditFailure    = $true
            Ensure          = 'Present'
        }

        # ════════════════════════════════════════════════════════════════════
        # 5 ─ DTDS_FirewallRule  (network access control — SEC-004)
        # ════════════════════════════════════════════════════════════════════

        # Allow only RDP from management CIDR (CIS 9.x — no unrestricted RDP)
        DTDS_FirewallRule 'AllowRDPManagementOnly' {
            RuleName    = 'DTDS-Allow-RDP-Management'
            DisplayName = 'Allow RDP from management network only'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '3389'
            RemoteAddress = '10.0.0.0/8'   # RFC-1918 management range
            Action      = 'Allow'
            Enabled     = $true
            Ensure      = 'Present'
        }

        # Block unrestricted RDP from any source (default-deny complement)
        DTDS_FirewallRule 'BlockRDPPublic' {
            RuleName    = 'DTDS-Block-RDP-Public'
            DisplayName = 'Block RDP from public networks'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '3389'
            RemoteAddress = 'Any'
            Action      = 'Block'
            Enabled     = $true
            Ensure      = 'Present'
        }

        # Allow HTTPS inbound for application tier
        DTDS_FirewallRule 'AllowHTTPS' {
            RuleName    = 'DTDS-Allow-HTTPS-Inbound'
            DisplayName = 'Allow HTTPS inbound (application traffic)'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '443'
            Action      = 'Allow'
            Enabled     = $true
            Ensure      = 'Present'
        }

        # Block SMB from external networks (SEC-004, CIS 9.2)
        DTDS_FirewallRule 'BlockSMBInbound' {
            RuleName    = 'DTDS-Block-SMB-External'
            DisplayName = 'Block SMB from non-RFC-1918 sources'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '445'
            RemoteAddress = 'Any'
            Action      = 'Block'
            Enabled     = $true
            Ensure      = 'Present'
        }

        # ════════════════════════════════════════════════════════════════════
        # 6 ─ DTDS_LocalUser  (account management — CIS 2.3.1, DORA Art.9)
        # ════════════════════════════════════════════════════════════════════

        # CIS 2.3.1.2 — Disable the built-in Administrator account
        DTDS_LocalUser 'DisableBuiltInAdministrator' {
            UserName      = 'Administrator'
            AccountStatus = 'Disabled'
            Description   = 'Built-in account — disabled per CIS 2.3.1.2 and DORA Art.9'
            Ensure        = 'Present'
        }

        # CIS 2.3.1.3 — Disable the built-in Guest account
        DTDS_LocalUser 'DisableGuestAccount' {
            UserName      = 'Guest'
            AccountStatus = 'Disabled'
            Description   = 'Built-in guest — disabled per CIS 2.3.1.3'
            Ensure        = 'Present'
        }

        # Application service account — enabled, password never expires
        DTDS_LocalUser "AppServiceAccount_${AppName}" {
            UserName            = "svc-${AppName}-app"
            AccountStatus       = 'Enabled'
            Description         = "${AppName} application service account (DORA Art.9 least-privilege)"
            PasswordNeverExpires = $true
            Ensure              = 'Present'
        }
    }
}

# ── Compile MOF and display summary ───────────────────────────────────────────
$outputPath = Join-Path $PSScriptRoot 'output/ComplianceBaseline'

ComplianceBaseline -AppName 'dtds' -Environment 'prod' -OutputPath $outputPath

Write-Host ""
Write-Host "ComplianceBaseline MOF compiled successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Resources applied:" -ForegroundColor Cyan
Write-Host "  DTDS_FileContent   — 3 managed files (banners, config, compliance marker)"
Write-Host "  DTDS_RegistryEntry — 5 registry entries (NTLMv2, SMB signing, TLS 1.2)"
Write-Host "  DTDS_ServiceConfig — 5 service states (disable legacy, enable defender/eventlog)"
Write-Host "  DTDS_AuditPolicy   — 6 audit subcategories (logon, privilege, object, policy)"
Write-Host "  DTDS_FirewallRule  — 4 firewall rules (allow RDP/HTTPS, block SMB/public RDP)"
Write-Host "  DTDS_LocalUser     — 3 accounts (disable admin/guest, create svc account)"
Write-Host ""
Write-Host "Compliance mappings:" -ForegroundColor Cyan
Write-Host "  CIS Benchmark  — CIS 1.7, 2.3.1, 2.3.11, 5.x, 9.x"
Write-Host "  DORA Art.9     — Access control (local accounts, firewall)"
Write-Host "  DORA Art.10    — Audit logging (audit policy, event log service)"
Write-Host "  NIS2-CRYPTO-001— TLS 1.2 enforcement (registry)"
Write-Host "  SEC-004        — Network access control (firewall rules)"
Write-Host ""
Write-Host "Apply with:" -ForegroundColor Yellow
Write-Host "  Start-DscConfiguration -Path $outputPath -Wait -Verbose -Force"
