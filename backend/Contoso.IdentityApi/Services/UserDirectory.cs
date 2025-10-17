using System.Text.Json;
using System.Text.Json.Serialization;

namespace Contoso.IdentityApi.Services;

public interface IUserDirectory
{
    Task<DirectoryUser?> FindByEmailAsync(string email, CancellationToken ct = default);
}

public record DirectoryUser(
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("userId")] string UserId,
    [property: JsonPropertyName("blocked")] bool Blocked
);

/// <summary>
/// Simple JSON-backed user directory for demo purposes. Not for production.
/// Reloads file if timestamp changes to allow iterative edits without restart.
/// </summary>
public class JsonUserDirectory : IUserDirectory
{
    private readonly string _filePath;
    // private DateTime _lastRead = DateTime.MinValue;
    private Dictionary<string, DirectoryUser> _byEmail = new(StringComparer.OrdinalIgnoreCase);
    private readonly SemaphoreSlim _lock = new(1,1);

    public JsonUserDirectory(string filePath)
    {
        _filePath = filePath;
    }

    public async Task<DirectoryUser?> FindByEmailAsync(string email, CancellationToken ct = default)
    {
        await EnsureLoadedAsync(ct);
        _byEmail.TryGetValue(email.Trim(), out var user);
        return user;
    }

    private async Task EnsureLoadedAsync(CancellationToken ct)
    {
        var info = new FileInfo(_filePath);
        if (!info.Exists) return; // empty directory
        // if (info.LastWriteTimeUtc <= _lastRead) return;
        await _lock.WaitAsync(ct);
        try
        {
            info.Refresh();
            // if (info.LastWriteTimeUtc <= _lastRead) return; // double-check
            var options = new JsonSerializerOptions
            {
                PropertyNamingPolicy = null // Use Pascal case as in C# record
            };
            using var stream = File.OpenRead(_filePath);
            var data = await JsonSerializer.DeserializeAsync<List<DirectoryUser>>(stream, options, cancellationToken: ct) 
                       ?? new List<DirectoryUser>();
            _byEmail = data
                .Where(u => !string.IsNullOrWhiteSpace(u.Email))
                .GroupBy(u => u.Email.Trim(), StringComparer.OrdinalIgnoreCase)
                .Select(g => g.First())
                .ToDictionary(u => u.Email.Trim(), u => u, StringComparer.OrdinalIgnoreCase);
            // _lastRead = info.LastWriteTimeUtc;
        }
        finally
        {
            _lock.Release();
        }
    }
}
