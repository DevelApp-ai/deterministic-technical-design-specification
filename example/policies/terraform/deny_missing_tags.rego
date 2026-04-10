# policies/terraform/deny_missing_tags.rego
#
# Policy: every Terraform resource must carry the four mandatory FinOps
# cost-allocation tags: environment, app_name, owner, cost_center.
#
# This policy is evaluated against the JSON output of `terraform plan`
# (planned_values.root_module.resources[*]) during the CI/CD pipeline.

package terraform.finops

import rego.v1

# Required cost-allocation tags — any resource missing one or more of these
# will produce a denial message.
required_tags := {"environment", "app_name", "owner", "cost_center"}

# __rego__metadoc__ provides self-describing metadata that the OPA evaluation
# engine embeds into compliance reports and the technical design specification.
__rego__metadoc__ := {
	"id": "FINOPS-001",
	"title": "Mandatory FinOps Cost-Allocation Tags",
	"description": "All Terraform resources must carry the four mandatory cost-allocation tags (environment, app_name, owner, cost_center) so that cloud expenditure can be attributed to the correct team and project.",
	"severity": "HIGH",
	"remediation": "Add a `tags` block to the offending resource that includes all four required keys.",
	# Traceability — links this policy back to the decisions and requirements
	# that mandated its existence.
	"related_adr": ["ADR-0002"],
	"related_requirements": ["M-002", "M-003", "S-001", "S-002"],
	"compliance": {
		"nis2":        ["Art.21(2)(i)"],
	},
}

# Collect every violation across all planned resources.
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource_tags := {tag | tag := resource.values.tags[_]; true} | object.keys(object.get(resource.values, "tags", {}))
	missing := required_tags - resource_tags
	count(missing) > 0
	msg := sprintf(
		"[FINOPS-001] Resource '%s' is missing required cost-allocation tags: %v",
		[resource.address, missing],
	)
}
