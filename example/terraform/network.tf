# network.tf — Network topology module using the `local` provider.
#
# Defines a complete virtual network topology (VPC, subnets, routing, NSGs)
# as Terraform code so that:
#   1. terraform-docs auto-generates the network input/output reference.
#   2. OPA policies (SEC-002, SEC-004) evaluate the plan JSON for violations.
#   3. MkDocs renders the network chapter from the generated artefacts.
#
# The `local_file` resources write human-readable JSON/YAML manifests that
# represent what would be created in a real cloud provider (AWS VPC, Azure VNet,
# etc.) — identical toolchain behaviour without requiring credentials.

# ---------------------------------------------------------------------------
# Locals — derived network values
# ---------------------------------------------------------------------------

locals {
  # Map subnets to their roles and availability zones for the manifest
  private_subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    "private-${idx + 1}" => {
      cidr              = cidr
      role              = "private"
      availability_zone = "az-${(idx % length(var.availability_zones)) + 1}"
      nat_gateway       = var.enable_nat_gateway
    }
  }

  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs :
    "public-${idx + 1}" => {
      cidr              = cidr
      role              = "public"
      availability_zone = "az-${(idx % length(var.availability_zones)) + 1}"
      internet_gateway  = true
    }
  }

  all_subnets = merge(local.private_subnet_map, local.public_subnet_map)

  # Default network security group rules (restrictive baseline)
  default_inbound_rules = [
    {
      rule_id     = "ALLOW-HTTPS-INBOUND"
      direction   = "inbound"
      priority    = 100
      protocol    = "tcp"
      port_range  = "443"
      source      = "0.0.0.0/0"
      destination = "VirtualNetwork"
      action      = "Allow"
      description = "Allow HTTPS from internet to load balancer tier"
    },
    {
      rule_id     = "ALLOW-HTTP-INBOUND"
      direction   = "inbound"
      priority    = 110
      protocol    = "tcp"
      port_range  = "80"
      source      = "0.0.0.0/0"
      destination = "VirtualNetwork"
      action      = "Allow"
      description = "Allow HTTP (redirect to HTTPS) from internet"
    },
    {
      rule_id     = "DENY-ALL-INBOUND"
      direction   = "inbound"
      priority    = 4096
      protocol    = "*"
      port_range  = "*"
      source      = "0.0.0.0/0"
      destination = "VirtualNetwork"
      action      = "Deny"
      description = "Default deny — all inbound traffic not matched above"
    },
  ]

  default_outbound_rules = [
    {
      rule_id     = "ALLOW-HTTPS-OUTBOUND"
      direction   = "outbound"
      priority    = 100
      protocol    = "tcp"
      port_range  = "443"
      source      = "VirtualNetwork"
      destination = "0.0.0.0/0"
      action      = "Allow"
      description = "Allow HTTPS egress (package managers, external APIs)"
    },
    {
      rule_id     = "DENY-ALL-OUTBOUND"
      direction   = "outbound"
      priority    = 4096
      protocol    = "*"
      port_range  = "*"
      source      = "VirtualNetwork"
      destination = "0.0.0.0/0"
      action      = "Deny"
      description = "Default deny — all outbound traffic not matched above"
    },
  ]
}

# ---------------------------------------------------------------------------
# Network topology manifest
# ---------------------------------------------------------------------------

resource "local_file" "network_topology" {
  filename = "${path.module}/output/network-topology.json"
  content = jsonencode({
    schema_version = "1.0"
    name           = "${var.app_name}-network"
    environment    = var.environment
    vpc_cidr       = var.vpc_cidr
    dns_support    = var.enable_dns_support
    nat_gateway    = var.enable_nat_gateway
    subnets        = local.all_subnets
    tags           = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Network security group (NSG / firewall rules) manifest
# ---------------------------------------------------------------------------

resource "local_file" "network_security_rules" {
  filename = "${path.module}/output/network-security-rules.json"
  content = jsonencode({
    schema_version = "1.0"
    nsg_name       = "${var.app_name}-nsg-${var.environment}"
    environment    = var.environment
    inbound_rules  = local.default_inbound_rules
    outbound_rules = local.default_outbound_rules
    tags           = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# DNS records manifest
# ---------------------------------------------------------------------------

resource "local_file" "dns_records" {
  filename = "${path.module}/output/dns-records.json"
  content = jsonencode({
    schema_version = "1.0"
    zone           = var.dns_zone
    environment    = var.environment
    records = [
      {
        name    = var.app_name
        type    = "CNAME"
        ttl     = 300
        value   = "lb.${var.dns_zone}"
        comment = "Application load balancer endpoint"
      },
      {
        name    = "api.${var.app_name}"
        type    = "CNAME"
        ttl     = 300
        value   = "lb.${var.dns_zone}"
        comment = "API endpoint (same LB, routed by host header)"
      },
    ]
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Network topology Markdown summary (rendered into MkDocs "generated" section)
# ---------------------------------------------------------------------------

resource "local_file" "network_summary_md" {
  filename = "${path.module}/../docs/generated/network-topology.md"
  content  = <<-MARKDOWN
    # Network Topology — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/network.tf`

    ## VPC / Virtual Network

    | Property | Value |
    |----------|-------|
    | **Name** | `${var.app_name}-network` |
    | **CIDR** | `${var.vpc_cidr}` |
    | **DNS Support** | `${var.enable_dns_support}` |
    | **NAT Gateway** | `${var.enable_nat_gateway}` |
    | **DNS Zone** | `${var.dns_zone}` |
    | **Environment** | `${var.environment}` |

    ## Subnets

    | Name | CIDR | Role | Availability Zone |
    |------|------|------|------------------|
    %{for name, s in local.all_subnets~}
    | `${name}` | `${s.cidr}` | ${s.role} | ${s.availability_zone} |
    %{endfor~}

    ## Network Security Rules

    ### Inbound

    | Priority | Rule ID | Protocol | Port | Source | Action |
    |----------|---------|----------|------|--------|--------|
    %{for rule in local.default_inbound_rules~}
    | ${rule.priority} | `${rule.rule_id}` | ${rule.protocol} | ${rule.port_range} | ${rule.source} | **${rule.action}** |
    %{endfor~}

    ### Outbound

    | Priority | Rule ID | Protocol | Port | Destination | Action |
    |----------|---------|----------|------|-------------|--------|
    %{for rule in local.default_outbound_rules~}
    | ${rule.priority} | `${rule.rule_id}` | ${rule.protocol} | ${rule.port_range} | ${rule.destination} | **${rule.action}** |
    %{endfor~}

    ## Related Policies

    - [SEC-002 — Deny Publicly Exposed Resources](../compliance/opa-policies.md#sec-002--deny-publicly-exposed-resources)
    - [SEC-004 — Deny Unrestricted Network Egress](../compliance/opa-policies.md#sec-004--deny-unrestricted-network-egress)
  MARKDOWN
  file_permission = "0644"
}
