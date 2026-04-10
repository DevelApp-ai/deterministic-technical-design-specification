---
id: ADR-0008
title: Add Kubernetes Manifests and Helm Chart as IaC Examples
status: Accepted
date: 2024-04-01
author: platform-team
tags: [kubernetes, helm, iac, policy-as-code, opa, k8s]
supersedes: []
related_requirements: [K-001, K-002, K-003, FIN-001]
---

# ADR-0008 — Add Kubernetes Manifests and Helm Chart as IaC Examples

## Status

Accepted

## Context

The example repository already demonstrates Terraform as an IaC layer.
Kubernetes is the dominant container orchestration platform and represents
a second, complementary IaC layer that many teams use alongside Terraform.

Demonstrating the deterministic documentation approach on Kubernetes
manifests shows that the same principles (policy as code, auto-generated
docs, traceability) apply across IaC paradigms.

Two common packaging approaches exist for Kubernetes: raw YAML manifests
(suitable for GitOps / Flux / ArgoCD workflows) and Helm charts (the
de-facto package manager for Kubernetes).  Both are included to give
practitioners a reference for each.

## Decision

Add two new layers to the example:

1. **`kubernetes/`** — raw YAML manifests (Namespace, Deployment, Service)
   with all required security contexts and FinOps labels.

2. **`helm/`** — a Helm chart (`dtds-docs`) that renders the same
   Kubernetes resources from `values.yaml` defaults using Go templates.

Both layers are governed by three OPA policies in `policies/kubernetes/`:

| Policy | ID | Severity |
|--------|----|---------|
| No privileged containers | K8S-001 | CRITICAL |
| CPU/memory limits required | K8S-002 | HIGH |
| Required FinOps labels | K8S-003 | HIGH |

Each policy has 100 % unit-test coverage (`*_test.rego`).

Documentation is auto-generated from the manifest YAML and Helm
`Chart.yaml` annotations into `docs/kubernetes/index.md`.

## Consequences

### Positive

- Demonstrates the deterministic documentation approach on a second IaC
  paradigm (Kubernetes) beyond Terraform.
- Three new OPA policies extend the policy-as-code coverage to the
  workload layer.
- Helm chart annotations provide machine-readable traceability metadata
  (`dtds/related_requirements`, `dtds/related_adr`).
- Developers have a compliant reference for both raw manifests and Helm.

### Negative / Trade-offs

- Adds two new tool dependencies to the CI image (kubectl / helm) for
  validation.  Both are pinned to exact versions in `Dockerfile`.
- Raw manifests and Helm chart are kept in sync manually; drift is
  possible if one is updated without the other.  The DOC-HELM gate
  (ADR-0006) mitigates documentation drift but not YAML drift.

## Alternatives Considered

| Alternative | Notes |
|-------------|-------|
| Kustomize only | Less widely used than Helm; would not showcase templating |
| Operator SDK | Too complex for a showcase; requires a running cluster |
| Pulumi / CDK8s | Adds a Node/Python runtime; out of scope for this example |

## Related

- [ADR-0001 — Terraform for IaC](0001-use-terraform-for-iac.md)
- [ADR-0002 — OPA for Policy](0002-use-opa-for-policy.md)
- [ADR-0006 — Doc Coverage Gate](0006-enforce-doc-coverage-gate.md)
- MoSCoW requirements: [K-001, K-002, K-003](../requirements/moscow.md#should-have--kubernetes)
