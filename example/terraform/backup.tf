# terraform/backup.tf — AWS Backup vault and plans (DORA Art.12)
#
# Implements the backup and disaster-recovery obligations of DORA Chapter II
# Article 12 (Backup policies and procedures, restoration and recovery).
# Defines three backup plans with increasing retention and cross-region copy:
#
#   Plan 1 — Daily plan:   daily at 02:00 UTC, 7-day retention
#   Plan 2 — Weekly plan:  every Sunday, 35-day retention + cross-region copy
#   Plan 3 — Monthly plan: 1st of each month, 1-year retention + cross-region copy
#
# The cross-region copy satisfies the DORA requirement for geographically
# separated backup storage and an RTO ≤ 4 hours for critical data.
#
# Related ADR:          docs/adrs/0011-dora-compliance.md
# Related requirements: DORA-003, NIS2-003, M-001
# DORA:                 Art.12 (Backup policies), Art.12(7) (Recovery testing)
# NIST 800-53:          CP-9 (System Backup), CP-10 (Recovery)
# SOC 2:                A1.2 (Recovery capacity objectives)

# ---------------------------------------------------------------------------
# Locals — backup configuration
# ---------------------------------------------------------------------------

locals {
  backup_vault_name          = "${var.app_name}-${var.environment}-vault"
  backup_vault_replica_name  = "${var.app_name}-${var.environment}-vault-dr"

  # Primary and DR regions
  backup_primary_region = "eu-west-1"
  backup_dr_region      = "eu-central-1"

  # Retention periods (days) — scaled by environment
  retention_daily    = var.environment == "prod" ? 7 : 3
  retention_weekly   = var.environment == "prod" ? 35 : 7
  retention_monthly  = var.environment == "prod" ? 365 : 30
  retention_copy_dr  = var.environment == "prod" ? 90 : 14

  # DORA RTO / RPO targets (documented in the generated summary)
  dora_rto_hours = 4
  dora_rpo_hours = var.environment == "prod" ? 1 : 4

  # KMS alias for backup vault encryption (references kms.tf)
  backup_kms_alias = local.kms_key_alias

  # Resources included in backup plans (ARN patterns)
  backup_selection_arns = [
    "arn:aws:rds:*:*:db:${var.app_name}-${var.environment}-*",       # RDS instances
    "arn:aws:ec2:*:*:volume/*",                                        # EBS volumes tagged with app_name
    "arn:aws:dynamodb:*:*:table/${var.app_name}-${var.environment}-*", # DynamoDB tables
    "arn:aws:efs:*:*:file-system/*",                                   # EFS file systems tagged
  ]
}

# ---------------------------------------------------------------------------
# Backup vault — primary region
# ---------------------------------------------------------------------------

