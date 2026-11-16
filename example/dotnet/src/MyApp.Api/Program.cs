using MyApp.Api.Infrastructure;
using MyApp.Application;
using MyApp.Domain;

var builder = WebApplication.CreateBuilder(args);

// Composition root: the only place where infrastructure implementations
// are wired to their domain contracts.
builder.Services.AddSingleton<ITodoRepository, InMemoryTodoRepository>();
builder.Services.AddSingleton<TodoService>();

builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();

await app.RunAsync();
