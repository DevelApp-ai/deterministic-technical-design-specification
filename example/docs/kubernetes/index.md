# Kubernetes & Helm

This chapter shows how the **deterministic documentation** approach extends
from Terraform (cloud IaC) to the Kubernetes workload layer.

Two packaging formats are demonstrated:

- `kubernetes/` — raw YAML manifests (GitOps / ArgoCD / Flux workflows)
- `helm/` — a Helm chart (`dtds-docs`) rendering the same resources from
  `values.yaml`

Both are governed by OPA policies and fully documented here.

---

## Architecture

```mermaid
C4Container
    title Kubernetes Workload Architecture

    Person(devops, "DevOps", "Deploys via Helm or kubectl")
    Person(dev, "Developer", "Reads docs at /")

    System_Boundary(cluster, "Kubernetes Cluster") {
        Container(ns, "dtds-example Namespace", "Kubernetes", "Isolated resource boundary with FinOps labels")
        Container(deploy, "dtds-docs Deployment", "nginx:1.27-alpine", "Serves the MkDocs static site (2 replicas)")
        Container(svc, "dtds-docs Service", "ClusterIP", "Internal load balancer on port 80")
    }

    System_Ext(gh_pages, "GitHub Pages", "Primary public site")
    System_Ext(helm_repo, "Helm Chart", "helm/ directory")

    devops --> helm_repo : helm install
    helm_repo --> deploy : renders Deployment + Service
    devops --> deploy : kubectl apply -f kubernetes/
    svc --> deploy : routes traffic
    dev --> svc : HTTP :80
    deploy --> gh_pages : static content served
```

---

## OPA Policy Coverage

Three OPA policies enforce Kubernetes workload hygiene:

| Policy | ID | Severity | Requirement |
|--------|----|---------|-------------|
| No privileged containers | **K8S-001** | CRITICAL | [K-001](../requirements/moscow.md#should-have--kubernetes) |
| CPU/memory limits required | **K8S-002** | HIGH | [K-002](../requirements/moscow.md#should-have--kubernetes) |
| Required FinOps labels | **K8S-003** | HIGH | [K-003](../requirements/moscow.md#should-have--kubernetes) / [FIN-001](../requirements/moscow.md#should-have--finops) |

Run the tests:

```bash
opa test example/policies/kubernetes/ -v
```

Expected output:
```
data.kubernetes.security_test.test_compliant_deployment_no_violations: PASS
data.kubernetes.security_test.test_privileged_container_denied: PASS
data.kubernetes.security_test.test_privilege_escalation_denied: PASS
data.kubernetes.security_test.test_missing_security_context_denied: PASS
data.kubernetes.resources_test.test_compliant_no_violations: PASS
data.kubernetes.resources_test.test_missing_cpu_limit_denied: PASS
data.kubernetes.resources_test.test_missing_memory_limit_denied: PASS
data.kubernetes.resources_test.test_no_limits_two_violations: PASS
data.kubernetes.finops_test.test_compliant_no_violations: PASS
data.kubernetes.finops_test.test_missing_one_label_one_violation: PASS
data.kubernetes.finops_test.test_missing_all_labels_four_violations: PASS
data.kubernetes.finops_test.test_non_workload_kind_not_checked: PASS
PASS: 12/12
```

---

## Security Contexts

The Deployment (`kubernetes/deployment.yaml` and `helm/templates/deployment.yaml`)
implements defence-in-depth at the container level:

| Setting | Value | Policy |
|---------|-------|--------|
| `privileged` | `false` | K8S-001 |
| `allowPrivilegeEscalation` | `false` | K8S-001 |
| `readOnlyRootFilesystem` | `true` | K8S-003 |
| `runAsNonRoot` | `true` | K8S-001 |
| `runAsUser` | `101` (nginx) | K8S-001 |
| `capabilities.drop` | `["ALL"]` | K8S-001 |
| `seccompProfile` | `RuntimeDefault` | K8S-001 |
| `automountServiceAccountToken` | `false` | K8S-001 |

---

## Helm Chart

The Helm chart packages the same resources as the raw manifests.

### Install

```bash
helm install dtds-docs example/helm/ \
  --namespace dtds-example \
  --create-namespace \
  --set labels.environment=production \
  --set labels.cost_center=CC-2001
```

### Upgrade

```bash
helm upgrade dtds-docs example/helm/ \
  --namespace dtds-example \
  --set image.tag=1.28-alpine
```

### Lint

```bash
helm lint example/helm/
```

### Template Preview

```bash
helm template dtds-docs example/helm/ \
  --namespace dtds-example
```

---

## FinOps Labels

All Kubernetes resources carry the four mandatory cost-allocation labels
enforced by **K8S-003**:

```yaml
labels:
  environment: staging
  app_name: dtds-example
  owner: platform-team
  cost_center: CC-1001
```

These labels mirror the Terraform `common_tags` local (enforced by
**FINOPS-001**), ensuring cost attribution is consistent across both IaC
layers.

---

## Traceability

| Artefact | Description |
|----------|-------------|
| `kubernetes/namespace.yaml` | Namespace with FinOps labels |
| `kubernetes/deployment.yaml` | nginx deployment (2 replicas, read-only rootfs) |
| `kubernetes/service.yaml` | ClusterIP service |
| `helm/Chart.yaml` | Helm chart metadata with traceability annotations |
| `helm/values.yaml` | Default values (override per environment) |
| `helm/templates/` | Go templates rendering Deployment + Service |
| `policies/kubernetes/deny_privileged_containers.rego` | K8S-001 |
| `policies/kubernetes/deny_missing_resource_limits.rego` | K8S-002 |
| `policies/kubernetes/deny_missing_labels.rego` | K8S-003 |
| ADR | [ADR-0008](../adrs/0008-kubernetes-manifests-and-helm-chart.md) |
| Requirements | [K-001, K-002, K-003](../requirements/moscow.md#should-have--kubernetes) |
