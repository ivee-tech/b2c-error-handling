using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Contoso.IdentityApi.Tests;

public class UserValidationEndpointTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public UserValidationEndpointTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    private record Request(string email, string correlationId);
    private record Response(bool userExists, string? userId, string? userMessage, string? errorCode, bool journeyHasError);
    private record SimulationRequest(string scenario, string correlationId);
    private record SimulationResponse(bool userExists, string? userId, string? userMessage, string? errorCode, bool journeyHasError, int? retryAfter);

    [Fact]
    public async Task Existing_User_Returns_UserExists_True()
    {
        var req = new Request("alice.legacy@example.com", Guid.NewGuid().ToString());
        var response = await _client.PostAsJsonAsync("/users/validate", req);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<Response>();
        Assert.NotNull(payload);
        Assert.True(payload!.userExists);
        Assert.False(payload.journeyHasError);
        Assert.NotNull(payload.userId);
        Assert.Null(payload.errorCode);
    }

    [Fact]
    public async Task Blocked_User_Returns_Error()
    {
        var req = new Request("carol.blocked@example.com", Guid.NewGuid().ToString());
        var response = await _client.PostAsJsonAsync("/users/validate", req);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<Response>();
        Assert.NotNull(payload);
        Assert.False(payload!.userExists);
        Assert.True(payload.journeyHasError);
        Assert.Equal("idm.user.blocked", payload.errorCode);
    }

    [Fact]
    public async Task New_User_Returns_UserExists_False()
    {
        var req = new Request($"newuser-{Guid.NewGuid():N}@example.com", Guid.NewGuid().ToString());
        var response = await _client.PostAsJsonAsync("/users/validate", req);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<Response>();
        Assert.NotNull(payload);
        Assert.False(payload!.userExists);
        Assert.False(payload.journeyHasError);
        Assert.Null(payload.userId);
        Assert.Null(payload.errorCode);
    }

    [Fact]
    public async Task Simulate_Throttle_Error_Returns_RetryAfter()
    {
        var req = new SimulationRequest("throttle", Guid.NewGuid().ToString());
        var response = await _client.PostAsJsonAsync("/users/simulate-error", req);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<SimulationResponse>();
        Assert.NotNull(payload);
        Assert.True(payload!.journeyHasError);
        Assert.Equal("idm.throttle", payload.errorCode);
        Assert.Equal(15, payload.retryAfter);
        Assert.False(payload.userExists); // always false in simulation payload
    }
}
