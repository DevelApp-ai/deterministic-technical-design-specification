namespace MyApp.Application;

/// <summary>
/// Use-case service for todo items: the only surface the API layer talks to.
/// </summary>
/// <spec>moscow:M-001</spec>
/// <spec>moscow:S-002</spec>
/// <remarks>
/// The service depends on the domain repository contract
/// (<see cref="MyApp.Domain.ITodoRepository"/>) and never exposes domain
/// entities to callers; everything crosses the boundary as
/// <see cref="TodoDto"/>.
/// </remarks>
public sealed class TodoService
{
    private readonly MyApp.Domain.ITodoRepository _repository;

    /// <summary>
    /// Initializes a new instance of the <see cref="TodoService"/> class.
    /// </summary>
    /// <param name="repository">The backing todo repository.</param>
    public TodoService(MyApp.Domain.ITodoRepository repository)
    {
        _repository = repository;
    }

    /// <summary>
    /// Returns all todo items, newest last.
    /// </summary>
    /// <returns>Every stored item as a <see cref="TodoDto"/>.</returns>
    public IReadOnlyList<TodoDto> GetAll() =>
        _repository.GetAll()
            .Select(ToDto)
            .OrderBy(dto => dto.Id)
            .ToList();

    /// <summary>
    /// Returns a single todo item.
    /// </summary>
    /// <param name="id">The identifier to look up.</param>
    /// <returns>The matching DTO, or <see langword="null"/> when not found.</returns>
    public TodoDto? Get(Guid id) =>
        _repository.Find(id) is { } item ? ToDto(item) : null;

    /// <summary>
    /// Creates a new todo item from the given request.
    /// </summary>
    /// <param name="request">The creation request.</param>
    /// <returns>The created item as a <see cref="TodoDto"/>.</returns>
    /// <exception cref="ArgumentException">Thrown when the request title is empty.</exception>
    public TodoDto Create(CreateTodoRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var item = MyApp.Domain.TodoItem.Create(request.Title);
        _repository.Add(item);
        return ToDto(item);
    }

    /// <summary>
    /// Sets the completion state of a stored todo item.
    /// </summary>
    /// <param name="id">The identifier of the item.</param>
    /// <param name="isCompleted">The new completion state.</param>
    /// <returns>The updated DTO, or <see langword="null"/> when the item does not exist.</returns>
    public TodoDto? SetCompletion(Guid id, bool isCompleted)
    {
        var existing = _repository.Find(id);
        if (existing is null)
        {
            return null;
        }

        var updated = existing.WithCompletion(isCompleted);
        _repository.Update(updated);
        return ToDto(updated);
    }

    /// <summary>
    /// Deletes a todo item.
    /// </summary>
    /// <param name="id">The identifier of the item.</param>
    /// <returns><see langword="true"/> when the item was deleted; otherwise <see langword="false"/>.</returns>
    public bool Delete(Guid id) =>
        _repository.Remove(id);

    private static TodoDto ToDto(MyApp.Domain.TodoItem item) =>
        new(item.Id, item.Title, item.IsCompleted);
}
