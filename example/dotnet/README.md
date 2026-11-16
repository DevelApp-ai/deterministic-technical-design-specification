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
│   ├── MyApp.ArchitectureTests/ # NetArchTest architecture policies
│   └── MyApp.UnitTests/        # xUnit unit tests
├── docs/                       # DocFX configuration (API reference generation)
├── dotnet-tools.json           # Pinned local tools (DocFX)
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

## Architecture policy gate

`tests/MyApp.ArchitectureTests` enforces named architecture policies using
NetArchTest.Rules:

| Policy | Enforces |
|--------|-----------|
| `APP-ARCH-001` | Controllers depend only on the application service layer, never on repository contracts |
| `APP-ARCH-002` | The domain layer references nothing above it (dependencies flow `Api → Application → Domain` only) |
| `APP-SEC-001` | Controllers expose DTOs, never domain entities |
| `APP-ARCH-003` | Every public member has an XML documentation entry (reflection-verified, custom check) |

The policy catalogue is published to `docs/application/architecture-policies.md`,
generated from the policy metadata literals embedded in the test source by
`scripts/generate-dotnet-policy-docs.py` (run from the `example/` directory).

## API reference generation (DocFX)

`docs/docfx.json` configures **DocFX** (pinned to 2.81.0 via the local tool
manifest `dotnet-tools.json`) to generate the API reference from the compiled
assemblies' XML documentation using DocFX's experimental Markdown output
format. The output lands in `example/docs/generated/dotnet-api/` (git-ignored,
regenerated on every pipeline run) and is published under the Application
section of the MkDocs site. `docs/filter.yml` keeps the entry-point class out
of the generated surface.

```bash
cd example/dotnet
dotnet tool restore
dotnet docfx metadata docs/docfx.json
```

The pipeline (`scripts/generate-docs.sh`, Step 5) runs `dotnet build` before
DocFX, so the deterministic gate — warnings-as-errors, analyzers, and the
architecture policies above — must pass before documentation is generated.

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
