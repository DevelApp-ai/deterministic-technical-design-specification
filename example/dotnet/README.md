# MyApp — Example .NET Application Layer

This is the application-layer counterpart of the deterministic TDS pipeline:
a minimal ASP.NET Core Web API demonstrating that the same
deterministic-documentation pattern used for infrastructure
(auto-generated docs, policy gates, traceability) applies to application
code.

## Structure

```
dotnet/
├── src/
│   ├── MyApp.Api/              # ASP.NET Core API (controllers, composition root)
│   ├── MyApp.Application/      # Use cases and DTOs
│   └── MyApp.Domain/           # Entities and repository contracts
├── tests/
│   └── MyApp.UnitTests/        # xUnit unit tests
├── MyApp.slnx                   # Solution entry point for build/test
├── Directory.Build.props       # Shared deterministic-build properties
├── global.json                 # Pinned .NET SDK version
└── .editorconfig               # Style baseline
```

The dependency direction is strict and one-way: `Api → Application → Domain`.
The domain layer references nothing; the API layer wires infrastructure
implementations (currently an in-memory repository) to domain contracts in
its composition root.

## Deterministic build guarantees

Every project inherits from `Directory.Build.props`:

| Property | Effect |
|----------|--------|
| `GenerateDocumentationFile` | The compiler emits `///` XML docs and raises CS1591 on undocumented public members |
| `TreatWarningsAsErrors` | Any analyzer violation fails the build |
| `Deterministic` | Byte-reproducible compiler output |
| `ContinuousIntegrationBuild` | Normalised paths in CI (`CI`/`GITHUB_ACTIONS` set) |
| `Nullable` + `AnalysisLevel latest-recommended` | Latest analyzer surface |

`global.json` pins the SDK (10.0.404, .NET 10 LTS) so every machine and CI
runner produces the same build.

## Build and test

```bash
cd example/dotnet
dotnet build MyApp.slnx -c Release
dotnet test MyApp.slnx -c Release --no-build
```

Both must pass with **zero warnings** (warnings are errors).

## Static-analysis gate

Three analyzer packages are referenced from `Directory.Build.props`:
`Microsoft.CodeAnalysis.NetAnalyzers` (platform baseline), `Roslynator.Analyzers`
(code quality/style) and `SonarAnalyzer.CSharp` (security and code smells).
Severities are configured in `.editorconfig`: security-critical rules are
`error`, code-quality rules are `warning` (fail the build via
`TreatWarningsAsErrors`), style preferences are `suggestion`. The enforced
rule catalogue is documented in `docs/application/code-quality.md`.

## Endpoints

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/api/todos` | List all todo items |
| GET | `/api/todos/{id}` | Get one item |
| POST | `/api/todos` | Create an item (`{"title": "..."}`) |
| PATCH | `/api/todos/{id}` | Set completion (`true`/`false` body) |
| DELETE | `/api/todos/{id}` | Delete an item |

Run it:

```bash
dotnet run --project src/MyApp.Api
curl http://localhost:5000/api/todos
```

## Where this fits in the pipeline

This project is the foundation for the .NET layer of the TDS pipeline:
Roslyn analyzer gates, NetArchTest architecture policies, DocFX API
reference generation, native OpenAPI document generation, and C4Sharp
diagrams all build on it (see the corresponding issues/ADRs).
