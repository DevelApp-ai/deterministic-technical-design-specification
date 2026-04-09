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
