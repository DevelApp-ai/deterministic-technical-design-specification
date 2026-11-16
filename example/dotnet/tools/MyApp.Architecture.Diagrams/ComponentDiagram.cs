using C4Sharp.Diagrams;
using C4Sharp.Diagrams.Builders;
using C4Sharp.Elements;
using C4Sharp.Elements.Relationships;

namespace MyApp.Architecture.Diagrams;

/// <summary>
/// C4 Component diagram of the MyApp API container: controller, application
/// service, the domain repository contract, and its infrastructure
/// implementation — mirroring the Api → Application → Domain layering that
/// the NetArchTest policies (APP-ARCH-001/002, APP-SEC-001) enforce.
/// </summary>
public sealed class MyAppComponentDiagram : ComponentDiagram
{
    /// <summary>The diagram title, also used to derive the output file name.</summary>
    protected override string Title => "MyApp API Components";

    /// <summary>Components and neighbours visible at the component level.</summary>
    protected override IEnumerable<Structure> Structures =>
    [
        new Person(
            alias: "consumer",
            label: "API Consumer",
            description: "A developer, script, or tool that calls the todo REST API.",
            boundary: Boundary.External),
        Container.None | (
            type: C4Sharp.Elements.ContainerType.Api,
            alias: "api",
            label: "MyApp API",
            technology: "ASP.NET Core (.NET 10)",
            description: "Serves the todo REST API."),
        Bound("api-components", "MyApp API",
            new Component(
                alias: "todosController",
                label: "Todos Controller",
                technology: "ASP.NET Core Controller",
                description: "Handles todo CRUD endpoints; talks only to the " +
                    "application service through DTOs (APP-SEC-001)."),
            new Component(
                alias: "todoService",
                label: "Todo Service",
                technology: "Application Service",
                description: "Use-case service for todo items; owns all " +
                    "orchestration between the API and the domain."),
            new Component(
                alias: "repositoryContract",
                label: "Todo Repository Contract",
                technology: "C# Interface",
                description: "Persistence contract owned by the domain layer " +
                    "(MyApp.Domain.ITodoRepository)."),
            new Component(
                alias: "todoRepository",
                label: "In-Memory Todo Repository",
                technology: "Infrastructure",
                description: "In-memory implementation wired to the contract in " +
                    "the composition root."))
    ];

    /// <summary>Component-level relationships.</summary>
    protected override IEnumerable<Relationship> Relationships =>
    [
        this["consumer"] > this["todosController"] | ("Calls", "HTTPS"),
        this["todosController"] > this["todoService"] | ("Calls", "in-process"),
        this["todoService"] > this["repositoryContract"] | ("Uses", "in-process"),
        this["todoRepository"] > this["repositoryContract"] | ("Implements", "in-process") | Position.Neighbor
    ];
}
