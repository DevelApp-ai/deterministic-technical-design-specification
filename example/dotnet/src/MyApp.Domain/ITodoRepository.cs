namespace MyApp.Domain;

/// <summary>
/// Persistence contract for todo items.
/// </summary>
/// <remarks>
/// The contract lives in the domain layer so that application services can
/// depend on it without referencing any concrete infrastructure.
/// </remarks>
public interface ITodoRepository
{
    /// <summary>
    /// Returns all todo items currently in the store.
    /// </summary>
    /// <returns>An ordered, read-only view of every stored item.</returns>
    IReadOnlyList<TodoItem> GetAll();

    /// <summary>
    /// Returns the todo item with the given identifier, if present.
    /// </summary>
    /// <param name="id">The identifier to look up.</param>
    /// <returns>The matching item, or <see langword="null"/> when no item exists.</returns>
    TodoItem? Find(Guid id);

    /// <summary>
    /// Adds a new todo item to the store.
    /// </summary>
    /// <param name="item">The item to add.</param>
    void Add(TodoItem item);

    /// <summary>
    /// Replaces a stored todo item with an updated copy.
    /// </summary>
    /// <param name="item">The item to update; identified by <see cref="TodoItem.Id"/>.</param>
    void Update(TodoItem item);

    /// <summary>
    /// Removes the todo item with the given identifier from the store.
    /// </summary>
    /// <param name="id">The identifier of the item to remove.</param>
    /// <returns><see langword="true"/> when an item was removed; otherwise <see langword="false"/>.</returns>
    bool Remove(Guid id);
}
