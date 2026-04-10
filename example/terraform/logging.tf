# logging.tf — CloudTrail, CloudWatch log groups, and S3 access logging.
#
# Directly satisfies DORA-ICT-001 requirements:
#   1. CloudTrail with enable_log_file_validation = true  (Art.9/10 log integrity)
#   2. CloudWatch log groups with non-zero retention_in_days (Art.10/15 lifecycle)
#   3. S3 bucket versioning enabled for audit-log backup (Art.12)
#
# Related ADR:          docs/adrs/0011-dora-compliance.md
# Related requirements: DORA-002, DORA-003, NIS2-004, OPS-001, OPS-002
# OPA policies:         DORA-ICT-001 (deny_dora_ict_risk.rego)

# ---------------------------------------------------------------------------
# Variables — logging-specific (declared in variables.tf)
# ---------------------------------------------------------------------------
# cloudwatch_retention_days, enable_cloudtrail

# ---------------------------------------------------------------------------
# Locals — derived log group names and trail settings
# ---------------------------------------------------------------------------

locals {
  cloudtrail_name           = "${var.app_name}-audit-trail-${var.environment}"
  cloudtrail_s3_bucket      = "${var.app_name}-cloudtrail-${var.environment}"
  cloudtrail_log_group_name = "/aws/cloudtrail/${var.app_name}/${var.environment}"
  app_log_group_name        = "/aws/${var.app_name}/${var.environment}/application"
  access_log_group_name     = "/aws/${var.app_name}/${var.environment}/access"
  security_log_group_name   = "/aws/${var.app_name}/${var.environment}/security"

  # S3 versioning config satisfies DORA Art.12 (backup of audit logs)
  s3_versioning_config = {
    status = "Enabled"   # DORA-ICT-001 S3 versioning rule
  }

  # Log retention by environment — never zero (DORA-ICT-001 retention rule)
  effective_retention_days = max(var.cloudwatch_retention_days, 1)
}

# ---------------------------------------------------------------------------
# CloudTrail — org-wide audit trail with log file validation
# ---------------------------------------------------------------------------

