namespace MyApp.Application;

/// <summary>
/// Data for creating a new todo item.
/// </summary>
/// <spec>moscow:M-002</spec>
/// <param name="Title">The title of the new item.</param>
public sealed record CreateTodoRequest(string Title);
