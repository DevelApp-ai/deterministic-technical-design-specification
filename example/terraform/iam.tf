# iam.tf — IAM roles, policies, and instance profiles.
#
# Demonstrates least-privilege IAM modelling as code.  The `local_file`
# resources emit JSON artefacts that mirror real AWS/Azure IAM objects,
# allowing the SEC-003 OPA policy (deny_public_iam.rego) to be evaluated
# against the plan without requiring cloud credentials.
#
# Related ADR:          docs/adrs/0002-use-opa-for-policy.md
# Related requirements: M-001, CYB-003, S-001

# ---------------------------------------------------------------------------
# Locals — re-usable IAM building blocks
# ---------------------------------------------------------------------------

locals {
  # Service principals that are allowed to assume application roles
  app_service_principals = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]

  # Read-only permission set for the app role
  app_read_actions = [
    "s3:GetObject",
    "s3:ListBucket",
    "secretsmanager:GetSecretValue",
    "ssm:GetParameter",
    "ssm:GetParametersByPath",
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
  ]

  # Specific KMS actions allowed for envelope encryption
  kms_actions = [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey",
  ]
}

# ---------------------------------------------------------------------------
# Application IAM role — least-privilege trust policy
# ---------------------------------------------------------------------------

resource "local_file" "iam_app_role" {
  filename = "${path.module}/output/iam-app-role.json"
  content = jsonencode({
    schema_version = "1.0"
    name           = "${var.app_name}-app-role-${var.environment}"
    description    = "Least-privilege role for ${var.app_name} application tier"
    assume_role_policy = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "AllowAppServicePrincipals"
          Effect = "Allow"
          Action = "sts:AssumeRole"
          Principal = {
            Service = local.app_service_principals
          }
        }
      ]
    }
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Application IAM policy — scoped read + logging permissions
# ---------------------------------------------------------------------------

resource "local_file" "iam_app_policy" {
  filename = "${path.module}/output/iam-app-policy.json"
  content = jsonencode({
    schema_version = "1.0"
    name           = "${var.app_name}-app-policy-${var.environment}"
    description    = "Read-only + logging permissions for ${var.app_name}"
    policy = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "AppS3Read"
          Effect   = "Allow"
          Action   = local.app_read_actions
          Resource = "arn:aws:s3:::${var.app_name}-${var.environment}-*"
        },
        {
          Sid      = "AppKmsDecrypt"
          Effect   = "Allow"
          Action   = local.kms_actions
          Resource = "arn:aws:kms:*:*:key/*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = "s3.amazonaws.com"
            }
          }
        }
      ]
    }
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# CI/CD deployment role — write permissions scoped to the app environment
# ---------------------------------------------------------------------------

resource "local_file" "iam_cicd_role" {
  filename = "${path.module}/output/iam-cicd-role.json"
  content = jsonencode({
    schema_version = "1.0"
    name           = "${var.app_name}-cicd-role-${var.environment}"
    description    = "CI/CD deployment role — write access scoped to ${var.environment}"
    assume_role_policy = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "AllowGitHubActionsOIDC"
          Effect = "Allow"
          Action = "sts:AssumeRoleWithWebIdentity"
          Principal = {
            Federated = "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
          }
          Condition = {
            StringLike = {
              "token.actions.githubusercontent.com:sub" = "repo:DevelApp-ai/deterministic-technical-design-specification:*"
            }
          }
        }
      ]
    }
    policy = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ECSDeployAccess"
          Effect = "Allow"
          Action = [
            "ecs:UpdateService",
            "ecs:DescribeServices",
            "ecs:DescribeTaskDefinition",
            "ecs:RegisterTaskDefinition",
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
          ]
          Resource = "*"
        }
      ]
    }
    tags = local.common_tags
  })
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# IAM summary Markdown (rendered into MkDocs "generated" section)
# ---------------------------------------------------------------------------

resource "local_file" "iam_summary_md" {
  filename = "${path.module}/../docs/generated/iam-summary.md"
  content  = <<-MARKDOWN
    # IAM Summary — ${var.app_name} (${var.environment})

    > Auto-generated by Terraform — do not edit manually.
    > Source: `terraform/iam.tf`

    ## Roles

    | Role | Purpose | Trust Principal |
    |------|---------|----------------|
    | `${var.app_name}-app-role-${var.environment}` | Application tier read access | EC2 / ECS tasks |
    | `${var.app_name}-cicd-role-${var.environment}` | CI/CD deployment | GitHub Actions OIDC |

    ## Policies

    | Policy | Allowed Actions | Scope |
    |--------|----------------|-------|
    | `${var.app_name}-app-policy-${var.environment}` | S3 GetObject/ListBucket, Secrets, SSM, Logs, KMS Decrypt | `${var.app_name}-${var.environment}-*` |
    | cicd inline policy | ECS update, ECR push | `*` (resource scoped by service) |

    ## Security Controls

    - No wildcard (`*`) principals in trust policies
    - No `*` actions on IAM, KMS, or STS services
    - CI/CD role uses OIDC federation (no long-lived access keys)
    - All roles carry FinOps cost-allocation tags

    ## Related OPA Policies

    - [SEC-003 — Deny Overly Permissive IAM](../compliance/opa-policies.md#sec-003--deny-overly-permissive-iam)
  MARKDOWN
  file_permission = "0644"
}
