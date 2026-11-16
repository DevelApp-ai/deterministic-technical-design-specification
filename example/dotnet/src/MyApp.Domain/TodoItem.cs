namespace MyApp.Domain;

/// <summary>
/// A single todo item in the example application.
/// </summary>
/// <param name="Id">The stable identifier of the item.</param>
/// <param name="Title">The human-readable title of the item.</param>
/// <param name="IsCompleted">A value indicating whether the item is done.</param>
public sealed record TodoItem(Guid Id, string Title, bool IsCompleted)
{
    /// <summary>
    /// Creates a new, uncompleted todo item with a fresh identifier.
    /// </summary>
    /// <param name="title">The title of the item.</param>
    /// <returns>A new <see cref="TodoItem"/>.</returns>
    /// <exception cref="ArgumentException">Thrown when <paramref name="title"/> is null or whitespace.</exception>
    public static TodoItem Create(string title)
    {
        if (string.IsNullOrWhiteSpace(title))
        {
            throw new ArgumentException("A todo item must have a non-empty title.", nameof(title));
        }

        return new TodoItem(Guid.NewGuid(), title.Trim(), IsCompleted: false);
    }

    /// <summary>
    /// Returns a copy of this item marked as completed or uncompleted.
    /// </summary>
    /// <param name="isCompleted">The new completion state.</param>
    /// <returns>A new <see cref="TodoItem"/> with the given completion state.</returns>
    public TodoItem WithCompletion(bool isCompleted) =>
        this with { IsCompleted = isCompleted };
}
