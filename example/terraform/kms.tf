# kms.tf — KMS key management, SSM Parameter Store, and Secrets Manager.
#
# Demonstrates encryption-as-code: KMS keys with automatic rotation, SSM
# SecureString parameters, and Secrets Manager entries — all carrying FinOps
# tags and satisfying NIS2-CRYPTO-001 (key rotation, SecureString).
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
#                       docs/adrs/0010-nis2-compliance.md
# Related requirements: NIS2-002, M-003, S-001
# OPA policies:         NIS2-CRYPTO-001 (deny_nis2_crypto.rego)

# ---------------------------------------------------------------------------
# Locals — key aliases and secret names
# ---------------------------------------------------------------------------

locals {
  kms_key_alias     = "alias/${var.app_name}-${var.environment}-cmk"
  app_secret_name   = "${var.app_name}/${var.environment}/app-credentials"
  db_secret_name    = "${var.app_name}/${var.environment}/db-credentials"

  # SSM parameter paths — hierarchical, per-environment
  ssm_config_path       = "/${var.app_name}/${var.environment}/config"
  ssm_secret_path       = "/${var.app_name}/${var.environment}/secrets"

  # KMS key policy document (least-privilege)
  kms_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::ACCOUNT_ID:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowAppDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::ACCOUNT_ID:role/${var.app_name}-app-role-${var.environment}"
        }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      },
      {
        Sid    = "AllowCIKeyUse"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::ACCOUNT_ID:role/${var.app_name}-cicd-role"
        }
        Action   = ["kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# KMS Customer-Managed Key with automatic rotation (NIS2-CRYPTO-001)
# ---------------------------------------------------------------------------

resource "local_file" "kms_key" {
  filename = "${path.module}/output/kms-key.json"
  content = jsonencode({
    schema_version           = "1.0"
    resource_type            = "aws_kms_key"
    description              = "CMK for ${var.app_name} (${var.environment}) — auto-rotation enabled"
    alias                    = local.kms_key_alias
    enable_key_rotation      = true          # NIS2-CRYPTO-001 requirement
    deletion_window_in_days  = 30
    multi_region             = false
    key_usage                = "ENCRYPT_DECRYPT"
    customer_master_key_spec = "SYMMETRIC_DEFAULT"
    policy                   = local.kms_key_policy
    tags                     = merge(local.common_tags, { Purpose = "encryption" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# SSM Parameter Store — configuration (String) and secrets (SecureString)
# ---------------------------------------------------------------------------

resource "local_file" "ssm_parameters" {
  filename = "${path.module}/output/ssm-parameters.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_ssm_parameter"
    parameters = [
      # Non-secret configuration — String type
      {
        name        = "${local.ssm_config_path}/log_level"
        type        = "String"
        value       = "INFO"
        description = "Application log verbosity level"
        tier        = "Standard"
        tags        = local.common_tags
      },
      {
        name        = "${local.ssm_config_path}/replica_count"
        type        = "String"
        value       = tostring(var.replica_count)
        description = "Number of application replicas"
        tier        = "Standard"
        tags        = local.common_tags
      },
      # Secret configuration — SecureString type (NIS2-CRYPTO-001 requirement)
      {
        name        = "${local.ssm_secret_path}/api_key"
        type        = "SecureString"
        value       = "PLACEHOLDER_ROTATED_AT_DEPLOY_TIME"
        description = "Application API key (SecureString — encrypted by CMK)"
        key_id      = local.kms_key_alias
        tier        = "Standard"
        tags        = local.common_tags
      },
      {
        name        = "${local.ssm_secret_path}/jwt_signing_key"
        type        = "SecureString"
        value       = "PLACEHOLDER_ROTATED_AT_DEPLOY_TIME"
        description = "JWT signing key (SecureString — encrypted by CMK)"
        key_id      = local.kms_key_alias
        tier        = "Standard"
        tags        = local.common_tags
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Secrets Manager — structured application secrets with auto-rotation
# ---------------------------------------------------------------------------

resource "local_file" "secrets_manager" {
  filename = "${path.module}/output/secrets-manager.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_secretsmanager_secret"
    secrets = [
      {
        name                    = local.app_secret_name
        description             = "Application credentials for ${var.app_name} (${var.environment})"
        kms_key_id              = local.kms_key_alias
        recovery_window_in_days = 7
        rotation_enabled        = true
        rotation_rules = {
          automatically_after_days = 30
        }
        secret_string_template = jsonencode({
          username = "${var.app_name}-app"
          password = "ROTATED_AUTOMATICALLY"
          endpoint = "https://api.${var.dns_zone}"
        })
        tags = merge(local.common_tags, { SecretType = "app-credentials" })
      },
      {
        name                    = local.db_secret_name
        description             = "Database credentials for ${var.app_name} (${var.environment})"
        kms_key_id              = local.kms_key_alias
        recovery_window_in_days = 7
        rotation_enabled        = true
        rotation_rules = {
          automatically_after_days = 30
        }
        secret_string_template = jsonencode({
          username = "${var.app_name}_app"
          password = "ROTATED_AUTOMATICALLY"
          engine   = "postgres"
          host     = "db.${var.dns_zone}"
          port     = 5432
          dbname   = var.app_name
        })
        tags = merge(local.common_tags, { SecretType = "db-credentials" })
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# KMS key usage Markdown summary (auto-generated for docs)
# ---------------------------------------------------------------------------

resource "local_file" "kms_summary_md" {
  filename = "${path.module}/../docs/generated/kms-summary.md"
  content  = <<-MARKDOWN
    # KMS Key Management — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/kms.tf`

    ## Customer-Managed Key (CMK)

    | Property | Value |
    |----------|-------|
    | **Alias** | `${local.kms_key_alias}` |
    | **Key Rotation** | ✅ Enabled (NIS2-CRYPTO-001) |
    | **Deletion Window** | 30 days |
    | **Usage** | ENCRYPT_DECRYPT |

    ## SSM Parameters

    | Path | Type | Purpose |
    |------|------|---------|
    | `${local.ssm_config_path}/log_level` | String | Application log level |
    | `${local.ssm_config_path}/replica_count` | String | Replica count |
    | `${local.ssm_secret_path}/api_key` | **SecureString** | API key (CMK-encrypted) |
    | `${local.ssm_secret_path}/jwt_signing_key` | **SecureString** | JWT signing key (CMK-encrypted) |

    ## Secrets Manager

    | Secret Name | Rotation | KMS Key |
    |-------------|----------|---------|
    | `${local.app_secret_name}` | Every 30 days | `${local.kms_key_alias}` |
    | `${local.db_secret_name}` | Every 30 days | `${local.kms_key_alias}` |

    ## Compliance

    | Control | Framework | Status |
    |---------|-----------|--------|
    | KMS key rotation enabled | NIS2-CRYPTO-001, Art.21(2)(h) | ✅ Automated |
    | All secrets as SecureString | NIS2-CRYPTO-001 | ✅ Automated |
    | CMK for Secrets Manager | NIS2-CRYPTO-001, DORA Art.9 | ✅ Automated |
  MARKDOWN
  file_permission = "0644"
}