resource "local_file" "cloudtrail" {
  filename = "${path.module}/output/cloudtrail.json"
  content = jsonencode({
    schema_version              = "1.0"
    resource_type               = "aws_cloudtrail"
    name                        = local.cloudtrail_name
    s3_bucket_name              = local.cloudtrail_s3_bucket
    include_global_service_events = true
    is_multi_region_trail       = var.environment == "prod" ? true : false
    enable_log_file_validation  = true   # DORA-ICT-001 — mandatory
    enable_logging              = true
    cloud_watch_logs_group_arn  = "arn:aws:logs:REGION:ACCOUNT:log-group:${local.cloudtrail_log_group_name}"
    cloud_watch_logs_role_arn   = "arn:aws:iam::ACCOUNT:role/${var.app_name}-cloudtrail-role"
    kms_key_id                  = local.kms_key_alias
    event_selectors = [
      {
        read_write_type           = "All"
        include_management_events = true
        data_resources = [
          {
            type   = "AWS::S3::Object"
            values = ["arn:aws:s3:::${local.primary_bucket_name}/"]
          }
        ]
      }
    ]
    insight_selectors = [
      { insight_type = "ApiCallRateInsight" },
      { insight_type = "ApiErrorRateInsight" }
    ]
    tags = merge(local.common_tags, { Purpose = "audit-logging", DORA = "Art.9-10" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CloudTrail S3 bucket — versioning enabled (DORA Art.12 backup prerequisite)
# ---------------------------------------------------------------------------

resource "local_file" "cloudtrail_s3_bucket" {
  filename = "${path.module}/output/cloudtrail-s3-bucket.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_s3_bucket"
    bucket         = local.cloudtrail_s3_bucket
    force_destroy  = var.environment != "prod"

    # Versioning — DORA-ICT-001 requirement
    versioning = local.s3_versioning_config

    # Server-side encryption using CMK
    server_side_encryption_configuration = {
      rule = {
        apply_server_side_encryption_by_default = {
          sse_algorithm     = "aws:kms"
          kms_master_key_id = local.kms_key_alias
        }
        bucket_key_enabled = true
      }
    }

    # Block all public access
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true

    # Lifecycle — transition to cheaper storage after 90 days, retain 7 years
    lifecycle_rules = [
      {
        id     = "cloudtrail-lifecycle"
        status = "Enabled"
        transitions = [
          { days = 90, storage_class = "STANDARD_IA" },
          { days = 365, storage_class = "GLACIER" }
        ]
        expiration = { days = 2555 }   # 7 years (365 * 7) — DORA Art.15 retention
      }
    ]
    tags = merge(local.common_tags, { Purpose = "audit-log-backup", DORA = "Art.12" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups — non-zero retention (DORA-ICT-001)
# ---------------------------------------------------------------------------

resource "local_file" "cloudwatch_log_groups" {
  filename = "${path.module}/output/cloudwatch-log-groups.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_cloudwatch_log_group"
    log_groups = [
      {
        name              = local.cloudtrail_log_group_name
        retention_in_days = local.effective_retention_days   # DORA-ICT-001 — must be > 0
        kms_key_id        = local.kms_key_alias
        tags              = merge(local.common_tags, { Purpose = "cloudtrail-delivery" })
      },
      {
        name              = local.app_log_group_name
        retention_in_days = local.effective_retention_days
        kms_key_id        = local.kms_key_alias
        tags              = merge(local.common_tags, { Purpose = "application-logs" })
      },
      {
        name              = local.access_log_group_name
        retention_in_days = local.effective_retention_days
        kms_key_id        = local.kms_key_alias
        tags              = merge(local.common_tags, { Purpose = "access-logs" })
      },
      {
        name              = local.security_log_group_name
        retention_in_days = local.effective_retention_days
        kms_key_id        = local.kms_key_alias
        tags              = merge(local.common_tags, { Purpose = "security-events" })
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CloudWatch Metric Alarms — DORA incident detection
# ---------------------------------------------------------------------------

resource "local_file" "security_alarms" {
  filename = "${path.module}/output/security-alarms.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_cloudwatch_metric_alarm"
    alarms = [
      {
        alarm_name          = "${var.app_name}-${var.environment}-root-login"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 1
        metric_name         = "RootAccountUsage"
        namespace           = "CISBenchmark"
        period              = 300
        statistic           = "Sum"
        threshold           = 1
        alarm_description   = "Alert: root account activity detected (CIS 3.3)"
        alarm_actions       = local.active_alert_channels
        tags                = merge(local.common_tags, { Severity = "CRITICAL" })
      },
      {
        alarm_name          = "${var.app_name}-${var.environment}-unauthorized-api"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 1
        metric_name         = "UnauthorizedAPICalls"
        namespace           = "CISBenchmark"
        period              = 300
        statistic           = "Sum"
        threshold           = 1
        alarm_description   = "Alert: unauthorized API calls detected (DORA Art.17)"
        alarm_actions       = local.active_alert_channels
        tags                = merge(local.common_tags, { Severity = "HIGH", DORA = "Art.17" })
      },
      {
        alarm_name          = "${var.app_name}-${var.environment}-console-no-mfa"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 1
        metric_name         = "ConsoleSignInWithoutMFA"
        namespace           = "CISBenchmark"
        period              = 300
        statistic           = "Sum"
        threshold           = 1
        alarm_description   = "Alert: console login without MFA (CIS 3.2)"
        alarm_actions       = local.active_alert_channels
        tags                = merge(local.common_tags, { Severity = "HIGH" })
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Logging summary Markdown (auto-generated for docs)
# ---------------------------------------------------------------------------

resource "local_file" "logging_summary_md" {
  filename = "${path.module}/../docs/generated/logging-summary.md"
  content  = <<-MARKDOWN
    # Logging & Audit Trail — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/logging.tf`

    ## CloudTrail

    | Property | Value |
    |----------|-------|
    | **Trail Name** | `${local.cloudtrail_name}` |
    | **Log File Validation** | ✅ Enabled (DORA-ICT-001) |
    | **Multi-Region** | ${var.environment == "prod" ? "✅ Yes" : "❌ No (prod only)"} |
    | **KMS Encryption** | ✅ `${local.kms_key_alias}` |
    | **Insight Selectors** | ApiCallRate + ApiErrorRate |

    ## CloudWatch Log Groups

    | Log Group | Retention | Purpose |
    |-----------|-----------|---------|
    | `${local.cloudtrail_log_group_name}` | ${local.effective_retention_days} days ✅ | CloudTrail delivery |
    | `${local.app_log_group_name}` | ${local.effective_retention_days} days ✅ | Application logs |
    | `${local.access_log_group_name}` | ${local.effective_retention_days} days ✅ | HTTP access logs |
    | `${local.security_log_group_name}` | ${local.effective_retention_days} days ✅ | Security events |

    ## DORA Compliance

    | DORA Article | Control | Status |
    |-------------|---------|--------|
    | Art.9/10 — Log integrity | CloudTrail log file validation | ✅ Automated |
    | Art.10/15 — Log lifecycle | CloudWatch retention > 0 days | ✅ Automated |
    | Art.12 — Backup | S3 versioning on audit-log bucket | ✅ Automated |
    | Art.15 — Retention | S3 lifecycle: 7-year expiry | ✅ Automated |
    | Art.17 — Incident detection | CloudWatch alarms (root, unauthorized, no-MFA) | ✅ Automated |
  MARKDOWN
  file_permission = "0644"
}
