using Xunit;
using MyApp.Domain;

namespace MyApp.UnitTests;

/// <summary>
/// Unit tests for <see cref="TodoItem"/>.
/// </summary>
public sealed class TodoItemTests
{
    /// <summary>
    /// Verifies that <see cref="TodoItem.Create"/> produces an uncompleted
    /// item with a trimmed title and a fresh identifier.
    /// </summary>
    [Fact]
    public void Create_ProducesUncompletedItemWithTrimmedTitle()
    {
        var item = TodoItem.Create("  Buy milk  ");

        Assert.Equal("Buy milk", item.Title);
        Assert.False(item.IsCompleted);
        Assert.NotEqual(Guid.Empty, item.Id);
    }

    /// <summary>
    /// Verifies that <see cref="TodoItem.Create"/> rejects empty titles.
    /// </summary>
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_RejectsEmptyTitles(string title) =>
        Assert.Throws<ArgumentException>(() => TodoItem.Create(title));

    /// <summary>
    /// Verifies that <see cref="TodoItem.WithCompletion"/> returns a new
    /// instance and leaves the original untouched.
    /// </summary>
    [Fact]
    public void WithCompletion_ReturnsNewInstanceWithoutMutatingOriginal()
    {
        var item = TodoItem.Create("Buy milk");
        var completed = item.WithCompletion(isCompleted: true);

        Assert.True(completed.IsCompleted);
        Assert.False(item.IsCompleted);
        Assert.Equal(item.Id, completed.Id);
    }
}
