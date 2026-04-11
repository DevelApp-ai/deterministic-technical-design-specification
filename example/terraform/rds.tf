# rds.tf — RDS PostgreSQL database tier (Multi-AZ, encrypted, audited).
#
# Completes the three-tier architecture (network → compute → database).
# Enforces data-at-rest encryption (NIS2-CRYPTO-001), automated backups
# for PITR (DORA Art.12), audit logging via parameter group (DORA Art.10),
# and private-subnet-only placement (SEC-002).
#
# Related ADR:          docs/adrs/0010-nis2-compliance.md
#                       docs/adrs/0011-dora-compliance.md
# Related requirements: NIS2-002, DORA-002, S-001, M-003
# OPA policies:         NIS2-CRYPTO-001, DORA-ICT-001, SEC-002

# ---------------------------------------------------------------------------
# Locals — DB naming, parameter group settings
# ---------------------------------------------------------------------------

locals {
  db_identifier        = "${var.app_name}-${var.environment}-db"
  db_subnet_group_name = "${var.app_name}-${var.environment}-db-subnet"
  db_sg_name           = "${var.app_name}-${var.environment}-db-sg"
  db_param_group_name  = "${var.app_name}-${var.environment}-pg15"
  db_kms_alias         = "alias/${var.app_name}-${var.environment}-cmk"

  # DORA Art.10 / CIS PostgreSQL: connection and statement logging
  db_parameters = [
    { name = "log_connections",    value = "1" },
    { name = "log_disconnections", value = "1" },
    { name = "log_duration",       value = "1" },
    { name = "log_statement",      value = "ddl" },   # log all DDL (CREATE, ALTER, DROP)
    { name = "log_min_duration_statement", value = "1000" }, # ms; slow-query audit
    { name = "rds.force_ssl",      value = "1" },     # encrypt in-transit (NIS2-CRYPTO-001)
    { name = "shared_preload_libraries", value = "pg_stat_statements" },
  ]

  db_backup_retention_days = var.environment == "prod" ? 35 : 7
}

# ---------------------------------------------------------------------------
# DB Subnet Group — private subnets only (SEC-002)
# ---------------------------------------------------------------------------