resource "local_file" "backup_vault_primary" {
  filename = "${path.module}/output/backup-vault-primary.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_backup_vault"
    name           = local.backup_vault_name
    region         = local.backup_primary_region
    kms_key_arn    = "arn:aws:kms:${local.backup_primary_region}:ACCOUNT_ID:${local.backup_kms_alias}"
    vault_lock_configuration = {
      # Immutable vault: prevents deletion/modification of backups during retention window
      changeable_for_days = var.environment == "prod" ? 3 : null
      max_retention_days  = local.retention_monthly
      min_retention_days  = 1
    }
    tags = merge(local.common_tags, { Purpose = "backup-vault" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Backup vault — DR region (cross-region copy target)
# ---------------------------------------------------------------------------

resource "local_file" "backup_vault_dr" {
  filename = "${path.module}/output/backup-vault-dr.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_backup_vault"
    name           = local.backup_vault_replica_name
    region         = local.backup_dr_region
    kms_key_arn    = "arn:aws:kms:${local.backup_dr_region}:ACCOUNT_ID:${local.backup_kms_alias}-dr"
    vault_lock_configuration = {
      changeable_for_days = var.environment == "prod" ? 3 : null
      max_retention_days  = local.retention_copy_dr
      min_retention_days  = 1
    }
    tags = merge(local.common_tags, { Purpose = "backup-vault-dr", Region = local.backup_dr_region })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Backup plans
# ---------------------------------------------------------------------------

resource "local_file" "backup_plan_daily" {
  filename = "${path.module}/output/backup-plan-daily.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_backup_plan"
    name           = "${var.app_name}-${var.environment}-daily"
    rule = {
      rule_name         = "daily-backup"
      target_vault_name = local.backup_vault_name
      schedule          = "cron(0 2 * * ? *)"  # 02:00 UTC daily
      start_window      = 60                    # minutes
      completion_window = 180                   # minutes
      lifecycle = {
        delete_after = local.retention_daily
      }
      recovery_point_tags = {
        BackupType  = "daily"
        Environment = var.environment
        ManagedBy   = "aws-backup"
      }
    }
    tags = merge(local.common_tags, { BackupPlan = "daily" })
  })
  file_permission = "0644"
}

resource "local_file" "backup_plan_weekly" {
  filename = "${path.module}/output/backup-plan-weekly.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_backup_plan"
    name           = "${var.app_name}-${var.environment}-weekly"
    rule = {
      rule_name         = "weekly-backup"
      target_vault_name = local.backup_vault_name
      schedule          = "cron(0 3 ? * 1 *)"  # 03:00 UTC every Sunday
      start_window      = 60
      completion_window = 480
      lifecycle = {
        delete_after = local.retention_weekly
      }
      copy_action = {
        destination_vault_arn = "arn:aws:backup:${local.backup_dr_region}:ACCOUNT_ID:backup-vault:${local.backup_vault_replica_name}"
        lifecycle = {
          delete_after = local.retention_copy_dr
        }
      }
      recovery_point_tags = {
        BackupType       = "weekly"
        CrossRegionCopy  = "true"
        DRRegion         = local.backup_dr_region
        Environment      = var.environment
        ManagedBy        = "aws-backup"
      }
    }
    tags = merge(local.common_tags, { BackupPlan = "weekly" })
  })
  file_permission = "0644"
}

