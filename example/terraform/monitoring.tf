# monitoring.tf — Observability resources: alarms, dashboards, log groups.
#
# Demonstrates that observability configuration is also managed as code,
# generating human-readable artefacts for documentation purposes.
# All resources carry the mandatory FinOps cost-allocation tags (FINOPS-001).
#
# Related ADR:          docs/adrs/0001-use-terraform-for-iac.md
# Related requirements: M-001, M-002, OPS-001, OPS-002

# ---------------------------------------------------------------------------
# Locals — alert thresholds (environment-aware)
# ---------------------------------------------------------------------------

locals {
  # Alert thresholds scale with environment to reduce noise in dev
  cpu_threshold_pct = var.environment == "prod" ? 70 : 90
  error_rate_pct    = var.environment == "prod" ? 1 : 5
  latency_p99_ms    = var.environment == "prod" ? 500 : 2000

  # Notification channels per environment
  alert_channels = {
    prod    = ["pagerduty://oncall", "slack://#platform-alerts"]
    staging = ["slack://#platform-staging"]
    dev     = ["slack://#platform-dev"]
  }

  active_alert_channels = lookup(local.alert_channels, var.environment, ["slack://#platform-dev"])

  # Standard alarms applicable to every service
  standard_alarms = [
    {
      name        = "${var.app_name}-${var.environment}-cpu-high"
      metric      = "CPUUtilization"
      namespace   = "AWS/ECS"
      threshold   = local.cpu_threshold_pct
      operator    = "GreaterThanThreshold"
      period      = 300
      eval_periods = 2
      severity    = "WARNING"
      description = "CPU utilization exceeds ${local.cpu_threshold_pct}% for 10 minutes"
      runbook     = "https://docs.example.com/runbooks/high-cpu"
    },
    {
      name        = "${var.app_name}-${var.environment}-error-rate"
      metric      = "5xxErrorRate"
      namespace   = "AWS/ApplicationELB"
      threshold   = local.error_rate_pct
      operator    = "GreaterThanThreshold"
      period      = 60
      eval_periods = 3
      severity    = "CRITICAL"
      description = "HTTP 5xx error rate exceeds ${local.error_rate_pct}% for 3 minutes"
      runbook     = "https://docs.example.com/runbooks/high-error-rate"
    },
    {
      name        = "${var.app_name}-${var.environment}-latency-p99"
      metric      = "TargetResponseTime"
      namespace   = "AWS/ApplicationELB"
      threshold   = local.latency_p99_ms
      operator    = "GreaterThanThreshold"
      period      = 60
      eval_periods = 5
      severity    = "WARNING"
      description = "P99 latency exceeds ${local.latency_p99_ms}ms"
      runbook     = "https://docs.example.com/runbooks/high-latency"
    },
    {
      name        = "${var.app_name}-${var.environment}-disk-usage"
      metric      = "DiskSpaceUtilization"
      namespace   = "System/Linux"
      threshold   = 80
      operator    = "GreaterThanThreshold"
      period      = 300
      eval_periods = 2
      severity    = "WARNING"
      description = "Disk utilization exceeds 80%"
      runbook     = "https://docs.example.com/runbooks/disk-full"
    },
  ]
}

# ---------------------------------------------------------------------------
# CloudWatch alarms manifest
# ---------------------------------------------------------------------------

resource "local_file" "monitoring_alarms" {
  filename = "${path.module}/output/monitoring-alarms.json"
  content = jsonencode({
    schema_version = "1.0"
    app_name       = var.app_name
    environment    = var.environment
    alarms         = local.standard_alarms
    channels       = local.active_alert_channels
    tags           = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CloudWatch log group manifest (30-day / 90-day retention)
# ---------------------------------------------------------------------------

resource "local_file" "monitoring_log_groups" {
  filename = "${path.module}/output/monitoring-log-groups.json"
  content = jsonencode({
    schema_version = "1.0"
    log_groups = [
      {
        name            = "/app/${var.app_name}/${var.environment}/application"
        retention_days  = var.environment == "prod" ? 90 : 30
        encryption_key  = "alias/${var.app_name}-${var.environment}-key"
        tags            = local.common_tags
      },
      {
        name            = "/app/${var.app_name}/${var.environment}/access"
        retention_days  = 365
        encryption_key  = null
        tags            = merge(local.common_tags, { purpose = "access-logs" })
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Operations dashboard manifest
# ---------------------------------------------------------------------------

resource "local_file" "monitoring_dashboard" {
  filename = "${path.module}/output/monitoring-dashboard.json"
  content = jsonencode({
    schema_version = "1.0"
    dashboard_name = "${var.app_name}-ops-${var.environment}"
    widgets = [
      {
        type   = "metric"
        title  = "CPU Utilization"
        metric = "CPUUtilization"
        period = 60
        stat   = "Average"
      },
      {
        type   = "metric"
        title  = "5xx Error Rate"
        metric = "5xxErrorRate"
        period = 60
        stat   = "Average"
      },
      {
        type   = "metric"
        title  = "Latency P99"
        metric = "TargetResponseTime"
        period = 60
        stat   = "p99"
      },
      {
        type   = "alarm_status"
        title  = "Active Alarms"
        alarms = [for a in local.standard_alarms : a.name]
      },
    ]
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Monitoring summary Markdown (rendered into MkDocs "generated" section)
# ---------------------------------------------------------------------------

resource "local_file" "monitoring_summary_md" {
  filename = "${path.module}/../docs/generated/monitoring-summary.md"
  content  = <<-MARKDOWN
    # Monitoring Summary — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/monitoring.tf`

    ## Alarms

    | Alarm | Metric | Threshold | Severity | Runbook |
    |-------|--------|-----------|----------|---------|
    %{for a in local.standard_alarms~}
    | `${a.name}` | `${a.metric}` | ${a.threshold} (${a.operator}) | ${a.severity} | [Link](${a.runbook}) |
    %{endfor~}

    ## Log Groups

    | Log Group | Retention | Encrypted |
    |-----------|-----------|-----------|
    | `/app/${var.app_name}/${var.environment}/application` | ${var.environment == "prod" ? "90" : "30"} days | ✅ KMS |
    | `/app/${var.app_name}/${var.environment}/access` | 365 days | ❌ (cost-opt) |

    ## Alert Channels (${var.environment})

    %{for ch in local.active_alert_channels~}
    - `${ch}`
    %{endfor~}

    ## Related ADRs

    - [ADR-0001 — Terraform for IaC](../adrs/0001-use-terraform-for-iac.md)
    - [Operational Runbook](../runbook/index.md)
  MARKDOWN
  file_permission = "0644"
}
