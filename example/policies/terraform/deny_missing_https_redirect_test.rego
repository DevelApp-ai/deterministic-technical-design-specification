# policies/terraform/deny_missing_https_redirect_test.rego
#
# Unit tests for SEC-005: deny_missing_https_redirect.rego
#
# Run:  opa test policies/terraform/ -v

package terraform.https_test

import data.terraform.https
import rego.v1

_mock_input(resources) := {"planned_values": {"root_module": {"resources": resources}}}

# ===========================================================================
# Rule 1: AWS ALB listener — no redirect action
# ===========================================================================

test_alb_http_no_redirect_denied if {
	mock := _mock_input([{
		"address": "aws_alb_listener.http",
		"type":    "aws_alb_listener",
		"values": {
			"port":     80,
			"protocol": "HTTP",
			"default_action": [{"type": "forward"}],
		},
	}])
	msgs := https.deny with input as mock
	count(msgs) == 1
	some msg in msgs
	contains(msg, "SEC-005")
}

test_alb_http_with_https_redirect_passes if {
	mock := _mock_input([{
		"address": "aws_alb_listener.http_redirect",
		"type":    "aws_alb_listener",
		"values": {
			"port":     80,
			"protocol": "HTTP",
			"default_action": [{"type": "redirect", "redirect": [{"protocol": "HTTPS", "status_code": "HTTP_301"}]}],
		},
	}])
	count(https.deny) == 0 with input as mock
}

test_alb_https_listener_ignored if {
	# HTTPS listeners on port 443 are not checked by this rule
	mock := _mock_input([{
		"address": "aws_alb_listener.https",
		"type":    "aws_alb_listener",
		"values": {
			"port":       443,
			"protocol":   "HTTPS",
			"ssl_policy": "ELBSecurityPolicy-TLS13-1-2-2021-06",
			"default_action": [{"type": "forward"}],
		},
	}])
	count(https.deny) == 0 with input as mock
}

# ===========================================================================
# Rule 1b: Redirect exists but targets wrong protocol
# ===========================================================================

test_alb_redirect_to_http_denied if {
	mock := _mock_input([{
		"address": "aws_alb_listener.bad_redirect",
		"type":    "aws_alb_listener",
		"values": {
			"port":     80,
			"protocol": "HTTP",
			"default_action": [{"type": "redirect", "redirect": [{"protocol": "HTTP", "status_code": "HTTP_301"}]}],
		},
	}])
	msgs := https.deny with input as mock
	some msg in msgs
	contains(msg, "SEC-005")
}

# ===========================================================================
# Rule 3: Deployment manifest exposes port 80 without redirect annotation
# ===========================================================================

test_manifest_port80_no_annotation_denied if {
	mock := _mock_input([{
		"address": "local_file.deployment_manifest",
		"type":    "local_file",
		"values": {
			"filename": "/tmp/deployment.yaml",
			"content":  "containerPort: 80\n",
		},
	}])
	msgs := https.deny with input as mock
	some msg in msgs
	contains(msg, "SEC-005")
	contains(msg, "redirect-https")
}

test_manifest_port80_with_annotation_passes if {
	mock := _mock_input([{
		"address": "local_file.deployment_manifest",
		"type":    "local_file",
		"values": {
			"filename": "/tmp/deployment.yaml",
			"content":  "containerPort: 80\nredirect-https: \"true\"\n",
		},
	}])
	count(https.deny) == 0 with input as mock
}

test_manifest_no_port80_passes if {
	mock := _mock_input([{
		"address": "local_file.deployment_manifest",
		"type":    "local_file",
		"values": {
			"filename": "/tmp/deployment.yaml",
			"content":  "containerPort: 443\n",
		},
	}])
	count(https.deny) == 0 with input as mock
}
