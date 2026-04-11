# policies/terraform/deny_nis2_supply_chain_test.rego
#
# Unit tests for SC-001: deny_nis2_supply_chain.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.supply_chain_test

import data.terraform.supply_chain
import rego.v1

# ---------------------------------------------------------------------------
# Mock input builder
# ---------------------------------------------------------------------------

_mock(module_calls, provider_config) := {
	"configuration": {"root_module": {
		"module_calls": module_calls,
		"provider_config": provider_config,
	}},
}

_mock_modules(module_calls) := _mock(module_calls, {})

_mock_providers(provider_config) := _mock({}, provider_config)

# ---------------------------------------------------------------------------
# Rule 1: Git module source has no ?ref=
# ---------------------------------------------------------------------------

test_git_module_no_ref_denied if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "no ?ref= parameter")
}

test_git_github_prefix_no_ref_denied if {
	mock := _mock_modules({"net": {"source": "github.com/org/terraform-net"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "no ?ref= parameter")
}

# ---------------------------------------------------------------------------
# Rule 2: Git module source uses a mutable branch ref
# ---------------------------------------------------------------------------

test_git_module_main_ref_denied if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git?ref=main"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "mutable ref")
	contains(msg, "main")
}

test_git_module_master_ref_denied if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git?ref=master"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "mutable ref")
}

test_git_module_head_ref_denied if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git?ref=HEAD"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "mutable ref")
}

test_git_module_semver_ref_passes if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git?ref=v1.3.0"}})
	count(supply_chain.deny) == 0 with input as mock
}

test_git_module_semver_ref_with_patch_passes if {
	mock := _mock_modules({"vpc": {"source": "git::https://github.com/org/vpc.git?ref=v2.10.4"}})
	count(supply_chain.deny) == 0 with input as mock
}

# ---------------------------------------------------------------------------
# Rule 3: Registry module has no version constraint
# ---------------------------------------------------------------------------

test_registry_module_no_constraint_denied if {
	mock := _mock_modules({"vpc": {"source": "terraform-aws-modules/vpc/aws"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "no version constraint")
}

# ---------------------------------------------------------------------------
# Rule 4: Registry module has a floating version constraint
# ---------------------------------------------------------------------------

test_registry_module_floating_constraint_denied if {
	mock := _mock_modules({"vpc": {
		"source":             "terraform-aws-modules/vpc/aws",
		"version_constraint": ">= 5.0",
	}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "floating version constraint")
}

test_registry_module_pessimistic_constraint_passes if {
	mock := _mock_modules({"vpc": {
		"source":             "terraform-aws-modules/vpc/aws",
		"version_constraint": "~> 5.0",
	}})
	count(supply_chain.deny) == 0 with input as mock
}

test_registry_module_exact_version_passes if {
	mock := _mock_modules({"vpc": {
		"source":             "terraform-aws-modules/vpc/aws",
		"version_constraint": "5.2.0",
	}})
	count(supply_chain.deny) == 0 with input as mock
}

test_registry_module_bounded_range_passes if {
	mock := _mock_modules({"vpc": {
		"source":             "terraform-aws-modules/vpc/aws",
		"version_constraint": ">= 5.0, < 6.0",
	}})
	count(supply_chain.deny) == 0 with input as mock
}

# ---------------------------------------------------------------------------
# Rule 5: Provider has no version constraint
# ---------------------------------------------------------------------------

test_provider_no_constraint_denied if {
	mock := _mock_providers({"aws": {"name": "aws", "full_name": "registry.terraform.io/hashicorp/aws"}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "no version constraint")
}

# ---------------------------------------------------------------------------
# Rule 6: Provider has a floating version constraint
# ---------------------------------------------------------------------------

test_provider_floating_constraint_denied if {
	mock := _mock_providers({"aws": {
		"name":               "aws",
		"version_constraint": ">= 5.0",
	}})
	msgs := supply_chain.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SC-001")
	contains(msg, "floating version constraint")
}

test_provider_pessimistic_constraint_passes if {
	mock := _mock_providers({"local": {
		"name":               "local",
		"version_constraint": "~> 2.5",
	}})
	count(supply_chain.deny) == 0 with input as mock
}

test_provider_exact_version_passes if {
	mock := _mock_providers({"aws": {
		"name":               "aws",
		"version_constraint": "5.53.0",
	}})
	count(supply_chain.deny) == 0 with input as mock
}

# ---------------------------------------------------------------------------
# Combined: no modules or providers → no violations
# ---------------------------------------------------------------------------

test_empty_configuration_passes if {
	mock := _mock({}, {})
	count(supply_chain.deny) == 0 with input as mock
}

# ---------------------------------------------------------------------------
# Combined: multiple violations counted correctly
# ---------------------------------------------------------------------------

test_multiple_violations_counted if {
	mock := _mock(
		{
			"mod_a": {"source": "git::https://github.com/org/a.git?ref=main"},
			"mod_b": {"source": "terraform-aws-modules/vpc/aws"},
		},
		{"aws": {
			"name":               "aws",
			"version_constraint": ">= 5.0",
		}},
	)
	# mod_a: mutable ref (1) + mod_b: no constraint (1) + aws: floating (1) = 3
	count(supply_chain.deny) == 3 with input as mock
}
