using MyApp.Domain;

namespace MyApp.Api.Infrastructure;

/// <summary>
/// In-memory implementation of <see cref="ITodoRepository"/> used by the
/// example application. Real deployments would provide a persistent
/// implementation from the composition root instead.
/// </summary>
internal sealed class InMemoryTodoRepository : ITodoRepository
{
    private readonly Dictionary<Guid, TodoItem> _items = [];
    private readonly Lock _lock = new();

    /// <inheritdoc />
    public IReadOnlyList<TodoItem> GetAll()
    {
        lock (_lock)
        {
            return [.. _items.Values];
        }
    }

    /// <inheritdoc />
    public TodoItem? Find(Guid id)
    {
        lock (_lock)
        {
            return _items.GetValueOrDefault(id);
        }
    }

    /// <inheritdoc />
    public void Add(TodoItem item)
    {
        lock (_lock)
        {
            _items[item.Id] = item;
        }
    }

    /// <inheritdoc />
    public void Update(TodoItem item) => Add(item);

    /// <inheritdoc />
    public bool Remove(Guid id)
    {
        lock (_lock)
        {
            return _items.Remove(id);
        }
    }
}
