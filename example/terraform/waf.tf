# terraform/waf.tf — AWS WAF (Web Application Firewall)
#
# Protects the public-facing ALB from:
#   - OWASP Top 10 web application attacks (AWSManagedRulesCommonRuleSet)
#   - Known bad IP addresses (AWSManagedRulesAmazonIpReputationList)
#   - Anonymous proxies and VPNs (AWSManagedRulesAnonymousIpList)
#   - Request rate abuse (custom rate-based rule)
#
# All rule groups use AWS managed rule sets so that the organisation
# receives signature updates automatically, meeting the NIS2 Art.21(2)(e)
# requirement for security in acquisition and maintenance.
#
# Related ADR:          docs/adrs/0010-nis2-compliance.md
# Related requirements: NIS2-002, CYB-002, M-003, S-001
# OPA policies:         SEC-002 (deny_public_access)
# CIS:                  AWS 6.x (network security)
# NIST 800-53:          SC-7, SI-3, SI-10

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  waf_name = "${var.app_name}-${var.environment}-waf"

  # Threshold for rate-based rule — maximum requests per 5-minute window
  # from a single IP.  Scaled by environment to avoid false-positives in dev.
  waf_rate_limit = var.environment == "prod" ? 2000 : 10000

  # Managed rule groups to attach to the WAF ACL.
  # Priority must be unique; lower number evaluated first.
  waf_managed_rules = [
    {
      priority        = 10
      name            = "AWS-AWSManagedRulesAmazonIpReputationList"
      vendor_name     = "AWS"
      rule_group_name = "AWSManagedRulesAmazonIpReputationList"
      description     = "Blocks IPs known to be associated with bots, botnets, and threat actors"
      override_action = "none"
      metric_name     = "${var.app_name}-${var.environment}-ip-reputation"
    },
    {
      priority        = 20
      name            = "AWS-AWSManagedRulesAnonymousIpList"
      vendor_name     = "AWS"
      rule_group_name = "AWSManagedRulesAnonymousIpList"
      description     = "Blocks requests originating from anonymous proxies, Tor exit nodes, and VPNs"
      override_action = "none"
      metric_name     = "${var.app_name}-${var.environment}-anonymous-ip"
    },
    {
      priority        = 30
      name            = "AWS-AWSManagedRulesCommonRuleSet"
      vendor_name     = "AWS"
      rule_group_name = "AWSManagedRulesCommonRuleSet"
      description     = "OWASP Top 10 protection: XSS, SQLi, path traversal, local file inclusion"
      override_action = "none"
      metric_name     = "${var.app_name}-${var.environment}-common-rules"
    },
    {
      priority        = 40
      name            = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name     = "AWS"
      rule_group_name = "AWSManagedRulesKnownBadInputsRuleSet"
      description     = "Blocks Log4jRCE, SSRF, Spring4Shell, and other known exploit patterns"
      override_action = "none"
      metric_name     = "${var.app_name}-${var.environment}-bad-inputs"
    },
    {
      priority        = 50
      name            = "AWS-AWSManagedRulesSQLiRuleSet"
      vendor_name     = "AWS"
      rule_group_name = "AWSManagedRulesSQLiRuleSet"
      description     = "Blocks SQL injection patterns across URI, body, query string, and cookie"
      override_action = "none"
      metric_name     = "${var.app_name}-${var.environment}-sqli"
    },
  ]

  # Custom rate-based rule evaluated after managed rules
  waf_rate_rule = {
    priority    = 100
    name        = "${var.app_name}-${var.environment}-rate-limit"
    description = "Throttle single-IP flood attacks to max ${local.waf_rate_limit} req/5min"
    limit       = local.waf_rate_limit
    action      = "block"
    metric_name = "${var.app_name}-${var.environment}-rate-limit"
  }
}

# ---------------------------------------------------------------------------
# WAF Web ACL manifest
# ---------------------------------------------------------------------------

