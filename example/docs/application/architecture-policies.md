# .NET Architecture Policy Summary

!!! note "Auto-generated"
    This page is generated from the policy metadata embedded in
    `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs`
    (the `Policy.Define` literals and the custom-policy metadata tuple)
    by `scripts/generate-dotnet-policy-docs.py`. Re-run that script after
    changing the architecture policy suite.

## Policy Inventory

### APP-ARCH-001 — Controllers Must Not Depend On Repositories

| Field | Value |
|-------|-------|
| **ID** | `APP-ARCH-001` |
| **Severity** | HIGH |
| **File** | `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` |
| **Test** | `Policy_AppArch001_ControllersMustNotDependOnRepositories` |
| **Rule** | `controllers-do-not-depend-on-repositories` |
| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |

**Description:**  
Controllers must not depend on repository contracts directly; all access goes
through the application service layer.

**Rule:**  
Controller types must not reference the repository contract ITodoRepository.

---

### APP-ARCH-002 — Domain Must Not Reference Upper Layers

| Field | Value |
|-------|-------|
| **ID** | `APP-ARCH-002` |
| **Severity** | HIGH |
| **File** | `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` |
| **Test** | `Policy_AppArch002_DomainMustNotReferenceUpperLayers` |
| **Rule** | `domain-has-no-upward-references` |
| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |

**Description:**  
The domain layer must not reference the application or API layers; dependencies
flow Api -> Application -> Domain only.

**Rule:**  
Domain types must not reference MyApp.Application or MyApp.Api.

---

### APP-ARCH-003 — All Public Members Are Documented

| Field | Value |
|-------|-------|
| **ID** | `APP-ARCH-003` |
| **Severity** | HIGH |
| **File** | `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` |
| **Test** | `Policy_AppArch003_AllPublicMembersAreDocumented` |
| **Rule** | custom reflection-based check |
| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |

**Description:**  
All public members of the application layer must be documented (XML doc entries
verified against reflection).

---

### APP-SEC-001 — Controllers Must Not Expose Domain Entities

| Field | Value |
|-------|-------|
| **ID** | `APP-SEC-001` |
| **Severity** | CRITICAL |
| **File** | `example/dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` |
| **Test** | `Policy_AppSec001_ControllersMustNotExposeDomainEntities` |
| **Rule** | `controllers-do-not-expose-domain-entities` |
| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |

**Description:**  
Public controllers must not expose domain entities directly; API contracts use
DTOs from the application layer.

**Rule:**  
Controller types must not reference the domain entity TodoItem.

---

## Traceability

See the [Traceability Matrix](../traceability/index.md) for the full chain
from MoSCoW requirements to ADRs, policies, and code.

The choice of NetArchTest.Rules as the architecture-policy engine
(over alternatives such as ArchUnitNET) will be recorded in an
upcoming ADR as part of the .NET ADR series.

## Running the Policies Locally

```bash
# Run the full solution test suite (unit + architecture policies)
cd example/dotnet && dotnet test MyApp.slnx
```

