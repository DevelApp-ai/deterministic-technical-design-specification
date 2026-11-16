using Microsoft.AspNetCore.Mvc;
using MyApp.Application;

namespace MyApp.Api.Controllers;

/// <summary>
/// CRUD endpoints for todo items.
/// </summary>
/// <remarks>
/// The controller talks only to <see cref="TodoService"/> and only through
/// DTOs — it never touches domain entities or the repository directly.
/// </remarks>
[ApiController]
[Route("api/todos")]
public sealed class TodosController : ControllerBase
{
    private readonly TodoService _service;

    /// <summary>
    /// Initializes a new instance of the <see cref="TodosController"/> class.
    /// </summary>
    /// <param name="service">The application-layer todo service.</param>
    public TodosController(TodoService service)
    {
        _service = service;
    }

    /// <summary>
    /// Lists all todo items.
    /// </summary>
    /// <returns>Every todo item currently stored.</returns>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<TodoDto>), StatusCodes.Status200OK)]
    public IActionResult GetAll() =>
        Ok(_service.GetAll());

    /// <summary>
    /// Returns a single todo item by identifier.
    /// </summary>
    /// <param name="id">The identifier of the item.</param>
    /// <returns>The requested item.</returns>
    /// <response code="404">No item with the given identifier exists.</response>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(TodoDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult Get(Guid id) =>
        _service.Get(id) is { } dto ? Ok(dto) : NotFound();

    /// <summary>
    /// Creates a new todo item.
    /// </summary>
    /// <param name="request">The creation request body.</param>
    /// <returns>The created item.</returns>
    /// <response code="400">The request body is missing or has an empty title.</response>
    [HttpPost]
    [ProducesResponseType(typeof(TodoDto), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public IActionResult Create([FromBody] CreateTodoRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (string.IsNullOrWhiteSpace(request.Title))
        {
            return BadRequest(new { error = "A todo item must have a non-empty title." });
        }

        var dto = _service.Create(request);
        return CreatedAtAction(nameof(Get), new { id = dto.Id }, dto);
    }

    /// <summary>
    /// Sets the completion state of a todo item.
    /// </summary>
    /// <param name="id">The identifier of the item.</param>
    /// <param name="isCompleted">The new completion state.</param>
    /// <returns>The updated item.</returns>
    /// <response code="404">No item with the given identifier exists.</response>
    [HttpPatch("{id:guid}")]
    [ProducesResponseType(typeof(TodoDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult SetCompletion(Guid id, [FromBody] bool isCompleted) =>
        _service.SetCompletion(id, isCompleted) is { } dto ? Ok(dto) : NotFound();

    /// <summary>
    /// Deletes a todo item.
    /// </summary>
    /// <param name="id">The identifier of the item.</param>
    /// <returns>No content on success.</returns>
    /// <response code="404">No item with the given identifier exists.</response>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult Delete(Guid id) =>
        _service.Delete(id) ? NoContent() : NotFound();
}
