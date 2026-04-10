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
