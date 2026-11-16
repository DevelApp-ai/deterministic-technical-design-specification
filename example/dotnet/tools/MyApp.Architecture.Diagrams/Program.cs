// Generates the C4 architecture diagrams (Context, Container, Component)
// of the example .NET application as Mermaid sources.
//
// The diagrams are declared as C4Sharp DiagramBuilder subclasses
// (ContextDiagram.cs, ContainerDiagram.cs, ComponentDiagram.cs) so the
// model is code, reviewable in pull requests, and rendered by the same
// deterministic pipeline as every other documentation artefact.
//
// Output: docs/generated/architecture/*.mermaid.md (+ PlantUML sources),
// wrapped into docs/application/architecture-diagrams.md by
// scripts/generate-c4-diagram-docs.py.
//
// Usage:
//   dotnet run --project tools/MyApp.Architecture.Diagrams [-c Release] [output-directory]
//
// Without an explicit output directory the generator walks up from its own
// location to the pipeline root (the directory containing mkdocs.yml, i.e.
// example/) and writes into docs/generated/architecture/.

using C4Sharp.Diagrams;
using C4Sharp.Diagrams.Builders;
using C4Sharp.Diagrams.Plantuml;
using MyApp.Architecture.Diagrams;

if (args.Length > 1)
{
    await Console.Error.WriteLineAsync("Usage: MyApp.Architecture.Diagrams [output-directory]");
    return 1;
}

var outputDirectory = args.Length == 1
    ? args[0]
    : ResolveDefaultOutputDirectory();

var diagrams = new DiagramBuilder[]
{
    new MyAppContextDiagram(),
    new MyAppContainerDiagram(),
    new MyAppComponentDiagram()
};

using var plantuml = new PlantumlContext();
plantuml
    .UseDiagramMermaidBuilder()
    .Export(outputDirectory, diagrams);

foreach (var file in Directory.GetFiles(outputDirectory, "*").OrderBy(path => path, StringComparer.Ordinal))
{
    await Console.Out.WriteLineAsync($"Wrote {file}");
}

return 0;

// Locates the pipeline root (the directory that contains mkdocs.yml) by
// walking up from the application's base directory, then returns its
// docs/generated/architecture/ subdirectory.
static string ResolveDefaultOutputDirectory()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "mkdocs.yml")))
    {
        directory = directory.Parent;
    }

    if (directory is null)
    {
        throw new InvalidOperationException(
            "Could not locate the pipeline root (a directory containing mkdocs.yml). "
            + "Pass the output directory explicitly as the first argument.");
    }

    return Path.Combine(directory.FullName, "docs", "generated", "architecture");
}
