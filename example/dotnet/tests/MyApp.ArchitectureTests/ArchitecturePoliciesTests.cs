using System.Reflection;
using System.Text;
using System.Xml.Linq;
using NetArchTest.Rules;
using NetArchTest.Rules.Policies;
using Xunit;
using MyApp.Api.Controllers;
using MyApp.Application;
using MyApp.Domain;

namespace MyApp.ArchitectureTests;

/// <summary>
/// Named architecture policies for the .NET application layer.
/// </summary>
/// <remarks>
/// Each policy uses <see cref="Policy.Define"/> so the policy carries
/// self-describing metadata (id + description), mirroring the
/// <c>__rego__metadoc__</c> pattern of the OPA policies. The compliance page
/// <c>docs/application/architecture-policies.md</c> is generated from these
/// literals by <c>scripts/generate-dotnet-policy-docs.py</c>.
/// </remarks>
public sealed class ArchitecturePoliciesTests
{
    private static readonly Assembly ApiAssembly = typeof(TodosController).Assembly;
    private static readonly Assembly DomainAssembly = typeof(TodoItem).Assembly;

    /// <summary>
    /// APP-ARCH-003 metadata for the custom (non-NetArchTest) documentation
    /// policy below — custom checks cannot use <see cref="Policy.Define"/>,
    /// so the generator script recognises this literal pair too.
    /// </summary>
    private static readonly (string Id, string Description) AppArch003 =
        ("APP-ARCH-003",
            "All public members of the application layer must be documented (XML doc entries verified against reflection).");

    /// <summary>
    /// APP-ARCH-001: controllers must not depend on repositories directly —
    /// every dependency goes through the application service layer.
    /// </summary>
    [Fact]
    public void Policy_AppArch001_ControllersMustNotDependOnRepositories()
    {
        var results = Policy
            .Define("APP-ARCH-001",
                "Controllers must not depend on repository contracts directly; all access goes through the application service layer.")
            .For(Types.InAssembly(ApiAssembly))
            .Add(
                types => types
                    .That()
                    .ResideInNamespace("MyApp.Api.Controllers")
                    .Should()
                    .NotHaveDependencyOn("MyApp.Domain.ITodoRepository"),
                "controllers-do-not-depend-on-repositories",
                "Controller types must not reference the repository contract ITodoRepository.")
            .Evaluate();

        Assert.False(results.HasViolations, FormatViolations("APP-ARCH-001", results));
    }

    /// <summary>
    /// APP-ARCH-002: the domain layer must stay dependency-free — no
    /// references to the application or API layers.
    /// </summary>
    [Fact]
    public void Policy_AppArch002_DomainMustNotReferenceUpperLayers()
    {
        var results = Policy
            .Define("APP-ARCH-002",
                "The domain layer must not reference the application or API layers; dependencies flow Api -> Application -> Domain only.")
            .For(Types.InAssembly(DomainAssembly))
            .Add(
                types => types
                    .Should()
                    .NotHaveDependencyOn("MyApp.Application")
                    .And()
                    .NotHaveDependencyOn("MyApp.Api"),
                "domain-has-no-upward-references",
                "Domain types must not reference MyApp.Application or MyApp.Api.")
            .Evaluate();

        Assert.False(results.HasViolations, FormatViolations("APP-ARCH-002", results));
    }

    /// <summary>
    /// APP-SEC-001: public controllers must not expose domain entities —
    /// everything crossing the API boundary is a DTO.
    /// </summary>
    [Fact]
    public void Policy_AppSec001_ControllersMustNotExposeDomainEntities()
    {
        var results = Policy
            .Define("APP-SEC-001",
                "Public controllers must not expose domain entities directly; API contracts use DTOs from the application layer.")
            .For(Types.InAssembly(ApiAssembly))
            .Add(
                types => types
                    .That()
                    .ResideInNamespace("MyApp.Api.Controllers")
                    .Should()
                    .NotHaveDependencyOn("MyApp.Domain.TodoItem"),
                "controllers-do-not-expose-domain-entities",
                "Controller types must not reference the domain entity TodoItem.")
            .Evaluate();

        Assert.False(results.HasViolations, FormatViolations("APP-SEC-001", results));
    }

