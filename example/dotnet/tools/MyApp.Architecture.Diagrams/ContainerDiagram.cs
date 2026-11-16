using C4Sharp.Diagrams.Builders;
using C4Sharp.Elements;
using C4Sharp.Elements.Relationships;
using static C4Sharp.Elements.ContainerType;

namespace MyApp.Architecture.Diagrams;

/// <summary>
/// C4 Container diagram of the example application: the MyApp API container
/// and its in-memory store boundary.
/// </summary>
public sealed class MyAppContainerDiagram : ContainerDiagram
{
    /// <summary>The diagram title, also used to derive the output file name.</summary>
    protected override string Title => "MyApp Containers";

    /// <summary>People, systems, and containers visible at the container level.</summary>
    protected override IEnumerable<Structure> Structures =>
    [
        new Person(
            alias: "consumer",
            label: "API Consumer",
            description: "A developer, script, or tool that calls the todo REST API.",
            boundary: Boundary.External),
        Bound("myapp", "MyApp",
            Container.None | (
                type: Api,
                alias: "api",
                label: "MyApp API",
                technology: "ASP.NET Core (.NET 10)",
                description: "Serves the todo REST API; wires infrastructure " +
                    "implementations to domain contracts in the composition root."),
            Container.None | (
                type: Database,
                alias: "store",
                label: "In-Memory Store",
                technology: "C# Dictionary + Lock",
                description: "Holds todo items for the lifetime of the process; " +
                    "a real deployment would swap in a persistent store."))
    ];

    /// <summary>Container-level relationships.</summary>
    protected override IEnumerable<Relationship> Relationships =>
    [
        this["consumer"] > this["api"] | ("Uses", "HTTPS"),
        this["store"] < this["api"] | ("Reads and writes", "in-process") | Position.Neighbor
    ];
}
