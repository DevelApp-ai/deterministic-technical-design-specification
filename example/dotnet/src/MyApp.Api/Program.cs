using MyApp.Api.Infrastructure;
using MyApp.Application;
using MyApp.Domain;

var builder = WebApplication.CreateBuilder(args);

// Composition root: the only place where infrastructure implementations
// are wired to their domain contracts.
builder.Services.AddSingleton<ITodoRepository, InMemoryTodoRepository>();
builder.Services.AddSingleton<TodoService>();

builder.Services.AddControllers();

// Registers the native OpenAPI document that `dotnet build` emits at
// build time (docs/generated/openapi.json) and that /openapi/v1.json
// serves at runtime.
builder.Services.AddOpenApi();

var app = builder.Build();

app.MapControllers();

app.MapOpenApi();

await app.RunAsync();
