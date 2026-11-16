using Xunit;
using MyApp.Application;
using MyApp.Domain;

namespace MyApp.UnitTests;

/// <summary>
/// Unit tests for <see cref="TodoService"/> using an in-memory repository.
/// </summary>
public sealed class TodoServiceTests
{
    private static TodoService NewService() =>
        new(new FakeTodoRepository());

    /// <summary>
    /// Verifies that a created item is returned by <see cref="TodoService.GetAll"/>.
    /// </summary>
    [Fact]
    public void Create_AddsItemToStore()
    {
        var service = NewService();

        var dto = service.Create(new CreateTodoRequest("Buy milk"));

        Assert.Equal("Buy milk", dto.Title);
        Assert.False(dto.IsCompleted);
        Assert.Contains(dto, service.GetAll());
    }

    /// <summary>
    /// Verifies that <see cref="TodoService.Get"/> finds an existing item
    /// and returns <see langword="null"/> for a missing one.
    /// </summary>
    [Fact]
    public void Get_ReturnsItemOrNull()
    {
        var service = NewService();
        var dto = service.Create(new CreateTodoRequest("Buy milk"));

        Assert.Equal(dto.Id, service.Get(dto.Id)?.Id);
        Assert.Null(service.Get(Guid.NewGuid()));
    }

    /// <summary>
    /// Verifies that <see cref="TodoService.SetCompletion"/> persists the
    /// new state and returns the updated DTO.
    /// </summary>
    [Fact]
    public void SetCompletion_UpdatesItem()
    {
        var service = NewService();
        var dto = service.Create(new CreateTodoRequest("Buy milk"));

        var updated = service.SetCompletion(dto.Id, isCompleted: true);

        Assert.NotNull(updated);
        Assert.True(updated.IsCompleted);
        Assert.True(service.Get(dto.Id)?.IsCompleted);
    }

    /// <summary>
    /// Verifies that <see cref="TodoService.Delete"/> removes the item and
    /// reports success only once.
    /// </summary>
    [Fact]
    public void Delete_RemovesItemOnce()
    {
        var service = NewService();
        var dto = service.Create(new CreateTodoRequest("Buy milk"));

        Assert.True(service.Delete(dto.Id));
        Assert.False(service.Delete(dto.Id));
        Assert.Null(service.Get(dto.Id));
    }

    /// <summary>
    /// Verifies that creating an item with an empty title fails, mirroring
    /// the domain guard, before anything is stored.
    /// </summary>
    [Fact]
    public void Create_RejectsEmptyTitleWithoutStoring()
    {
        var service = NewService();

        Assert.Throws<ArgumentException>(
            () => service.Create(new CreateTodoRequest("")));
        Assert.Empty(service.GetAll());
    }

    private sealed class FakeTodoRepository : ITodoRepository
    {
        private readonly Dictionary<Guid, TodoItem> _items = [];

        public IReadOnlyList<TodoItem> GetAll() => [.. _items.Values];
        public TodoItem? Find(Guid id) => _items.GetValueOrDefault(id);
        public void Add(TodoItem item) => _items[item.Id] = item;
        public void Update(TodoItem item) => _items[item.Id] = item;
        public bool Remove(Guid id) => _items.Remove(id);
    }
}
