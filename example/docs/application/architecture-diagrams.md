# Architecture Diagrams (C4 Model)

!!! note "Auto-generated"
    This page embeds the Mermaid sources in
    `docs/generated/architecture/` — rendered by the C4Sharp
    generator project `dotnet/tools/MyApp.Architecture.Diagrams`
    (C4 model as code: the diagrams are declared in C# and rebuilt
    by the same deterministic pipeline as every other artefact).
    Re-render with
    `python3 scripts/generate-c4-diagram-docs.py` after regenerating
    the diagrams.

| Field | Value |
|-------|-------|
| **Model** | C4 (Context, Container, Component) |
| **Generator** | C4Sharp 8.1.204 (`dotnet/tools/MyApp.Architecture.Diagrams`) |
| **Output format** | Mermaid (`C4Context` / `C4Container` / `C4Component`) |
| **Generated sources** | `docs/generated/architecture/` |
| **Related Requirements** | [MoSCoW Prioritisation](../requirements/moscow.md) |
| **Related policies** | [Architecture Policies](architecture-policies.md) |

The diagrams are the reviewable source of truth for the application's
structure: they change only in pull requests, together with the code
they describe, and the pipeline re-renders them on every build.

## System Context

The C4 System Context diagram: the API consumer and the MyApp software system, with no internal detail.

```mermaid
C4Context

title MyApp System Context

Person_Ext(consumer, "API Consumer", "A developer, script, or tool that calls the todo REST API.")
System(myapp, "MyApp", "The example todo application: a layered ASP.NET Core API that demonstrates the deterministic documentation pipeline.")

Rel(consumer, myapp, "Uses", "HTTPS")
```

## Containers

The C4 Container diagram: the MyApp API container and its in-memory store boundary.

```mermaid
C4Container

title MyApp Containers

Person_Ext(consumer, "API Consumer", "A developer, script, or tool that calls the todo REST API.")

System_Boundary(myapp, "MyApp") {
    Container(api, "MyApp API", "Api:ASP.NET Core (.NET 10)", "Serves the todo REST API; wires infrastructure implementations to domain contracts in the composition root.")
    ContainerDb(store, "In-Memory Store", "Database:C# Dictionary + Lock", "Holds todo items for the lifetime of the process; a real deployment would swap in a persistent store.")
}


Rel(consumer, api, "Uses", "HTTPS")
Rel_Back(store, api, "Reads and writes", "in-process")
```

## Components (MyApp API)

The C4 Component diagram of the MyApp API container — controller, application service, the domain repository contract, and its infrastructure implementation. The arrows mirror the strict Api → Application → Domain layering that the NetArchTest policies (APP-ARCH-001/002, APP-SEC-001) enforce.

```mermaid
C4Component

title MyApp API Components

Person_Ext(consumer, "API Consumer", "A developer, script, or tool that calls the todo REST API.")
Container(api, "MyApp API", "Api:ASP.NET Core (.NET 10)", "Serves the todo REST API.")

Container_Boundary(api-components, "MyApp API") {
    Component(todosController, "Todos Controller", "ASP.NET Core Controller", "Handles todo CRUD endpoints; talks only to the application service through DTOs (APP-SEC-001).")
    Component(todoService, "Todo Service", "Application Service", "Use-case service for todo items; owns all orchestration between the API and the domain.")
    Component(repositoryContract, "Todo Repository Contract", "C# Interface", "Persistence contract owned by the domain layer (MyApp.Domain.ITodoRepository).")
    Component(todoRepository, "In-Memory Todo Repository", "Infrastructure", "In-memory implementation wired to the contract in the composition root.")
}


Rel(consumer, todosController, "Calls", "HTTPS")
Rel(todosController, todoService, "Calls", "in-process")
Rel(todoService, repositoryContract, "Uses", "in-process")
Rel(todoRepository, repositoryContract, "Implements", "in-process")
```

## Traceability

The C4 model is a traceable pipeline artefact: it is declared as
code, regenerated deterministically, and embedded in this page.
See the
[Traceability Matrix](../traceability/index.md) for the full chain
from MoSCoW requirements to ADRs, policies, and code. The
C4Sharp-over-Mermaid approach will be recorded in the .NET ADR
series (together with the other tooling decisions).
