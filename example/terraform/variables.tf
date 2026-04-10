# variables.tf — Input variable definitions for the example web-app module.
# terraform-docs reads these declarations to generate the "Inputs" table in README.md.

variable "environment" {
  type        = string
  description = "Deployment environment (dev | staging | prod)."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "app_name" {
  type        = string
  description = "Name of the application being deployed."
}

variable "owner" {
  type        = string
  description = "Team or individual responsible for this resource (FinOps cost-allocation tag)."
}

variable "cost_center" {
  type        = string
  description = "Financial cost-center code used for FinOps reporting (FinOps cost-allocation tag)."
}

variable "enable_backups" {
  type        = bool
  description = "Whether to enable automated backups for the application data volume."
  default     = true
}

variable "replica_count" {
  type        = number
  description = "Number of application replicas to provision."
  default     = 1

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "replica_count must be between 1 and 10."
  }
}

# ---------------------------------------------------------------------------
# Network variables
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "Primary CIDR block for the virtual network / VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets (no direct internet route; egress via NAT gateway)."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets (internet-gateway attached; hosts load balancers and NAT gateways only)."
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to spread subnets across."
  default     = ["az-1", "az-2"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "When true, provision a NAT gateway in each public subnet so private subnets can reach the internet for egress."
  default     = true
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS resolution and DNS hostnames for the virtual network."
  default     = true
}

variable "dns_zone" {
  type        = string
  description = "Internal DNS zone name used for service discovery records."
  default     = "internal.example.com"
}

# ---------------------------------------------------------------------------
# Compute variables
# ---------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  description = "EC2 instance type for application tier launch template."
  default     = "t3.medium"
}

variable "ami_id" {
  type        = string
  description = "Amazon Machine Image ID for the application tier (pin to a hardened AMI in production)."
  default     = "ami-0123456789abcdef0"
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances in the Auto Scaling group."
  default     = 1

  validation {
    condition     = var.min_size >= 1
    error_message = "min_size must be at least 1."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances in the Auto Scaling group."
  default     = 4

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of instances in the Auto Scaling group at steady state."
  default     = 2

  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size."
  }
}

# ---------------------------------------------------------------------------
# Logging variables
# ---------------------------------------------------------------------------

variable "cloudwatch_retention_days" {
  type        = number
  description = "CloudWatch log group retention in days. Must be > 0 (DORA-ICT-001 requirement)."
  default     = 90

  validation {
    condition     = var.cloudwatch_retention_days > 0
    error_message = "cloudwatch_retention_days must be greater than 0 (DORA-ICT-001)."
  }
}

variable "enable_cloudtrail" {
  type        = bool
  description = "Enable CloudTrail with log file validation (DORA Art.9/10 requirement)."
  default     = true
}