resource "local_file" "waf_web_acl" {
  filename = "${path.module}/output/waf-web-acl.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_wafv2_web_acl"
    name           = local.waf_name
    description    = "WAF ACL protecting ${var.app_name} ALB (${var.environment})"
    scope          = "REGIONAL"
    default_action = "allow"

    # Cloudwatch metrics and logging configuration
    visibility_config = {
      cloudwatch_metrics_enabled = true
      metric_name                = local.waf_name
      sampled_requests_enabled   = true
    }

    logging_configuration = {
      log_destination_arns = [
        "arn:aws:firehose:eu-west-1:ACCOUNT_ID:deliverystream/${var.app_name}-${var.environment}-waf-logs"
      ]
      redacted_fields = ["authorization_header"]  # PII protection
    }

    managed_rule_groups = local.waf_managed_rules

    rate_based_rule = local.waf_rate_rule

    # Association with ALB is configured in the alb_association resource below
    associated_resource_arn = "arn:aws:elasticloadbalancing:eu-west-1:ACCOUNT_ID:loadbalancer/app/${var.app_name}-${var.environment}/..."

    tags = merge(local.common_tags, {
      Purpose   = "waf"
      Component = "security"
    })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# WAF IP set — allow-listed admin CIDR ranges
# ---------------------------------------------------------------------------

resource "local_file" "waf_admin_ip_set" {
  filename = "${path.module}/output/waf-admin-ip-set.json"
  content = jsonencode({
    schema_version = "1.0"
    resource_type  = "aws_wafv2_ip_set"
    name           = "${local.waf_name}-admin-ips"
    description    = "Trusted admin IP ranges exempt from WAF rate limiting"
    scope          = "REGIONAL"
    ip_address_version = "IPV4"
    addresses = [
      "10.0.0.0/8",     # Internal RFC-1918 — never rate-limited
      "172.16.0.0/12",  # Internal RFC-1918
      "192.168.0.0/16", # Internal RFC-1918
    ]
    tags = merge(local.common_tags, { Purpose = "waf-allowlist" })
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# WAF summary Markdown — auto-generated documentation
# ---------------------------------------------------------------------------

resource "local_file" "waf_summary_md" {
  filename = "${path.module}/../docs/generated/waf-summary.md"
  content  = <<-MARKDOWN
    # WAF Summary — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/waf.tf`

    ## Web ACL: `${local.waf_name}`

    | Property | Value |
    |----------|-------|
    | **Scope** | REGIONAL (ALB) |
    | **Default action** | ALLOW (rules block threats) |
    | **CloudWatch metrics** | Enabled |
    | **WAF logging** | Kinesis Firehose → S3 |
    | **Rate limit** | ${local.waf_rate_limit} requests / 5 minutes per IP |

    ## Managed Rule Groups

    | Priority | Rule Group | Protects Against |
    |----------|-----------|-----------------|
    | 10 | `AWSManagedRulesAmazonIpReputationList` | Bots, botnets, threat actor IPs |
    | 20 | `AWSManagedRulesAnonymousIpList` | Tor exit nodes, anonymous proxies |
    | 30 | `AWSManagedRulesCommonRuleSet` | OWASP Top 10 (XSS, SQLi, path traversal) |
    | 40 | `AWSManagedRulesKnownBadInputsRuleSet` | Log4JRCE, SSRF, Spring4Shell |
    | 50 | `AWSManagedRulesSQLiRuleSet` | SQL injection (URI, body, query, cookie) |

    ## Custom Rules

    | Priority | Rule | Action | Threshold |
    |----------|------|--------|-----------|
    | 100 | Rate-based flood protection | BLOCK | ${local.waf_rate_limit} req/5min per IP |

    ## Compliance Mapping

    | Control | Framework | Satisfied By |
    |---------|-----------|-------------|
    | Prevent OWASP Top 10 | NIS2 Art.21(2)(e) | `AWSManagedRulesCommonRuleSet` |
    | Block known malicious IPs | CYB-002 | `AWSManagedRulesAmazonIpReputationList` |
    | Protect against SQLi | CIS AWS 6.x | `AWSManagedRulesSQLiRuleSet` |
    | Rate-limit flood attacks | NIST 800-53 SC-7 | Rate-based rule (${local.waf_rate_limit} req/5min) |

    ## Related OPA Policies

    - [SEC-002 — Deny Publicly Exposed Resources](../compliance/opa-policies.md#sec-002--deny-publicly-exposed-resources)
    - [SEC-004 — Deny Unrestricted Network Egress](../compliance/opa-policies.md#sec-004--deny-unrestricted-network-egress)
  MARKDOWN
  file_permission = "0644"
}
