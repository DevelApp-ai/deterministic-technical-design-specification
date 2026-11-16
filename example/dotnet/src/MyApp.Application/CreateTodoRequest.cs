namespace MyApp.Application;

/// <summary>
/// Data for creating a new todo item.
/// </summary>
/// <param name="Title">The title of the new item.</param>
public sealed record CreateTodoRequest(string Title);
