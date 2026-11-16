using C4Sharp.Diagrams.Builders;
using C4Sharp.Elements;
using C4Sharp.Elements.Relationships;

namespace MyApp.Architecture.Diagrams;

/// <summary>
/// C4 System Context diagram of the example application: the API consumer
/// and the MyApp software system, with no internal detail.
/// </summary>
public sealed class MyAppContextDiagram : ContextDiagram
{
    /// <summary>The diagram title, also used to derive the output file name.</summary>
    protected override string Title => "MyApp System Context";

    /// <summary>People and systems visible at the context level.</summary>
    protected override IEnumerable<Structure> Structures =>
    [
        new Person(
            alias: "consumer",
            label: "API Consumer",
            description: "A developer, script, or tool that calls the todo REST API.",
            boundary: Boundary.External),
        new SoftwareSystem(
            alias: "myapp",
            label: "MyApp",
            description: "The example todo application: a layered ASP.NET Core API " +
                "that demonstrates the deterministic documentation pipeline.")
    ];

    /// <summary>Context-level relationships.</summary>
    protected override IEnumerable<Relationship> Relationships =>
    [
        this["consumer"] > this["myapp"] | ("Uses", "HTTPS")
    ];
}
