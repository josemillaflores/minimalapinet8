namespace CleanMinimalApi.Application.Tests.Unit.Common.Exceptions;

using Application.Authors.Entities;
using CleanMinimalApi.Application.Common.Enums;
using CleanMinimalApi.Application.Common.Exceptions;
using Shouldly;
using Xunit;

public class NotFoundExceptionTests
{
    [Fact]
    public void ThrowIfNull_ShouldNotThrow_NotFoundException()
    {
        // Arrange
        var entityType = EntityType.Author;
        var argument = new Author(Guid.NewGuid(), "FirstName", "LastName");

        // Act
        var result = Should.NotThrow(() =>
        {
            NotFoundException.ThrowIfNull(argument, entityType);

            return true;
        });

        // Assert
        result.ShouldBeTrue();
    }

    [Fact]
    public void ThrowIfNull_ShouldThrow_NotFoundException()
    {
        // Arrange
        var entityType = EntityType.Author;
        Author argument = null;

        // Act
        var result = Should.Throw<NotFoundException>(() =>
        {
            NotFoundException.ThrowIfNull(argument, entityType);

            return true;
        });

        // Assert
        _ = result.ShouldNotBeNull();

        result.Message.ShouldBe("The Author with the supplied id was not found.");
    }

    [Fact]
    public void Throw_ShouldThrow_NotFoundException()
    {
        // Arrange
        var entityType = EntityType.Author;

        // Act
        var result = Should.Throw<NotFoundException>(() =>
        {
            NotFoundException.Throw(entityType);

            return true;
        });

        // Assert
        _ = result.ShouldNotBeNull();

        result.Message.ShouldBe("The Author with the supplied id was not found.");
    }
    [Fact]
    public void Method_WhenArgumentIsNull_ThrowsException()
    {
        // Arrange
        var entityType = "SomeEntityType"; // Puede ser cualquier valor para entityType
        object argument = null;

        // Act & Assert
        var exception = Assert.Throws<Exception>(() =>
        {
            if (argument is null) Throw(entityType);
            {
                Throw(entityType);
            }
        });

        // Puedes agregar más aserciones sobre la excepción si es necesario
        Assert.Equal($"Mensaje esperado para {entityType}", exception.Message);
    }

    // Asumiendo que Throw es un método que lanza una excepción como:
    private void Throw(string entityType)
    {
        throw new Exception($"Mensaje esperado para {entityType}");
    }

}