    /// <summary>
    /// APP-ARCH-003: every public member of the application layer is
    /// documented. The build raises CS1591 on missing <c>///</c> comments;
    /// this policy verifies the emitted XML documentation files contain an
    /// entry for every public type, method, and property, so documentation
    /// generation (DocFX, OpenAPI) has a complete input.
    /// </summary>
    [Fact]
    public void Policy_AppArch003_AllPublicMembersAreDocumented()
    {
        var assemblies = new[]
        {
            typeof(TodoItem).Assembly,
            typeof(TodoService).Assembly,
            typeof(TodosController).Assembly
        };

        var missing = new List<string>();

        foreach (var assembly in assemblies)
        {
            var docPath = Path.Combine(
                AppContext.BaseDirectory,
                Path.GetFileNameWithoutExtension(assembly.Location) + ".xml");
            Assert.True(File.Exists(docPath), $"XML documentation file not found: {docPath}");

            var doc = XDocument.Load(docPath);
            var documented = new HashSet<string>(
                doc.Root!.Descendants("member").Select(m => m.Attribute("name")!.Value));

            foreach (var type in assembly.GetTypes())
            {
                if (!type.IsPublic || type.IsNested)
                {
                    continue;
                }

                if (!documented.Contains($"T:{type.FullName}"))
                {
                    missing.Add($"T:{type.FullName}");
                }

                foreach (var member in type.GetMembers(
                    BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
                {
                    string docId;
                    switch (member)
                    {
                        case PropertyInfo p when p.GetMethod is { IsPublic: true } || p.SetMethod is { IsPublic: true }:
                            docId = $"P:{type.FullName}.{p.Name}";
                            break;
                        case MethodInfo m when !m.IsSpecialName && !IsCompilerSynthesized(m) && !IsOverride(m):
                            docId = $"M:{type.FullName}.{m.Name}{ParameterList(m)}";
                            break;
                        default:
                            docId = string.Empty;
                            break;
                    }

                    if (docId.Length > 0 && !documented.Contains(docId))
                    {
                        missing.Add(docId);
                    }
                }
            }
        }

        Assert.True(missing.Count == 0,
            $"{AppArch003.Id} violated — public members without XML documentation:\n"
            + string.Join("\n", missing));
    }

    /// <summary>
    /// Members the record compiler synthesis adds (equality, formatting,
    /// operators) — not part of the hand-written public API surface.
    /// </summary>
    private static bool IsCompilerSynthesized(MethodInfo m) =>
        m.Name.Length > 0 && m.Name[0] == '<'
            || m.Name is "ToString" or "GetHashCode" or "Equals" or "PrintMembers" or "PrintToString"
            or "Deconstruct"
            or "op_Equality" or "op_Inequality";

    /// <summary>
    /// Overrides inherit the base member's documentation contract; only
    /// newly declared API must carry its own <c>///</c> entry.
    /// </summary>
    private static bool IsOverride(MethodInfo m) => m.GetBaseDefinition() != m;

    /// <summary>
    /// Builds the XML documentation ID parameter list, e.g.
    /// <c>(System.Guid,System.Boolean)</c>; empty for parameterless methods.
    /// </summary>
    private static string ParameterList(MethodInfo m)
    {
        var parameters = m.GetParameters();
        return parameters.Length == 0
            ? string.Empty
            : $"({string.Join(",", parameters.Select(p => DocTypeName(p.ParameterType)))})";
    }

    /// <summary>
    /// Renders the reflection type name in XML documentation ID form:
    /// generic parameters keep their bare name, generics use
    /// <c>Namespace.Type{T}</c>, arrays get a <c>[]</c> suffix.
    /// </summary>
    private static string DocTypeName(Type type)
    {
        if (type.IsArray)
        {
            return $"{DocTypeName(type.GetElementType()!)}[]";
        }

        if (type.IsGenericParameter)
        {
            return type.Name;
        }

        if (type.IsGenericType)
        {
            var name = type.FullName!.Split('`')[0];
            var arguments = string.Join(",", type.GetGenericArguments().Select(DocTypeName));
            return $"{name}{{{arguments}}}";
        }

        return type.FullName!;
    }

    private static string FormatViolations(string policyId, PolicyResults results)
    {
        var sb = new StringBuilder($"{policyId} violated:\n");
        foreach (var result in results.Results.Where(r => !r.IsSuccessful))
        {
            sb.AppendLine("  rule '" + result.Name + "': " + result.Description);
            foreach (var type in result.FailingTypes)
            {
                sb.AppendLine("    - " + type);
            }
        }

        return sb.ToString();
    }
}