resource "local_file" "db_subnet_group" {
  filename = "${path.module}/output/rds-subnet-group.json"
  content = jsonencode({
    schema_version   = "1.0"
    resource_type    = "aws_db_subnet_group"
    name             = local.db_subnet_group_name
    description      = "Private subnets for ${var.app_name} RDS (${var.environment})"
    subnet_ids_note  = "References private_subnet_cidrs — no public subnet placement (SEC-002)"
    tags             = merge(local.common_tags, { Tier = "database" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# DB Security Group — allow only from app-tier security group (SEC-004)
# ---------------------------------------------------------------------------

resource "local_file" "db_security_group" {
  filename = "${path.module}/output/rds-security-group.json"
  content = jsonencode({
    schema_version  = "1.0"
    resource_type   = "aws_security_group"
    name            = local.db_sg_name
    description     = "Allow PostgreSQL only from app tier (SEC-004)"
    ingress = [
      {
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        description = "PostgreSQL from app tier security group only — no 0.0.0.0/0 (SEC-004)"
        source      = "app_tier_security_group_id"
      }
    ]
    egress = [
      {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["10.0.0.0/8"]
        description = "RFC-1918 only — deny unrestricted egress (SEC-004)"
      }
    ]
    tags = merge(local.common_tags, { Tier = "database" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# DB Parameter Group — audit logging, SSL enforcement (DORA Art.10, NIS2)
# ---------------------------------------------------------------------------

resource "local_file" "db_parameter_group" {
  filename = "${path.module}/output/rds-parameter-group.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_db_parameter_group"
    name           = local.db_param_group_name
    family         = "postgres15"
    description    = "DORA/NIS2 hardened parameter group for PostgreSQL 15"
    parameters     = local.db_parameters
    tags           = merge(local.common_tags, { Tier = "database" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# RDS Instance — Multi-AZ, encrypted, backups, enhanced monitoring
# ---------------------------------------------------------------------------

resource "local_file" "rds_instance" {
  filename = "${path.module}/output/rds-instance.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_db_instance"

    identifier = local.db_identifier
    engine     = "postgres"
    engine_version = "15.5"

    # Instance sizing — override per environment via variables
    instance_class    = var.environment == "prod" ? "db.t3.large" : "db.t3.micro"
    allocated_storage = var.environment == "prod" ? 100 : 20
    storage_type      = "gp3"
    storage_encrypted = true                 # NIS2-CRYPTO-001: data-at-rest encryption
    kms_key_id        = "aws_kms_key.dtds_cmk.arn"

    # Database credentials — sourced from Secrets Manager, not plaintext
    db_name  = replace(var.app_name, "-", "_")
    username = "${replace(var.app_name, "-", "_")}_admin"
    password = "aws_secretsmanager_random_password"  # populated at runtime

    # Network — private subnets only, no public endpoint (SEC-002)
    db_subnet_group_name   = local.db_subnet_group_name
    vpc_security_group_ids = [local.db_sg_name]
    publicly_accessible    = false           # SEC-002: no public endpoint

    # High availability — Multi-AZ for DORA Art.12 RTO/RPO objectives
    multi_az = var.environment == "prod"

    # Backup and PITR — DORA Art.12 backup prerequisite
    backup_retention_period = local.db_backup_retention_days
    backup_window           = "03:00-04:00"  # UTC, outside business hours
    copy_tags_to_snapshot   = true
    skip_final_snapshot     = var.environment != "prod"
    final_snapshot_identifier = "${local.db_identifier}-final"

    # Maintenance and updates
    maintenance_window          = "sun:05:00-sun:06:00"
    auto_minor_version_upgrade  = true
    deletion_protection         = var.environment == "prod"

    # Parameter and option groups
    parameter_group_name = local.db_param_group_name

    # Enhanced monitoring — CloudWatch metrics every 60 s (DORA Art.10)
    monitoring_interval = 60
    monitoring_role_arn = "aws_iam_role.rds_monitoring.arn"

    # Performance Insights — 7-day free tier; 731 days (2 years) for prod
    performance_insights_enabled          = true
    performance_insights_retention_period = var.environment == "prod" ? 731 : 7

    # CloudWatch log exports — DORA Art.10 log governance
    enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

    tags = merge(local.common_tags, { Tier = "database", FinOps-DataClass = "confidential" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Read replica — disaster recovery / read scale-out (DORA Art.12)
# ---------------------------------------------------------------------------

resource "local_file" "rds_read_replica" {
  filename = "${path.module}/output/rds-read-replica.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_db_instance"
    note           = "Read replica — only created in prod (DORA Art.12 DR)"
    count_condition = "var.environment == 'prod' ? 1 : 0"

    identifier            = "${local.db_identifier}-replica"
    replicate_source_db   = local.db_identifier
    instance_class        = "db.t3.large"
    storage_encrypted     = true
    kms_key_id            = "aws_kms_key.dtds_cmk.arn"
    publicly_accessible   = false
    auto_minor_version_upgrade = true
    performance_insights_enabled = true
    monitoring_interval   = 60
    monitoring_role_arn   = "aws_iam_role.rds_monitoring.arn"

    tags = merge(local.common_tags, { Tier = "database", Role = "read-replica" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CloudWatch alarms — DB health (DORA Art.10 monitoring)
# ---------------------------------------------------------------------------

resource "local_file" "rds_alarms" {
  filename = "${path.module}/output/rds-alarms.json"
  content = jsonencode({
    schema_version = "1.0"
    alarms = [
      {
        alarm_name  = "${local.db_identifier}-cpu-high"
        metric_name = "CPUUtilization"
        namespace   = "AWS/RDS"
        threshold   = 80
        description = "RDS CPU > 80% (DORA Art.10 capacity monitoring)"
      },
      {
        alarm_name  = "${local.db_identifier}-storage-low"
        metric_name = "FreeStorageSpace"
        namespace   = "AWS/RDS"
        threshold   = 10737418240  # 10 GiB in bytes
        comparison  = "LessThanThreshold"
        description = "RDS free storage < 10 GiB (DORA Art.10 capacity monitoring)"
      },
      {
        alarm_name  = "${local.db_identifier}-connections-high"
        metric_name = "DatabaseConnections"
        namespace   = "AWS/RDS"
        threshold   = 100
        description = "RDS connections > 100 (DORA Art.10 availability monitoring)"
      },
      {
        alarm_name  = "${local.db_identifier}-replica-lag"
        metric_name = "ReplicaLag"
        namespace   = "AWS/RDS"
        threshold   = 300  # 5 minutes in seconds
        description = "Read-replica lag > 5 min (DORA Art.12 RPO monitoring)"
      },
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Auto-generated documentation
# ---------------------------------------------------------------------------

resource "local_file" "rds_summary_md" {
  filename = "${path.module}/../docs/generated/rds-summary.md"
  content  = <<-EOF
# RDS Summary

> Auto-generated by `terraform plan` — do not edit manually.

## Database Instance

| Property | Value |
|----------|-------|
| Engine | PostgreSQL 15.5 |
| Identifier | `${local.db_identifier}` |
| Encrypted | ✅ Yes — KMS CMK (`${local.db_kms_alias}`) |
| Multi-AZ | ${var.environment == "prod" ? "✅ Yes (prod)" : "❌ No (non-prod)"} |
| Publicly Accessible | ❌ No (SEC-002) |
| Backup Retention | ${local.db_backup_retention_days} days (DORA Art.12) |
| Parameter Group | `${local.db_param_group_name}` |
| Enhanced Monitoring | ✅ 60-second intervals |

## Security Configuration

| Control | Implementation | Policy |
|---------|---------------|--------|
| Data-at-rest encryption | KMS CMK, `storage_encrypted = true` | NIS2-CRYPTO-001 |
| In-transit encryption | `rds.force_ssl = 1` in parameter group | NIS2-CRYPTO-001 |
| No public endpoint | `publicly_accessible = false` | SEC-002 |
| Ingress restriction | App-tier SG only (port 5432) | SEC-004 |
| Audit logging | `log_connections`, `log_disconnections`, `log_statement = ddl` | DORA Art.10 |
| Automated backups | ${local.db_backup_retention_days}-day retention + PITR | DORA Art.12 |
| CloudWatch log exports | postgresql + upgrade logs | DORA-ICT-001 |

## Compliance Traceability

```mermaid
graph LR
  DORA_012[DORA Art.12 Backup] --> RDS_BACKUP[backup_retention_period = ${local.db_backup_retention_days}]
  DORA_010[DORA Art.10 Audit] --> RDS_LOG[log_connections + log_statement]
  NIS2_CRYPTO[NIS2-CRYPTO-001] --> RDS_ENC[storage_encrypted + rds.force_ssl]
  SEC_002[SEC-002 No Public] --> RDS_NET[publicly_accessible = false]
```
EOF
  file_permission = "0644"
}