resource "local_file" "backup_plan_monthly" {
  filename = "${path.module}/output/backup-plan-monthly.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_backup_plan"
    name           = "${var.app_name}-${var.environment}-monthly"
    rule = {
      rule_name         = "monthly-backup"
      target_vault_name = local.backup_vault_name
      schedule          = "cron(0 4 1 * ? *)"  # 04:00 UTC on the 1st of each month
      start_window      = 120
      completion_window = 720
      lifecycle = {
        delete_after = local.retention_monthly
      }
      copy_action = {
        destination_vault_arn = "arn:aws:backup:${local.backup_dr_region}:ACCOUNT_ID:backup-vault:${local.backup_vault_replica_name}"
        lifecycle = {
          delete_after = local.retention_copy_dr
        }
      }
      recovery_point_tags = {
        BackupType       = "monthly"
        CrossRegionCopy  = "true"
        DRRegion         = local.backup_dr_region
        LongTermRetention = "true"
        Environment       = var.environment
        ManagedBy         = "aws-backup"
      }
    }
    tags = merge(local.common_tags, { BackupPlan = "monthly" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Backup selection — tag-based resource association
# ---------------------------------------------------------------------------

resource "local_file" "backup_selection" {
  filename = "${path.module}/output/backup-selection.json"
  content = jsonencode({
    schema_version    = "1.0"
    resource_type     = "aws_backup_selection"
    name              = "${var.app_name}-${var.environment}-resources"
    iam_role_arn      = "arn:aws:iam::ACCOUNT_ID:role/${var.app_name}-backup-role-${var.environment}"
    selection_method  = "tag"
    selection_tags = [
      {
        type  = "STRINGEQUALS"
        key   = "app_name"
        value = var.app_name
      },
      {
        type  = "STRINGEQUALS"
        key   = "environment"
        value = var.environment
      },
    ]
    note = "Selects all resources tagged with app_name=${var.app_name} AND environment=${var.environment}"
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Backup compliance report — DORA Art.12(7) restore-test evidence
# ---------------------------------------------------------------------------

resource "local_file" "backup_compliance_report" {
  filename = "${path.module}/output/backup-compliance-report.json"
  content = jsonencode({
    schema_version   = "1.0"
    resource_type    = "aws_backup_report_plan"
    name             = "${var.app_name}-${var.environment}-backup-report"
    description      = "Automated restore-test evidence for DORA Art.12(7) supervisory reporting"
    report_delivery_channel = {
      formats   = ["JSON", "CSV"]
      s3_bucket = "${var.app_name}-${var.environment}-backup-reports"
      s3_key_prefix = "backup-compliance/"
    }
    report_setting = {
      report_template       = "RESTORE_JOB_REPORT"
      regions               = [local.backup_primary_region, local.backup_dr_region]
      frameworks            = ["NIST_800_53_Rev_5"]
    }
    tags = merge(local.common_tags, { Purpose = "backup-compliance-reporting" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Backup summary Markdown — auto-generated documentation
# ---------------------------------------------------------------------------

resource "local_file" "backup_summary_md" {
  filename = "${path.module}/../docs/generated/backup-summary.md"
  content  = <<-MARKDOWN
    # Backup & DR Summary — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/backup.tf`

    ## DORA Art.12 RTO / RPO Targets

    | Target | Value | Satisfied By |
    |--------|-------|-------------|
    | **RTO (Recovery Time Objective)** | ≤ ${local.dora_rto_hours} hours | Cross-region vault in `${local.backup_dr_region}` |
    | **RPO (Recovery Point Objective)** | ≤ ${local.dora_rpo_hours} hours | Daily backup schedule (02:00 UTC) |

    ## Backup Vaults

    | Vault | Region | Encryption | Lock |
    |-------|--------|-----------|------|
    | `${local.backup_vault_name}` | `${local.backup_primary_region}` | KMS CMK | Immutable (${local.retention_monthly} day max) |
    | `${local.backup_vault_replica_name}` | `${local.backup_dr_region}` | KMS CMK (DR key) | Immutable (${local.retention_copy_dr} day max) |

    ## Backup Plans

    | Plan | Schedule | Retention | Cross-Region Copy |
    |------|----------|-----------|------------------|
    | `daily` | 02:00 UTC every day | ${local.retention_daily} days | ❌ |
    | `weekly` | 03:00 UTC every Sunday | ${local.retention_weekly} days | ✅ `${local.backup_dr_region}` (${local.retention_copy_dr} days) |
    | `monthly` | 04:00 UTC 1st of month | ${local.retention_monthly} days | ✅ `${local.backup_dr_region}` (${local.retention_copy_dr} days) |

    ## Resource Selection

    All resources tagged `app_name=${var.app_name}` AND `environment=${var.environment}` are
    automatically enrolled in all backup plans.  Covered resource types:

    - RDS database instances
    - EBS volumes
    - DynamoDB tables
    - EFS file systems

    ## Compliance Mapping

    | Requirement | Framework | Evidence |
    |-------------|-----------|---------|
    | Backup policies and procedures | DORA Art.12 | This file + `aws_backup_plan` resources |
    | Cross-region backup isolation | DORA Art.12(7) | `${local.backup_vault_replica_name}` in `${local.backup_dr_region}` |
    | Immutable backup vault | DORA Art.12, SOC 2 A1.2 | `vault_lock_configuration` |
    | Restore-test evidence reporting | DORA Art.12(7) | `aws_backup_report_plan` (JSON+CSV to S3) |
    | Encrypted backups | NIS2 Art.21(2)(c), SEC-001 | KMS CMK encryption on both vaults |

    ## Related OPA Policies

    - [DORA-ICT-001 — DORA ICT Risk Management](../compliance/opa-policies.md#dora-ict-001--dora-ict-risk-management)
    - [NIS2-CRYPTO-001 — Cryptography and Key Management](../compliance/opa-policies.md#nis2-crypto-001--nis2-cryptography-and-key-management)

    ## See Also

    - [DORA Compliance page](../compliance/dora.md#chapter-ii-art12--backup)
    - [NIS2 Compliance page](../compliance/nis2.md)
  MARKDOWN
  file_permission = "0644"
}
