namespace MyApp.Application;

/// <summary>
/// Data-transfer shape of a todo item exposed by the application layer.
/// </summary>
/// <spec>moscow:M-002</spec>
/// <param name="Id">The stable identifier of the item.</param>
/// <param name="Title">The human-readable title of the item.</param>
/// <param name="IsCompleted">A value indicating whether the item is done.</param>
public sealed record TodoDto(Guid Id, string Title, bool IsCompleted);
