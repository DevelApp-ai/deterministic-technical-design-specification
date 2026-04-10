# compute.tf — EC2 Auto Scaling group and launch template.
#
# Demonstrates security-hardened compute resources as code:
# - IMDSv2 (hop limit = 1, token required)
# - Encrypted EBS root volume using the application CMK
# - No public IP address assignment on instances
# - User-data bootstrap that installs the monitoring agent and DSC prerequisites
# - Auto Scaling with lifecycle hooks for graceful drain
#
# Related ADR:          docs/adrs/0001-use-terraform-for-iac.md
# Related requirements: M-001, M-003, S-001, CYB-002, CYB-004
# OPA policies:         SEC-001 (encryption), SEC-002 (no public IP)

# ---------------------------------------------------------------------------
# Variables — compute-specific (declared in variables.tf)
# ---------------------------------------------------------------------------
# instance_type, min_size, max_size, desired_capacity, ami_id

# ---------------------------------------------------------------------------
# Locals — derived compute settings
# ---------------------------------------------------------------------------

locals {
  asg_name              = "${var.app_name}-asg-${var.environment}"
  launch_template_name  = "${var.app_name}-lt-${var.environment}"
  instance_profile_name = "${var.app_name}-instance-profile-${var.environment}"

  # User-data script (base64 in a real provider; plain text for the manifest)
  user_data_script = <<-USERDATA
    #!/usr/bin/env bash
    # Bootstrap script — managed by Terraform (do not edit manually)
    set -euo pipefail

    # Install monitoring agent
    curl -sSL https://dl.monitoring.example.com/agent/install.sh | bash
    systemctl enable --now monitoring-agent

    # Install PowerShell (for DSC on Linux)
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS

    # Harden OS baseline (invokes Ansible via SSH from CI after launch)
    echo "instance_ready=true" > /var/lib/cloud/instance/ready
  USERDATA
}

# ---------------------------------------------------------------------------
# Launch Template — hardened, IMDSv2 mandatory, encrypted EBS
# ---------------------------------------------------------------------------

resource "local_file" "launch_template" {
  filename = "${path.module}/output/launch-template.json"
  content = jsonencode({
    schema_version       = "1.0"
    resource_type        = "aws_launch_template"
    name                 = local.launch_template_name
    description          = "Hardened launch template for ${var.app_name} (${var.environment})"
    instance_type        = var.instance_type
    image_id             = var.ami_id
    iam_instance_profile = { name = local.instance_profile_name }

    # IMDSv2 — tokens required, hop limit prevents SSRF container escape
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"   # IMDSv2
      http_put_response_hop_limit = 1
      instance_metadata_tags      = "enabled"
    }

    # Block devices — encrypted root volume, no instance store
    block_device_mappings = [
      {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 30
          volume_type           = "gp3"
          encrypted             = true   # SEC-001
          kms_key_id            = local.kms_key_alias
          delete_on_termination = true
        }
      }
    ]

    # No public IP — instances must use NAT gateway for egress
    network_interfaces = [
      {
        associate_public_ip_address = false   # SEC-002
        security_groups             = ["${var.app_name}-sg-app-${var.environment}"]
        delete_on_termination       = true
      }
    ]

    tag_specifications = [
      {
        resource_type = "instance"
        tags          = merge(local.common_tags, { Role = "app" })
      },
      {
        resource_type = "volume"
        tags          = merge(local.common_tags, { Role = "app-root" })
      }
    ]

    user_data = base64encode(local.user_data_script)
    tags      = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------

resource "local_file" "auto_scaling_group" {
  filename = "${path.module}/output/auto-scaling-group.json"
  content = jsonencode({
    schema_version    = "1.0"
    resource_type     = "aws_autoscaling_group"
    name              = local.asg_name
    launch_template   = { name = local.launch_template_name, version = "$Latest" }
    min_size          = var.min_size
    max_size          = var.max_size
    desired_capacity  = var.desired_capacity
    vpc_zone_identifier = var.private_subnet_cidrs   # private subnets only
    health_check_type = "ELB"
    health_check_grace_period = 300

    # Lifecycle hook — waits for instance to be ready before marking InService
    initial_lifecycle_hook = {
      name                    = "${local.asg_name}-launch-hook"
      lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
      heartbeat_timeout       = 300
      default_result          = "ABANDON"
      notification_metadata   = jsonencode({ app = var.app_name, env = var.environment })
    }

    # Scaling policies
    scaling_policies = [
      {
        name                   = "${local.asg_name}-cpu-scale-out"
        policy_type            = "TargetTrackingScaling"
        estimated_instance_warmup = 120
        target_tracking_configuration = {
          predefined_metric_type = "ASGAverageCPUUtilization"
          target_value           = 60.0
        }
      }
    ]

    tags = [
      for k, v in merge(local.common_tags, { AsgGroup = local.asg_name }) :
      { key = k, value = v, propagate_at_launch = true }
    ]
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Security Group — application tier
# ---------------------------------------------------------------------------

resource "local_file" "security_group_app" {
  filename = "${path.module}/output/security-group-app.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_security_group"
    name           = "${var.app_name}-sg-app-${var.environment}"
    description    = "Application tier security group — deny direct internet access"
    ingress_rules = [
      {
        description = "HTTPS from load balancer only"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        source      = "sg-loadbalancer-ref"   # reference to LB security group
      },
      {
        description = "Application port from load balancer"
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        source      = "sg-loadbalancer-ref"
      }
    ]
    egress_rules = [
      {
        description = "HTTPS to internet (package manager, external APIs)"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        destination = "0.0.0.0/0"
      },
      {
        description = "PostgreSQL to database tier"
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        destination = "sg-database-ref"
      }
    ]
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Compute summary Markdown (auto-generated for docs)
# ---------------------------------------------------------------------------

resource "local_file" "compute_summary_md" {
  filename = "${path.module}/../docs/generated/compute-summary.md"
  content  = <<-MARKDOWN
    # Compute — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/compute.tf`

    ## Launch Template

    | Property | Value |
    |----------|-------|
    | **Name** | `${local.launch_template_name}` |
    | **Instance Type** | `${var.instance_type}` |
    | **IMDSv2** | ✅ Tokens required (hop limit: 1) |
    | **EBS Encryption** | ✅ CMK `${local.kms_key_alias}` |
    | **Public IP** | ❌ Disabled (private subnets only) |

    ## Auto Scaling Group

    | Property | Value |
    |----------|-------|
    | **Name** | `${local.asg_name}` |
    | **Min / Desired / Max** | `${var.min_size}` / `${var.desired_capacity}` / `${var.max_size}` |
    | **Subnets** | Private only |
    | **Health Check** | ELB |
    | **Scale-Out Target** | 60% CPU (TargetTracking) |

    ## Security Controls

    | Control | Policy | Status |
    |---------|--------|--------|
    | EBS root volume encrypted | SEC-001 | ✅ `gp3` + CMK |
    | No public IP on instances | SEC-002 | ✅ Disabled |
    | IMDSv2 only | CYB-002 | ✅ `http_tokens = required` |
    | Least-privilege egress | SEC-004 | ✅ HTTPS + DB port only |
  MARKDOWN
  file_permission = "0644"
}
